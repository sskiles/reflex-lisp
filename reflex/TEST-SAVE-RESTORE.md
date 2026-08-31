# Save/Restore Test

Reproduces the `save-image` round-trip with executable core, history, and dexador pool rebuild.

## Sequence

```bash
cd /home/reflex/common-lisp/reflex
rm -f tst

# 1. Start the harness and prompt + save in one batch.
printf 'my name is Alex\n(reflex:save-image "tst" :executable t)\n\n' \
  | timeout 300 ./start-harness.sh
```

The LLM call takes a few seconds; `save-lisp-and-die` writes a 54 MB executable.

```bash
# 2. Run the saved executable and prompt.
printf 'what is my name?\n\n' | timeout 60 ./tst
```

## Expected output

```
[Restore Hook] Dexador pool rebuilt; NVIDIA_API_KEY refreshed.
Reflex image restarted from /home/reflex/common-lisp/reflex/tst
Endpoint:   https://integrate.api.nvidia.com/v1/chat/completions
Model:      openai/gpt-oss-20b
History:    0 message(s)

Reflex ready.
Endpoint:   https://integrate.api.nvidia.com/v1/chat/completions
Model:      openai/gpt-oss-20b
API key:    SET
History:    2 message(s)

Try: (setf reflex:*session-history* nil)
Or:  (reflex:ask "Say hello.")


--- Query Loop (empty line to exit) ---
 Lisp expressions (start with '(') are evaluated
 Anything else is sent to the LLM

Operator> 
Your name is Alex.
```

## Pass criteria

- No `CORRUPTION WARNING` / `Memory fault` messages.
- `History: 2 message(s)` in the banner (the user turn + assistant turn).
- LLM response `Your name is Alex.` (or similar that names the user).

## Implementation notes

The fix that made this work:

- `save-image` sets `dexador:*connection-pool*` to NIL and disables pooling
  before calling `save-lisp-and-die`. Just clearing the pool leaves the
  LRU-POOL object intact with closures over stale C pointers, which faults
  on first use after restore.
- `%post-restore` rebuilds the pool via `dexador:make-connection-pool` and
  re-enables pooling.
- Conversation history lives in `*session-history*` (defvar), not in a
  local let-binding, so it survives `save-lisp-and-die`.
- `%response-content` falls back to `reasoning_content` when `content` is
  null (gpt-oss-20b sometimes returns null content with reasoning only).

## Files involved

- `src/api.lisp` — `send-prompt`, `save-image`, `%post-restore`,
  `%response-content`, `*connection-pool*` handling.
- `src/reflex.lisp` — `*session-history*`, `agent-send`, `query-loop`.
- `src/package.lisp` — exports `*session-history*`.
