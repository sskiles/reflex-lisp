# Context Engine

A tiered prompt-assembly strategy that gives the agent a dense, relevant
context window — ~70–80% signal — instead of a sprawling one that wastes
tokens on stale turns.

## Design goal

After many turns of accumulated conversation, every new prompt should be
assembled from the **most relevant** material, not the most recent. The
context window is divided into four zones, each tuned for a different
kind of recall:

```
┌──────────────────────────────────────────────────────────────┐
│ Zone A — verbatim recent turns        (full fidelity)        │
│          last 2–4 user / assistant / tool exchanges          │
│          preserves exact wording, code, tool args            │
│          budget: ~30–40% of window                           │
├──────────────────────────────────────────────────────────────┤
│ Zone B — caveman mid-recent          (compressed continuity) │
│          previous 10–20 turns as U=… / A=… / R=… lines       │
│          good enough for "what were we doing 5 min ago"      │
│          budget: ~20–25% of window                           │
├──────────────────────────────────────────────────────────────┤
│ Zone C — semantically recalled history (caveman + ids)       │
│          brute-force cosine top-K over the full DB           │
│          includes short verbatim snippet for top 1–2 hits    │
│          budget: ~15–20% of window                           │
├──────────────────────────────────────────────────────────────┤
│ Zone D — system prompt + current query  (fixed overhead)     │
└──────────────────────────────────────────────────────────────┘
```

The target fill rate after extended use is **70–80%** of the model's
context window with high-relevance content. This holds even after
thousands of accumulated turns because zone C is gated by similarity,
not recency.

## Why three tiers

| Tier | Failure mode it avoids |
|---|---|
| **A (verbatim)** | The LLM cannot recover exact wording, code, or tool-call arguments from a compressed form. Recency-dependent detail (variable names, error messages, file paths) lives here. |
| **B (caveman)** | Full verbatim for everything is too expensive. Mid-recent turns are almost always relevant but rarely need exact wording. |
| **C (recalled)** | Pure recency windows miss the case where the user circles back to a topic discussed hours ago. Semantic search finds that exact case at low token cost. |

The caveman projection (grammar v1, see `src/context/caveman.lisp`) is
the bridge between zones B and C:

```
U3=fix the off-by-one in parse-args
A3=patched, added regression test
R3=22 tests pass
D4=ship it
F1=src/parser.lisp:142
```

The LLM can quote `U3=` back to the user, ask for expansion, or use it
as a decision anchor. Code identifiers, file paths, and decision verbs
are kept verbatim so the projection is reversible-ish.

## Storage layer

All three tiers read from the same SQLite table (`context`) defined in
`src/context/connect.lisp`. Columns:

```
id, ts, kind, role, content, content_hash, token_count,
session_id, turn_id, seq, tags,
embedding (BLOB), embed_model, embed_dim, embed_dtype, embed_norm,
caveman, caveman_tokens, caveman_v,
tool_name, tool_call_id
```

Indexes: `(session_id, seq)`, `(kind, ts)`, `content_hash`, `turn_id`.

The `caveman_v` column tracks the grammar version; helpers lazily
regenerate stale rows on read so the grammar can evolve without a full
rewrite.

## Embedding round trip

Embeddings are stored as **raw little-endian float32 BLOBs**, with
`embed_model`, `embed_dim`, and `embed_dtype` stored alongside. This
makes decoding unambiguous even if the model changes later.

```
pack:   #(0.0 1.0 2.0 3.0)
          │  for each float: ieee-floats:encode-float32 → 32 bits
          │  write 4 bytes little-endian
          ▼
        #(0 0 0 0  0 0 128 63  0 0 0 64  0 0 64 64)   ; 16-byte BLOB
          │
          ▼  stored in `embedding` column

unpack: 16-byte BLOB + dim=4
          │  for each i: assemble 4 bytes via logior/ash
          │  ieee-floats:decode-float32 → float
          ▼
        (0.0 1.0 2.0 3.0)   ; list of floats, ready for cosine
```

Cosine similarity (`%ctx-cosine` in `src/context/embedding.lisp`):

```
dot(a, b) / (‖a‖ · ‖b‖)
```

Returns 1.0 for identical vectors, 0.0 for orthogonal. The search
helper does brute-force top-K over the rows that match the optional
`session-id` filter.

## Assembly algorithm (proposed)

The public function will look roughly like:

```lisp
(context-assemble-prompt query
                         &key
                           (model *default-model*)
                           (token-budget 8000)
                           (verbatim-turns 4)
                           (caveman-turns 20)
                           (recall-k 8))
```

Steps:

1. **Reserve overhead.** Subtract `system-prompt` + `query` + response
   budget from the model's max context. The remainder is the working
   budget.

2. **Zone A — verbatim.** Fetch the last `verbatim-turns` rows for the
   current `session-id` ordered by `seq DESC`. Render each as a
   `[role] content` line. Stop when the zone hits ~35% of budget.

3. **Zone B — caveman mid-recent.** Fetch the next `caveman-turns`
   rows. For each row, use the cached `caveman` column; if missing or
   stale (`caveman_v < *caveman-version*`), call `context-caveman`
   which regenerates and writes back. Render as-is. Stop at ~55% of
   budget.

4. **Zone C — semantic recall.** Embed `query` (via the configured
   embedding model) and call `context-search` with `k=recall-k`,
   optionally filtered by `session-id`. For each result, render
   `caveman` line + a short verbatim snippet from `content` for the
   top 1–2 hits. Stop at ~75% of budget.

5. **Zone D — prepend system prompt + append query.**

The budget split (35/20/20) is a starting point and should be tunable
per session type. A coding session wants more verbatim; a research
session wants more recalled history.

## API surface (current and planned)

**Implemented** (`src/context/api-*.lisp`):

| Function | Purpose |
|---|---|
| `context-add` | Insert one row |
| `context-caveman` | Get/regenerate caveman projection for a row |
| `context-replay` | Build transcript (`:full` / `:caveman` / `:summary`) |
| `context-search` | Brute-force cosine top-K |

**Planned:**

| Function | Purpose |
|---|---|
| `context-assemble-prompt` | The tiered builder described above |
| `context-expander` (tool) | Let the LLM pull a full verbatim row given an id |
| `reflex.tools:context-add` | Tool so the agent can persist notes explicitly |
| `reflex.tools:context-search` | Tool so the agent can recall on demand |

## Integration points

Currently **nothing populates the table automatically**. Every turn
written to `*session-history*` should also be persisted via
`context-add` — a small change in `agent-send` (`src/reflex.lisp`).

Once `context-assemble-prompt` exists, `send-prompt` should call it
instead of passing `*session-history*` verbatim. The agent will then
get a dense, relevant window even after long sessions.

## Operational notes

- **DB location:** `~/.cache/reflex/reflex.sqlite` (override via
  `*context-db-path*`).
- **Schema bootstrap:** runs at load time, idempotent (`CREATE … IF NOT
  EXISTS`).
- **Connection per call:** no pooling, to avoid stale handles on
  `save-image` / restore.
- **Embedding model drift:** detectable via `embed_model` / `embed_dim`
  columns. Fix is a re-embed migration or versioned tables per model.
- **Scale:** brute-force cosine is fine to ~10k rows. Beyond that, add
  an HNSW index or pre-filter aggressively by `session-id`.
