(in-package #:reflex.context)

(defparameter *file-corpus*
  '(;; --- Top-level system files ---
    ("reflex.asd"                "ASDF system definitions for reflex and reflex/context subsystems, listing source files and dependencies")
    ("README.md"                 "Project readme with usage examples and quickstart instructions")
    ("REFLEX.md"                 "Reflex-specific design notes and architecture overview")
    ("AGENTS.md"                 "Notes for agents working on the reflex codebase")
    ("TODO.md"                   "Pending tasks and roadmap items")
    ("TEST-SAVE-RESTORE.md"      "Notes on the save-image and restore cycle, including Dexador pool handling")
    ("CONTEXT_ENGINE.md"         "Design document for the tiered context window: zone A verbatim, zone B caveman, zone C recall")
    ;; --- src/ core ---
    ("src/package.lisp"          "Reflex package definition, exports, and import-from for reflex.context")
    ("src/api.lisp"              "HTTP client for OpenAI-compatible chat completions: send-prompt, streaming, save-image, llm-request-error condition")
    ("src/reflex.lisp"           "Query loop, agent-send with tool-calling, save-image, menu cheat-sheet, *session-history* persistence")
    ;; --- src/tools/ ---
    ("src/tools/package.lisp"    "Reflex tools package definition")
    ("src/tools/registry.lisp"   "Tool registry: list-tools, execute-tool-call, tool definition storage")
    ("src/tools/define-tool.lisp " "define-tool macro for declaring a tool with a name, schema, and handler function")
    ("src/tools/eval-lisp.lisp"  "eval-lisp tool: evaluates a Common Lisp expression in the running image and returns the result")
    ("src/tools/read-file.lisp"  "read-file tool: reads a file from disk and returns its contents")
    ("src/tools/write-file.lisp" "write-file tool: writes content to a file, creating directories as needed")
    ("src/tools/edit-file.lisp"  "edit-file tool: applies targeted edits to a file by replacing exact strings")
    ("src/tools/bash.lisp"       "bash tool: runs a shell command and returns stdout, stderr, and exit code")
    ("src/tools/sqlite-sql.lisp" "sqlite-sql tool: executes a SQL query against the default reflex SQLite database")
    ;; --- src/context/ subsystem ---
    ("src/context/package.lisp"  "Reflex.context package definition and symbol exports")
    ("src/context/config.lisp"   "Configuration parameters: database path, table name, caveman version number")
    ("src/context/connect.lisp"  "SQLite connection helpers, schema DDL, and automatic bootstrap at load time")
    ("src/context/crypto.lisp"   "SHA-256 hashing via ironclad and a rough chars-per-4 token estimator")
    ("src/context/caveman.lisp"  "Caveman projection: truncate text and prefix with kind-specific letter for compact history")
    ("src/context/embedding.lisp" "Float32 little-endian embedding pack and unpack, L2 norm, cosine similarity")
    ("src/context/embed.lisp"    "Pluggable embedder interface: *embed-fn* and *embed-dim* for plugging in any embedding model")
    ("src/context/embed-nvidia.lisp" "NVIDIA integration API embeddings client using nvidia/nemotron-3-embed-1b for 2048-dim vectors")
    ("src/context/api-add.lisp"  "context-add: insert a row into the context table with optional embedding and tool metadata")
    ("src/context/api-caveman.lisp" "context-caveman: get the caveman projection for a row, regenerating it lazily if stale")
    ("src/context/api-replay.lisp" "context-replay: build a compact transcript for a session in full, caveman, or summary mode with token budget")
    ("src/context/api-search.lisp" "context-search: brute-force cosine top-K over stored embeddings, optionally filtered by session")
    ("src/context/budget.lisp"   "Per-zone budget allocation: verbatim 35%, caveman 25%, recall 20% of the total context window")
    ("src/context/zone-result.lisp" "zone-result struct plus one-line summary and multi-line detail helpers for feedback reports")
    ("src/context/zone-verbatim.lisp" "Zone A builder: fetch the last N turns for a session and render them verbatim")
    ("src/context/zone-caveman.lisp" "Zone B builder: fetch turns offset after zone A and render them in caveman form")
    ("src/context/zone-recall.lisp" "Zone C builder: semantic recall with verbatim snippet for the top two hits")
    ("src/context/report.lisp"   "Render the per-zone feedback report: line counts, token use, recall hit scores")
    ("src/context/assemble.lisp" "context-assemble-prompt orchestrator: builds the four zones and prints the feedback report")
    ("src/context/persist.lisp"  "Persist agent turns to the context table: %persist-turn, *persist-enabled*, *current-session-id*")
    ;; --- test/ ---
    ("test/test-api.lisp"        "Smoke tests for the HTTP client and chat completions endpoint")
    ("test/test-eval-lisp.lisp"  "Tests for the eval-lisp tool")
    ("test/test-file-tools.lisp" "Tests for read-file, write-file, and edit-file tools")
    ("test/test-sqlite.lisp"     "Tests for the sqlite-sql tool")
    ("test/test-reflex.lisp"     "Smoke tests for the reflex entry points and query loop")
    )
  "Mapping from filename to natural-language description.
Used by corpus-index to populate the context table with self-describing rows.")

(defun %ctx-override-caveman (row-id caveman-str)
  "Overwrite the cached caveman projection for ROW-ID with CAVEMAN-STR."
  (let ((db (%ctx-connect)))
    (unwind-protect
         (sqlite:execute-non-query
          db
          (format nil
                  "UPDATE ~A SET caveman=?, caveman_tokens=?, caveman_v=? WHERE id=?"
                  *context-table-name*)
          caveman-str
          (%ctx-estimate-tokens caveman-str)
          *caveman-version*
          row-id)
      (sqlite:disconnect db))))

(defun %ctx-embed-corpus-row (description embed-fn)
  "Embed DESCRIPTION for a corpus row.  Returns the vector or NIL."
  (and embed-fn (funcall embed-fn description)))

(defun %ctx-insert-corpus-row (session-id count path description embedding)
  "Insert one corpus row.  Returns the new row id, or NIL on error."
  (handler-case
      (context-add :session-id session-id
                   :seq count
                   :kind "file"
                   :role "file"
                   :content description
                   :tags (format nil "corpus,harness,~A" path)
                   :embedding embedding
                   :embed-model (and embedding *nvidia-embed-model*)
                   :tool-name path
                   :tool-call-id nil)
    (error (e)
      (format *error-output*
              "~&[corpus] failed to index ~A: ~A~%" path e)
      nil)))

(defun %ctx-index-file-corpus (&key (session-id "corpus") (embed-fn *embed-fn*))
  "Persist every entry in *FILE-CORPS* to the context table.
Each row stores the DESCRIPTION as content (so semantic search matches it)
and the PATH in the tool_name field (so we can recover which file it
points to).  The caveman projection is overridden to be F=<path>
so zone B shows the path directly.  Returns the number of rows inserted."
  (unless *file-corpus*
    (return-from %ctx-index-file-corpus 0))
  (let ((count 0))
    (dolist (entry *file-corpus*)
      (destructuring-bind (path description) entry
        (let* ((embedding (%ctx-embed-corpus-row description embed-fn))
               (row-id (%ctx-insert-corpus-row session-id (incf count)
                                               path description embedding)))
          (when row-id
            (%ctx-override-caveman row-id
                                    (format nil "F=~A" path))))))
    count))
