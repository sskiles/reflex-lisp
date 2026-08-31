# Tool Calls — TODO

Goal: let the LLM invoke tools from the chat-completions request. Each tool is
its own file so we can add, persist, and roll back tools independently.

## Tools to implement

1. **`eval-lisp`** — execute a Lisp expression in the running SBCL image.
   This is the highest-priority tool because it lets the agent extend itself
   and probe state. We build this one first.
2. **`read-file`** — read a file's contents (path → string).
3. **`write-file`** — create or overwrite a file (path + content).
4. **`edit-file`** — exact string replacement in a file (path + old + new).
5. **`bash`** — execute a shell command and capture stdout/stderr/exit code.

## Open architectural decisions

These need a decision before we cut code:

### A. Template vs bespoke

Two options:

- **Template** — define a `define-tool` macro that takes the function, name,
  description, and parameter schema, and registers it. Saves repetition,
  forces consistent schema/error handling, easier to add new tools. Each
  tool file is then a thin wrapper around `define-tool`.
- **Bespoke** — each tool file defines its own JSON schema, dispatch, and
  error handling. More flexibility, more duplication.

Recommendation: **template**. The four file tools all take `path` plus a
string field; `bash` and `eval-lisp` are similar. A `define-tool` macro
that emits a tool-callable function plus its schema would let us write each
tool in ~10 lines.

### B. Tool registration

Tools need to be:

- discoverable from the JSON schema sent to the LLM (`tools` array),
- callable when the LLM returns a `tool_calls` payload,
- persistable across save/restore (since we want `*session-history*` and
  tool definitions to survive a core save).

Recommendation: a `*tools*` defvar holding an alist of `name → tool`
entries. Each tool entry has `(name function description parameters)`.
`sending-prompt` automatically appends `*tools*` to the request; the
response loop dispatches `tool_calls` by looking up the name in `*tools*`.

### C. File layout

```
src/tools/
  package.lisp          ;; defines REFLEX.TOOLS package, exports REGISTER-TOOL,
                        ;;   DEFINE-TOOL, LIST-TOOLS, EXECUTE-TOOL-CALL
  define-tool.lisp      ;; the template macro
  registry.lisp         ;; *TOOLS* defvar + register/lookup
  eval-lisp.lisp        ;; eval-lisp tool (build first)
  read-file.lisp
  write-file.lisp
  edit-file.lisp
  bash.lisp
test/
  test-eval-lisp.lisp
  test-read-file.lisp
  test-write-file.lisp
  test-edit-file.lisp
  test-bash.lisp
```

### D. `eval-lisp` semantics

Need a decision on:

- **Sandboxing.** Do we let the agent eval anything (current reflex
  philosophy — full access to the image) or restrict to a sandbox? Arch3
  allowed full eval; we should match.
- **Output formatting.** Print to REPL only? Return as a string? Multi-
  value support?
- **Error handling.** `handler-case` around the eval, return the error
  message as the tool result (string), don't kill the agent loop.

Recommendation: full eval, return `format nil "~S" value` as the tool
result string (one-value), errors caught and returned as
`(format nil "ERROR: ~A" e)`.

### E. Test harness

Each tool gets a `test-<name>.lisp` in `test/` that:

- registers the tool,
- calls it directly with sample arguments,
- asserts the return shape (string, file content, exit code).

Tests run via `asdf:test-system :reflex` (already wired). They do not call
the LLM; they're unit tests on the tool function itself.

## Step-by-step plan

- [x] Decide A (template vs bespoke). Default: template.
- [x] Decide B (registration model). Default: `*tools*` alist.
- [x] Decide D (`eval-lisp` semantics). Default: full eval, `~S` output,
      errors as strings.
- [x] Create `src/tools/package.lisp`, `src/tools/registry.lisp`,
      `src/tools/define-tool.lisp`.
- [x] Implement `src/tools/eval-lisp.lisp`.
- [x] Write `test/test-eval-lisp.lisp`.
- [x] Wire tools into `send-prompt` (include `*tools*` in the request).
- [x] Wire tool-call dispatch into `agent-send` (parse response,
      call tool, append result to history).
- [x] Implement `read-file`, `write-file`, `edit-file`, `bash` (one
      file per tool, each with its own test).
- [ ] End-to-end test: prompt the LLM to "read /etc/hostname using
      read-file tool", verify the LLM invokes the tool and returns the
      result.

## Open questions for the user

1. Template vs bespoke? **template** (decided)
2. `eval-lisp` sandboxing? **none** (decided)
3. Should the tool registry persist across `save-image`? **yes** (decided)

## Implementation status

- `src/tools/package.lisp`, `registry.lisp`, `define-tool.lisp` exist.
- Tools implemented (one per file):
  - `eval-lisp` — evaluates a Lisp expression in the running SBCL image.
  - `read-file` — reads file contents as a string.
  - `write-file` — creates/overwrites a file with given content.
  - `edit-file` — exact-string-replace within a file.
  - `bash` — runs a shell command, returns stdout/stderr/exit code.
- `reflex:send-prompt` includes the `tools` array in every request and
  returns `values content tool-calls`.
- `reflex:agent-send` is a tool-calling loop: it sends, dispatches any
  tool calls, appends assistant+tool messages to `*session-history*`,
  re-prompts until the LLM stops calling tools (or
  `*max-tool-iterations*` is hit).
- Tests (`asdf:test-system :reflex` or `reflex-test:run-tests`):
  - `test-api` — request body shape, HTTP failure raises
    `llm-request-error`.
  - `test-eval-lisp` — arithmetic, strings, symbols, lists, errors,
    side-effects, cross-package access.
  - `test-file-tools` — read/write/edit file contents, shell commands,
    error paths.

## Next steps

1. End-to-end smoke: prompt "read /etc/hostname using read-file tool",
   verify the LLM invokes the tool and returns the hostname.  (Blocked
   on slow NVIDIA API today.)
2. Improve `bash` tool: capture exit codes properly, better timeout
   reporting.
3. Add `glob` and `grep` tools for code-search workflows.
4. Persistence: ensure tools persist across `save-image` (they do,
   because `*tools*` is a defvar; verify by saving with tools loaded
   and restarting).

