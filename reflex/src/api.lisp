(in-package #:reflex)

;;; Default endpoint parameters

(defparameter *default-endpoint* "https://integrate.api.nvidia.com/v1/chat/completions")
(defparameter *default-model* "openai/gpt-oss-20b")
(defparameter *default-api-key* (uiop:getenv "NVIDIA_API_KEY"))

(defparameter *default-system-prompt*
  "You are a coding agent with access to a file system, shell, AND a live Lisp image.

Available tools:
- read-file: Read a file's contents
- write-file: Create or overwrite a file
- edit-file: Make exact string replacements in a file
- bash: Execute shell commands
- eval-lisp: Evaluate a Lisp expression in the running SBCL image (use this to actually RUN Lisp code, not just print it)
- query: Eval-if-Lisp-or-ask-LLM (input starting with '(' is evaluated, else sent to LLM)
- save-image: Save the entire Lisp state to a .core file

IMPORTANT: When the user gives you Lisp code or asks you to write/run Lisp, USE THE EVAL-LISP TOOL to actually execute it. Do not just print code snippets — execute them and report the actual results. The running image is fully accessible: you can define functions, modify variables, load files, and inspect any state via eval-lisp.

LISP CODING BEST PRACTICES:
- Use functional programming paradigms where practical.
- Prioritize tail recursion, clean lexical bindings (LET, LET*), and robust error handling (handler-case, restart-case).
- Document packages, classes, and complex functions with clear docstrings.
- Before committing edits, run Lisp code and tests locally via the `eval-lisp` tool to confirm correctness.
- The running SBCL image is fully interactive and live; modify variables, redefine functions, and inspect state dynamically.

Work in the current directory. Prefer reading files before editing. Be concise. Show your work by executing code, not just describing it."
  "Default system prompt used by SEND-PROMPT and ASK.")

(defvar *default-history* nil
  "Default conversation history used by SEND-PROMPT and ASK.
Each element is an alist of the form ((\"role\" . \"user\") (\"content\" . \"...\")) or
((\"role\" . \"assistant\") (\"content\" . \"...\")).  When NIL the request contains
only the system message (if any) and the new user turn.")

;;; --- Restore hook -------------------------------------------------------
;; Run automatically by SBCL whenever a saved core is restored.
;; Resets foreign resources (dexador's connection pool) and refreshes the
;; API key from the environment so a core saved with an unset key picks up
;; the current value when reloaded.

(defun %post-restore ()
  (setf *default-api-key* (uiop:getenv "NVIDIA_API_KEY"))
  (let ((pool-var (find-symbol "*CONNECTION-POOL*" "DEXADOR"))
        (use-var  (find-symbol "*USE-CONNECTION-POOL*" "DEXADOR"))
        (make-fn  (find-symbol "MAKE-CONNECTION-POOL" "DEXADOR")))
    ;; The saved image intentionally has *CONNECTION-POOL* = NIL (see
    ;; SAVE-IMAGE).  Build a fresh LRU-POOL and re-enable pooling so the
    ;; steady-state connection cache works.
    (when (and pool-var (boundp pool-var) make-fn (fboundp make-fn))
      (setf (symbol-value pool-var) (funcall make-fn)))
    (when (and use-var (boundp use-var))
      (setf (symbol-value use-var) t)))
  (format t "~&[Restore Hook] Dexador pool rebuilt; NVIDIA_API_KEY refreshed.~%"))

(eval-when (:load-toplevel :execute)
  ;; Modern SBCL: register as an init hook so it runs after the core loads.
  (pushnew #'%post-restore sb-ext:*init-hooks*)
  ;; Older SBCL: register-restore-hook was the way.  Defensive lookup.
  (let ((hook (find-symbol "REGISTER-RESTORE-HOOK" "SB-EXT")))
    (when (and hook (fboundp hook))
      (funcall hook #'%post-restore))))

;;; HTTP client for an OpenAI-compatible chat-completions endpoint.

(defun %request-headers (api-key)
  "Return HTTP request headers for the chat-completions request."
  (append '(("Content-Type" . "application/json"))
          (when api-key
            (list (cons "Authorization"
                        (format nil "Bearer ~A" api-key))))))

(defun %request-body (model prompt system-prompt history tools temperature max-tokens top-p stop)
  "Encode PROMPT, SYSTEM-PROMPT, HISTORY, and TOOLS as an OpenAI-compatible
chat-completions request body. TOOLS is a list of tool schemas or NIL."
  (json:encode-json-alist-to-string
   (append
    `(("model" . ,model)
      ("messages" . ,(append
                      (when system-prompt
                        (list (list (cons "role" "system")
                                    (cons "content" system-prompt))))
                      history
                      (list (list (cons "role" "user")
                                  (cons "content" prompt))))))
    (when (and tools (consp tools))
      (list (cons "tools" tools)))
    (when temperature
      (list (cons "temperature" temperature)))
    (when max-tokens
      (list (cons "max_tokens" max-tokens)))
    (when top-p
      (list (cons "top_p" top-p)))
    (when stop
      (list (cons "stop" stop))))))

(defun %json-value (key object)
  "Return the value associated with KEY in decoded JSON alist OBJECT."
  (cdr (assoc key object)))

(defun %response-content (body)
  "Extract the first assistant message from a JSON response BODY string.
Returns (values content tool-calls) where CONTENT is the message text (or
empty string) and TOOL-CALLS is a list of (id . ((name . name) (arguments .
decoded-args))) alists."
  (let ((decoded (handler-case
                     (json:decode-json-from-string body)
                   (error () nil))))
    (let* ((choices (and decoded (%json-value :CHOICES decoded)))
           (first-choice (and (listp choices) (first choices)))
           (message (and first-choice (%json-value :MESSAGE first-choice)))
           (content (and message (%json-value :CONTENT message)))
           (reasoning (or (and message (%json-value :REASONING_CONTENT message))
                          (and decoded (%json-value :REASONING_CONTENT decoded))
                          (and decoded (%json-value :REASONING decoded))))
           (raw-tool-calls (and message (%json-value :TOOL_CALLS message))))
      (let ((final-content
              (cond
                ((and content (stringp content) (not (zerop (length content))))
                 content)
                ((and reasoning (stringp reasoning) (not (zerop (length reasoning))))
                 reasoning)
                (t "")))
            (parsed-calls
              (when raw-tool-calls
                (mapcar (lambda (tc)
                          (let* ((id       (or (%json-value :ID tc)
                                               (cdr (assoc "id" tc :test #'string=))))
                                 (function (or (%json-value :FUNCTION tc)
                                               (cdr (assoc "function" tc :test #'string=))))
                                 (name     (or (and function (%json-value :NAME function))
                                               (and function (cdr (assoc "name" function :test #'string=)))))
                                 (args-raw (or (and function (%json-value :ARGUMENTS function))
                                               (and function (cdr (assoc "arguments" function :test #'string=)))))
                                 (args     (cond
                                             ((null args-raw) nil)
                                             ((stringp args-raw)
                                              (handler-case (json:decode-json-from-string args-raw)
                                                (error () args-raw)))
                                             (t args-raw))))
                            (list (cons :id id)
                                  (cons :name name)
                                  (cons :arguments args))))
                        raw-tool-calls))))
        (values final-content parsed-calls)))))

(define-condition llm-request-error (error)
  ((url :initarg :url :reader llm-request-error-url)
   (status :initarg :status :reader llm-request-error-status)
   (body :initarg :body :reader llm-request-error-body))
  (:report
   (lambda (condition stream)
     (format stream "LLM request to ~A failed with HTTP status ~A~%"
             (llm-request-error-url condition)
             (llm-request-error-status condition))
     (format stream "Response body: ~A" (llm-request-error-body condition))))
  (:documentation "Signalled when the endpoint returns a non-2xx response."))

(defun send-prompt (prompt &key
                    (endpoint *default-endpoint*)
                    (model *default-model*)
                    (api-key *default-api-key*)
                    (system-prompt *default-system-prompt*)
                    (history *default-history*)
                    (tools (and (find-package :reflex.tools)
                                (boundp 'reflex.tools:*tools*)
                                (reflex.tools:tool-schemas-for-llm)))
                    (temperature 0.7d0)
                    (max-tokens 512)
                    (top-p 1.0d0)
                    stop
                    (request-function #'dexador:request))
  "Send PROMPT to an OpenAI-compatible chat-completions endpoint.

PROMPT is the string sent as the current user message.  ENDPOINT defaults to
*DEFAULT-ENDPOINT*, MODEL to *DEFAULT-MODEL*, API-KEY to *DEFAULT-API-KEY*,
SYSTEM-PROMPT to *DEFAULT-SYSTEM-PROMPT*, HISTORY to *DEFAULT-HISTORY*, and
TOOLS to the schemas of every registered tool in REFLEX.TOOLS:*TOOLS*.

Returns two values: the response content string and a list of tool-call
alists of the shape ((:ID . \"...\") (:NAME . \"...\") (:ARGUMENTS . alist)).
Tool-call alists are non-empty only when the LLM chose to invoke tools.

REQUEST-FUNCTION exists primarily for tests and protocol adapters; it is called
with the same arguments accepted by DEXADOR:REQUEST."
  (let* ((use-pool-var (find-symbol "*USE-CONNECTION-POOL*" "DEXADOR"))
         (api-key (or api-key (uiop:getenv "NVIDIA_API_KEY"))))
    (unwind-protect
         (progn
           ;; Re-enable pooling for this request if it was disabled by the
           ;; restore hook (so we keep pooling for steady-state operation
           ;; but the first request after restore never reuses a stale handle).
           (when (and use-pool-var (boundp use-pool-var))
             (setf (symbol-value use-pool-var) t))
           (multiple-value-bind (body status response-headers response-uri response-method)
               (funcall request-function
                        endpoint
                        :method :post
                        :headers (%request-headers api-key)
                        :content (%request-body model prompt system-prompt history tools temperature max-tokens top-p stop))
             (declare (ignore response-headers response-uri response-method))
             (unless (and (integerp status)
                          (<= 200 status)
                          (<= status 299))
               (error 'llm-request-error
                      :url endpoint
                      :status status
                      :body body))
             (%response-content body))))))

(defun ask (prompt &rest options)
  "Convenience wrapper around SEND-PROMPT."
  (apply #'send-prompt prompt options))

;;; --- History helpers ----------------------------------------------------

(defun make-message (role content)
  "Build a single OpenAI-style message alist with ROLE (\"user\", \"assistant\" or \"system\") and CONTENT."
  (list (cons "role" role)
        (cons "content" content)))

(defun append-turn (history user-prompt assistant-reply)
  "Append a user/assistant turn to HISTORY and return the new list."
  (append history
          (list (make-message "user" user-prompt)
                (make-message "assistant" assistant-reply))))

;;; --- Image save/load ----------------------------------------------------

(defun save-image (core-path &key (executable nil))
  "Save the running SBCL image to CORE-PATH.

When EXECUTABLE is non-nil, embed an :executable t core so the resulting file
is a standalone binary.  The default (EXECUTABLE NIL) saves a plain .core
file that must be restarted with
  sbcl --core CORE-PATH
which avoids the integrity check that :executable t cores perform.

Before saving, dexador's connection pool is destroyed (set to NIL) and pooling
is disabled so that no live foreign handles (libcurl, SSL) are baked into the
image.  After restore, %post-restore re-enables pooling so steady-state
operation keeps the connection cache."
  (let ((pool-var (find-symbol "*CONNECTION-POOL*" "DEXADOR"))
        (use-var  (find-symbol "*USE-CONNECTION-POOL*" "DEXADOR"))
        (clear-fn (find-symbol "CLEAR-CONNECTION-POOL" "DEXADOR"))
        (make-fn  (find-symbol "MAKE-CONNECTION-POOL" "DEXADOR")))
    ;; Pre-save cleanup:
    ;; 1. Disable pooling so the first request after restore cannot reuse
    ;;    a stale handle.
    ;; 2. Clear the pool so any cached connections are released.
    ;; 3. Null out *connection-pool* entirely.  The LRU-POOL object holds
    ;;    closures over C pointers (libcurl handles); just clearing the table
    ;;    does not dispose of those closures, and they cause memory faults
    ;;    when the saved image is restored.  Replacing the variable with NIL
    ;;    lets dexador build a fresh pool on first use.
    (when (and use-var (boundp use-var))
      (setf (symbol-value use-var) nil))
    (when (and pool-var (boundp pool-var) clear-fn (fboundp clear-fn))
      (funcall clear-fn))
    (when (and pool-var (boundp pool-var))
      (setf (symbol-value pool-var) nil))
    (let* ((path (merge-pathnames core-path))
           (top-level (lambda ()
                        (format t "~&Reflex image restarted from ~A~%" path)
                        (format t "Endpoint:   ~A~%" *default-endpoint*)
                        (format t "Model:      ~A~%" *default-model*)
                        (format t "History:    ~A message(s)~%" (length *default-history*))
                        (start))))
      (declare (ignore make-fn))
      (if executable
          (sb-ext:save-lisp-and-die path :toplevel top-level :executable t)
          (sb-ext:save-lisp-and-die path :toplevel top-level)))))
