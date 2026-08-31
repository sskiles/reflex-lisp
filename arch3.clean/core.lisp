;;;; harness/core.lisp - Main entry point, wires all stages

(defpackage #:harness.core
  (:use #:cl
        #:harness.tools.protocol
        #:harness.tools.registry
        #:harness.stage-0.protocol
        #:harness.stage-0.nvidia
        #:harness.stage-1.protocol
        #:harness.stage-1.eval-loop
        #:harness.stage-3.protocol
        #:harness.stage-4.tools)
  (:shadow #:start
           #:agent-send
           #:query-loop
           #:show-history
           #:show-stats)
  (:export #:start
           #:agent-send
           #:query-loop
           #:reset-history
           #:show-history
           #:show-tools
           #:show-stats
           #:set-system-prompt
           #:change-model
           #:list-models
           #:refresh-models
           #:save-image
           #:start-swank-server
           #:*harness*
           #:*provider*
           #:*registry*
           #:*history-manager*
           #:*eval-loop*))

(in-package #:harness.core)

;;; --- Global Harness State --------------------------------------------------

(defstruct harness
  (provider nil :type (or null provider))
  (registry nil :type (or null tool-registry))
  (history-manager nil :type (or null history-manager))
  (eval-loop nil)
  (config nil :type (or null eval-loop-config))
  (running-p nil :type boolean))

(defvar *harness* nil "Global harness instance.")
(defvar *provider* nil "Current provider.")
(defvar *registry* nil "Current tool registry.")
(defvar *history-manager* nil "Current history manager.")
(defvar *eval-loop* nil "Current eval loop.")
(defvar *current-provider* nil "Bound dynamically for model/refresh tools.")
(defvar *current-config* nil "Current eval loop config.")
(defvar *current-eval-loop* nil "Current eval loop function.")


;;; --- Initialization --------------------------------------------------------

(defun make-default-provider ()
  (make-nvidia-provider))

(defun make-default-registry ()
  (let ((reg (make-instance 'tool-registry)))
    ;; Register built-in eval-lisp tool (Stage 1)
    (let ((spec (get-lisp-eval-tool-spec)))
      (register-tool reg spec))
    ;; Register standard tools (Stage 4)
    (register-standard-tools reg)
    reg))

(defun make-default-history-manager (&key (model "openai/gpt-oss-20b") (max-tokens 6000))
  (create-history-manager :model model :max-tokens max-tokens))

(defun initialize-harness (&key provider registry history-manager
                           (system-prompt nil)
                           (max-iterations 10))
  "Create and wire all components."
  (let ((prov (or provider (make-default-provider)))
        (reg (or registry (make-default-registry)))
        (hist (or history-manager (make-default-history-manager
                                    :model (provider-config-default-model (provider-config (or provider (make-default-provider))))
                                    :max-tokens (floor (* (provider-model-context-size (or provider (make-default-provider))
                                                            (provider-config-default-model (provider-config (or provider (make-default-provider)))))
                                                          0.7))))))
    
    ;; Create eval-loop config with history wrapping (Stage 3 wraps Stage 1)
    (let ((base-config (make-eval-loop-config*
                        :provider prov
                        :tool-registry reg
                        :max-iterations max-iterations
                        :system-prompt system-prompt)))
      
      (let ((wrapped-config (make-history-aware-config base-config hist))
            (loop-fn #'eval-loop))
        
        (setf *harness* (make-harness
                         :provider prov
                         :registry reg
                         :history-manager hist
                         :eval-loop loop-fn
                         :config wrapped-config
                         :running-p t))
        
        (setf *provider* prov)
        (setf *registry* reg)
        (setf *history-manager* hist)
        (setf *eval-loop* loop-fn)
        (setf *current-provider* prov)
        (setf *current-config* wrapped-config)
        (setf *current-eval-loop* loop-fn)
        
        *harness*))))


;;; --- Public API (matches original harness.lisp entry points) --------------

(defun start (&key provider registry history-manager
                (system-prompt "You are a coding agent with access to a file system, shell, a live Lisp image, and a hybrid semantic/chronological memory manager.

Your primary objective is to maintain, optimize, and augment the running Lisp environment. Ensure functions, libraries, and custom states you define persist or are logged in the memory store.

Available tools:
- read-file: Read a file's contents
- write-file: Create or overwrite a file
- edit-file: Make exact string replacements in a file
- bash: Execute shell commands
- eval-lisp: Evaluate a Lisp expression in the running SBCL image
- query: Eval if Lisp, else ask LLM (handled by eval-loop)
- save-image: Save the entire Lisp state to a .core file
- refresh-model-list: Refresh model list from NVIDIA API
- model: Manage LLM model (list, select, current)
- memory-db: Perform CRUD operations on the persistent semantic/chronological SQLite database (actions: insert, find, update, delete)

PERSISTENT MEMORY & SEMANTIC CRUD:
You can manage facts, conventions, and rules using the `memory-db` tool (recommended) or the Lisp API (`harness.stage-0.db` package):
Using the `memory-db` tool:
- Create Fact: action=\"insert\", session_id=\"kb_facts\", role=\"system\", content=\"Fact: Custom Lisp utilities package\"
- Read/Search Facts: action=\"find\", session_id=\"kb_facts\", content=\"search query\"
- Update Fact: action=\"update\", id=123, content=\"New fact content\" (triggers background re-embedding)
- Delete Fact: action=\"delete\", id=123

Alternatively, via Lisp:
- Create Fact: (harness.stage-0.db:insert-message :session-id \"kb_facts\" :role \"system\" :content-raw \"Fact: Custom Lisp utilities package\")
- Read Facts: Query the namespace (e.g. \"kb_facts\" or \"kb_user_rules\") via (harness.stage-0.db:semantic-search-messages query-vector :session-id \"kb_facts\").
- Update Fact: (harness.stage-0.db:update-message id :content-raw \"New fact content\" :processed 0) (resets processed status to trigger re-embedding).
- Delete Fact: (harness.stage-0.db:delete-message id)

LISP CODING BEST PRACTICES:
- Use functional programming paradigms where practical.
- Prioritize tail recursion, clean lexical bindings (LET, LET*), and robust error handling (handler-case, restart-case).
- Document packages, classes, and complex functions with clear docstrings.
- Before committing edits, run Lisp code and tests locally via the `eval-lisp` tool to confirm correctness.
- The running SBCL image is fully interactive and live; modify variables, redefine functions, and inspect state dynamically.

Work in the current directory. Prefer reading files before editing. Be concise. Show your work by executing code, not just describing it.")
                (max-iterations 10))
  "Initialize the harness and print status."
  (initialize-harness :provider provider
                      :registry registry
                      :history-manager history-manager
                      :system-prompt system-prompt
                      :max-iterations max-iterations)
  (format t "~&=== Harness Ready ===~%")
  (format t "Provider: ~A (~A)~%" (provider-name *provider*) (provider-config-default-model (provider-config *provider*)))
  (format t "Tools: ~A registered~%" (hash-table-count (registry-tools *registry*)))
  (format t "History: ~A tokens max (~A% of model context)~%"
          (history-max-tokens *history-manager*)
          (round (* 100 (history-context-percentage *history-manager*))))
  (format t "~%Entry points:~%")
  (format t "  (agent-send \"msg\")     - Full agent loop~%")
  (format t "  (query-loop)            - Interactive REPL~%")
  (format t "  (reset-history)         - Clear conversation~%")
  (format t "  (show-history [n])      - Show last N messages~%")
  (format t "  (show-tools)            - List available tools~%")
  (format t "  (show-stats)            - Token usage stats~%")
  (format t "  (change-model \"name\")  - Switch model~%")
  (format t "  (list-models)           - List available models~%")
  (format t "  (refresh-models)        - Refresh model list from API~%")
  (format t "  (save-image \"path\")    - Save Lisp image~%")
  (format t "  (start-swank-server)    - Start Swank server~%")
  (values))

(defun agent-send (user-input &key (model nil))
  "Send user input to agent, run full loop until final response."
  (declare (ignore model))
  (unless *harness* (start))
  (format t "~&---------~%")
  (let ((*current-provider* *provider*))
    (let ((result (eval-loop user-input (harness-config *harness*))))
      (if (eval-result-error result)
          (progn
            (format t "Error: ~A~%" (eval-result-error result))
            (format t "---------~%"))
          (progn
            (format t "Thinking:~%")
            (format t "~A~%" (or (eval-result-thinking result) "Analyzing prompt and generating response..."))
            (format t "---------~%")
            (when (eval-result-content result)
              (format t "~A~%" (eval-result-content result)))
            (when (eval-result-usage result)
              (format t "    [usage: ~A prompt + ~A completion = ~A total]~%"
                      (or (json-get (eval-result-usage result) "prompt_tokens") 0)
                      (or (json-get (eval-result-usage result) "completion_tokens") 0)
                      (or (json-get (eval-result-usage result) "total_tokens") 0)))
            (format t "---------~%")))
      (eval-result-content result))))

(defun query-loop ()
  "Interactive read-line loop. Lisp expressions (starting with '(') are evaluated directly.
   Everything else goes through the full agent loop (matches original harness.lisp)."
  (unless *harness* (start))
  (format t "~&~%--- Query Loop (empty line to exit) ---~%")
  (format t "    Lisp expressions (start with '(') are evaluated directly~%")
  (format t "    Anything else is sent to the agent~%~%")
  (loop for line = (progn (format t "~&Operator> ") (finish-output) (read-line *standard-input* nil nil))
        while (and line (string/= line ""))
        do (handler-case
               (if (and (> (length line) 0) (char= (char line 0) #\())
                   ;; Direct Lisp eval (matches original query-loop)
                   (progn
                     (format t "~&---------~%")
                     (let* ((expr (read-from-string line))
                            (result (eval expr)))
                       (format t "~A~%" result))
                     (format t "---------~%"))
                   ;; Agent loop
                   (let ((*current-provider* *provider*))
                     (agent-send line)))
             (error (e)
               (format t "~&---------~%")
               (format t "⚠️  ~A~%" e)
               (format t "---------~%")))))

(defun reset-history ()
  (when *history-manager* (clear-history *history-manager*))
  (format t "~&History reset.~%"))

(defun show-history (&optional (n 20))
  (when *history-manager*
    (format t "~&=== Last ~A messages (~A tokens) ===~%"
            (min n (length (history-messages *history-manager*)))
            (history-token-count *history-manager*))
    (let ((msgs (last (history-messages *history-manager*) n)))
      (dolist (msg msgs)
        (format t "~&[~A] ~A (~A tok): ~A~%"
                (history-message-timestamp msg)
                (history-message-role msg)
                (history-message-tokens msg)
                (subseq (history-message-content msg) 0 (min 80 (length (history-message-content msg)))))))))

(defun show-tools ()
  (when *registry* (list-tools *registry*)))

(defun show-stats ()
  (when *history-manager* (show-stats *history-manager*)))

(defun set-system-prompt (text)
  (when *harness*
    (setf (eval-loop-config-system-prompt (harness-config *harness*)) text)
    (format t "~&System prompt updated (~A chars).~%" (length text))))

(defun change-model (model-name)
  "Change the active model. Updates provider config and history limits."
  (when *provider*
    (let ((config (provider-config *provider*)))
      (when (gethash model-name (provider-config-context-sizes config))
        (setf (provider-config-default-model config) model-name)
        ;; Update history manager limits
        (when *history-manager*
          (setf (history-model *history-manager*) model-name)
          (setf (history-max-tokens *history-manager*)
                (floor (* (provider-model-context-size *provider* model-name)
                          (history-context-percentage *history-manager*))))
          (prune-to-max-tokens *history-manager*))
        (format t "~&Model changed to: ~A (context: ~A tokens)~%"
                model-name (provider-model-context-size *provider* model-name))
        t))))

(defun list-models ()
  (when *provider*
    (let ((models (provider-list-models *provider*)))
      (format t "~&=== Available Models ===~%")
      (format t "Current: ~A~%~%" (provider-config-default-model (provider-config *provider*)))
      (dolist (m models)
        (format t "  ~A ~A tokens~:[~; (current)~]~%"
                (getf m :id) (getf m :context-size)
                (string= (getf m :id) (provider-config-default-model (provider-config *provider*)))))
      models)))

(defun refresh-models ()
  (when *provider*
    (provider-list-models *provider*)))

(defvar *save-hooks* '()
  "List of functions to call before saving a Lisp image.")

(defun register-save-hook (fn)
  "Register a function to run before saving the Lisp image."
  (pushnew fn *save-hooks*))

(defun run-save-hooks ()
  "Run all registered save hooks."
  (dolist (hook *save-hooks*)
    (handler-case (funcall hook)
      (error (e) (format t "~&[Save Hook Error] ~A~%" e)))))

;; Register database and thread cleanup to execute before save-lisp-and-die
(register-save-hook
 (lambda ()
   (when (find-package "HARNESS.STAGE-0.ASYNC-PROCESSOR")
     (let ((stop-sym (find-symbol "STOP-BACKGROUND-PROCESSOR" "HARNESS.STAGE-0.ASYNC-PROCESSOR")))
       (when (and stop-sym (fboundp stop-sym))
         (format t "~&[Save Hook] Stopping background processor thread...~%")
         (funcall stop-sym))))
   (when (find-package "HARNESS.STAGE-0.DB")
     (let ((close-sym (find-symbol "CLOSE-DB" "HARNESS.STAGE-0.DB")))
       (when (and close-sym (fboundp close-sym))
         (format t "~&[Save Hook] Closing database connection...~%")
         (funcall close-sym))))))

(defun save-image (path &key (purify t))
  "Save the running Lisp image to a .core file."
  (format t "~&Preparing save image... Running save hooks.~%")
  (run-save-hooks)
  (format t "~&Saving image to ~A...~%" path)
  (sb-ext:save-lisp-and-die path :executable t :purify purify))

(defun start-swank-server (&key (port 4005))
  "Start a Swank server for remote REPL access (matches original harness.lisp)."
  (format t "~&Starting Swank server on port ~A...~%" port)
  (let ((swank-pkg (find-package :swank)))
    (if swank-pkg
        (let ((server (funcall (find-symbol "CREATE-SERVER" swank-pkg)
                                :port port :dont-close t)))
          (format t "~&Swank server listening on port ~A (server: ~A)~%" port server)
          server)
        (progn
          (format t "~&Swank not loaded, cannot start server~%")
          nil))))

;;; --- REPL Convenience ------------------------------------------------------

(defun apropos-harness (string)
  "Search harness symbols."
  (apropos string "HARNESS.CORE"))

(format t "~&[harness.core] Loaded. Call (harness.core:start) to initialize.~%")