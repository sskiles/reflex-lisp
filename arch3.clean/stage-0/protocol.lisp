;;;; harness/stage-0/protocol.lisp - Provider protocol (Stage 0)

(defpackage #:harness.stage-0.protocol
  (:use #:cl #:harness.tools.protocol)
  (:export
   #:provider
   #:provider-name
   #:provider-config
   #:make-provider-config
   #:make-provider-config*
   #:config-api-key
   #:config-base-url
   #:config-model
   #:config-temperature
   #:config-max-tokens
   #:config-timeout
   #:provider-call
   #:provider-stream
   #:provider-list-models
   #:provider-model-context-size
   #:provider-refresh-models
   #:provider-error
   #:provider-auth-error
   #:provider-rate-limit-error
   #:provider-timeout-error
   #:provider-connection-error
   ;; Provider config accessors
   #:provider-config-name
   #:provider-config-api-key
   #:provider-config-base-url
   #:provider-config-default-model
   #:provider-config-default-temperature
   #:provider-config-default-max-tokens
   #:provider-config-timeout
   #:provider-config-extra-headers
   #:provider-config-context-sizes
   ;; Message structures
   #:message
   #:make-message
   #:message-role
   #:message-content
   #:message-thinking
   #:message-tool-call-id
   #:message-name
   #:message-tool-calls
   #:message-token-est
   #:message-timestamp
   #:message-metadata
   #:make-history-message
   #:history-messages
   #:history-message-role
   #:history-message-content
   #:history-message-tokens
   #:history-message-timestamp
   #:tool-call
   #:make-tool-call
   #:tool-call-id
   #:tool-call-name
   #:tool-call-arguments

   ;; History structures
   #:history-manager
   #:make-history-manager
   #:history-manager-messages
   #:history-manager-max-tokens
   #:history-manager-model
   #:history-manager-context-percentage
   #:history-manager-token-estimator
   #:history-manager-injectors
   #:history-manager-summarizer
   #:history-manager-rewriters
   #:context-injector
   #:make-context-injector
   #:context-injector-name
   #:context-injector-priority
   #:context-injector-fn
   #:summarizer
   #:make-summarizer
   #:summarizer-name
   #:summarizer-trigger-threshold
   #:summarizer-target-ratio
   #:summarizer-fn
   #:rewriter
   #:make-rewriter
   #:rewriter-name
   #:rewriter-fn

   ;; History globals and functions
   #:*history*
   #:*system-prompt*
   #:*chars-per-token*
   #:*max-context-tokens*
   #:*context-percentage*
   #:*manual-max-tokens*
   #:truncate-string
   #:estimate-tokens
   #:message-tokens
   #:history-tokens
   #:add-message
   #:clear-history
   #:show-history
   #:prune-old
   #:prune-to-max-tokens
   #:show-stats
   #:create-history-manager
   #:create-context-injector
   #:create-summarizer
   #:create-rewriter
   #:history-token-count
   #:inject-context
   #:add-injector
   #:summarize-history
   #:rewrite-history
   #:add-rewriter
   #:make-history-aware-config))

(in-package #:harness.stage-0.protocol)

;;; --- Provider Configuration ------------------------------------------------

(defstruct provider-config
  (name "" :type string :read-only t)
  (api-key nil :type (or string null))
  (base-url "" :type string)
  (default-model "" :type string)
  (default-temperature 0.3 :type float)
  (default-max-tokens 8192 :type integer)
  (timeout 120 :type integer)
  (extra-headers nil :type list)
  (context-sizes (make-hash-table :test 'equal) :type hash-table))

(defun make-provider-config* (&key name api-key base-url default-model
                             (temperature 0.3) (max-tokens 8192) (timeout 120)
                             extra-headers context-sizes)
  "Convenience constructor with simplified keyword names."
  (make-provider-config
   :name name
   :api-key api-key
   :base-url base-url
   :default-model default-model
   :default-temperature (float temperature)
   :default-max-tokens max-tokens
   :timeout timeout
   :extra-headers extra-headers
   :context-sizes (or context-sizes (make-hash-table :test 'equal))))

;;; --- Provider Base Class ---------------------------------------------------

(defclass provider ()
  ((config :initarg :config :reader provider-config :type provider-config)
   (name :initarg :name :reader provider-name :type string
         :documentation "Human-readable provider name"))
  (:documentation "Base provider class. Implement provider-stream for streaming."))

;;; --- Provider Protocol -----------------------------------------------------

(defgeneric provider-call (provider messages &key
                                        model
                                        temperature
                                        max-tokens
                                        tools
                                        tool-choice)
  (:documentation "Non-streaming request. Returns (values response-plist raw-json)."))

(defgeneric provider-stream (provider messages &key
                                            model
                                            temperature
                                            max-tokens
                                            tools
                                            tool-choice
                                            callback)
  (:documentation "Streaming request. CALLBACK receives chunk plists."))

(defgeneric provider-list-models (provider)
  (:documentation "Return list of available models. Each model is a plist with :id, :name, :context-size."))

(defgeneric provider-model-context-size (provider model)
  (:documentation "Return context window size for MODEL (integer tokens)."))

(defgeneric provider-refresh-models (provider)
  (:documentation "Refresh and return updated model list from provider API."))

(defmethod provider-refresh-models ((provider provider))
  (provider-list-models provider))

;;; --- Provider Errors -------------------------------------------------------

(define-condition provider-error (error)
  ((message :initarg :message :reader provider-error-message))
  (:report (lambda (c s) (format s "Provider error: ~A" (provider-error-message c)))))

(define-condition provider-auth-error (provider-error) ()
  (:report (lambda (c s) (format s "Authentication failed: ~A" (provider-error-message c)))))

(define-condition provider-rate-limit-error (provider-error)
  ((retry-after :initarg :retry-after :initform nil :reader rate-limit-retry-after))
  (:report (lambda (c s) (format s "Rate limited: ~A" (provider-error-message c)))))

(define-condition provider-timeout-error (provider-error) ()
  (:report (lambda (c s) (format s "Request timeout: ~A" (provider-error-message c)))))

(define-condition provider-connection-error (provider-error) ()
  (:report (lambda (c s) (format s "Connection error: ~A" (provider-error-message c)))))

;;; --- Message Structures (needed by providers) ------------------------------

(defstruct message
  role        ; :system | :user | :assistant | :tool
  content     ; string
  (thinking nil) ; reasoning/thinking string
  (tool-call-id nil)  ; for tool messages
  (name nil)          ; tool name for tool messages
  (tool-calls nil)    ; list of tool-call structs for assistant
  (token-est 0)       ; estimated tokens
  (timestamp nil)
  (metadata nil))

;; Global variables for history management
(defvar *history* '()
  "Global conversation history list.")

(defvar *system-prompt* nil
  "Global system prompt message.")

(defvar *chars-per-token* 4
  "Estimated characters per token.")

(defvar *max-context-tokens* 6000
  "Maximum tokens allowed in global history.")

(defvar *context-percentage* 0.7
  "Fraction of context window for history.")

(defvar *manual-max-tokens* nil
  "Manual token limit override.")

(defun truncate-string (str max-len)
  "Truncate string to MAX-LEN characters, appending '...' if truncated."
  (if (and str (> (length str) max-len))
      (concatenate 'string (subseq str 0 max-len) "...")
      (or str "")))

;; Token estimation functions (needed by history-manager)
(defun estimate-tokens (text)
  "Rough token estimate from string. Good enough for window management."
  (max 1 (ceiling (length text) *chars-per-token*)))

(defun message-tokens (msg)
  "Estimate tokens for a message, including role/structure overhead."
  (+ (estimate-tokens (or (message-content msg) ""))
     4))  ; role + structural overhead

;; Compatibility helpers for history/message
(defun make-history-message (&rest args)
  (apply #'make-message args))

(defun history-message-role (m) (message-role m))
(defun history-message-content (m) (message-content m))
(defun history-message-tokens (m) (message-tokens m))
(defun history-message-timestamp (m) (message-timestamp m))

(defun history-tokens (history)
  "Total estimated tokens in history."
  (reduce #'+ history :key #'message-tokens :initial-value 0))

;; Supporting structs for history-manager
(defstruct context-injector
  (name "" :type string)
  (priority 0 :type integer)
  (fn nil :type (or null function)))

(defstruct summarizer
  (name "" :type string)
  (trigger-threshold 0.8 :type float)
  (target-ratio 0.5 :type float)
  (fn nil :type (or null function)))

(defstruct rewriter
  (name "" :type string)
  (fn nil :type (or null function)))

;; Now define history-manager which references the above
(defstruct history-manager
  (messages '() :type list)
  (max-tokens 6000 :type integer)
  (model "openai/gpt-oss-20b" :type string)
  (context-percentage 0.7 :type float)
  (token-estimator #'message-tokens :type function)
  (injectors '() :type list)
  (summarizer nil :type (or null summarizer))
  (rewriters '() :type list))

(defun history-messages (hm)
  (history-manager-messages hm))

;;; --- History Globals and Functions --------------------------------------

(defun add-message (arg1 &optional arg2)
  (let ((mgr (if arg2 arg1 nil))
        (msg (if arg2 arg2 arg1)))
    (setf (message-timestamp msg) (get-universal-time))
    (setf (message-token-est msg) (message-tokens msg))
    (if mgr
        (progn
          (setf (history-manager-messages mgr) (append (history-manager-messages mgr) (list msg)))
          (when (> (history-tokens (history-manager-messages mgr)) (history-manager-max-tokens mgr))
            (loop while (> (history-tokens (history-manager-messages mgr)) (history-manager-max-tokens mgr))
                  do (pop (history-manager-messages mgr)))))
        (setf *history* (append *history* (list msg))))
    msg))

(defun clear-history (&optional mgr)
  (if mgr
      (setf (history-manager-messages mgr) '())
      (setf *history* '()))
  (format t "~&History cleared.~%"))

(defun show-history (&optional (n 20))
  "Print last N messages with token estimates."
  (let ((history (if (typep n 'history-manager)
                     (history-manager-messages n)
                     *history*))
        (count (if (integerp n) n 20)))
    (format t "~&=== Last ~A messages (total: ~A tokens) ===~%"
            (min count (length history))
            (history-tokens history))
    (let ((start (max 0 (- (length history) count))))
      (loop for msg in (nthcdr start history)
            for i from start
            do (format t "~&[~A] ~A (~A tok): ~A~%"
                       i
                       (message-role msg)
                       (message-token-est msg)
                       (truncate-string (or (message-content msg) "") 80))))))

(defun prune-old (keep-n)
  "Drop oldest messages, keeping last KEEP-N."
  (when (> (length *history*) keep-n)
    (setf *history* (last *history* keep-n))
    (format t "~&Pruned to last ~A messages (~A tokens).~%"
            keep-n (history-tokens *history*))))

(defun prune-to-max-tokens (&optional limit)
  "Remove oldest messages from history until estimated tokens <= LIMIT.
   If limit is a history-manager, prunes that manager's messages."
  (if (typep limit 'history-manager)
      (let ((mgr limit)
            (removed 0))
        (loop while (> (history-tokens (history-manager-messages mgr)) (history-manager-max-tokens mgr))
              do (pop (history-manager-messages mgr))
                 (incf removed))
        removed)
      (let ((max-tok (or limit *max-context-tokens*))
            (removed 0))
        (loop while (> (history-tokens *history*) max-tok)
              do (pop *history*)
                 (incf removed))
        (when (> removed 0)
          (format t "~&[Context] Pruned ~A oldest messages (~A tokens).~%"
                  removed (history-tokens *history*)))
        removed)))

(defun show-stats (&optional mgr)
  "Show current context usage statistics."
  (let* ((history (if (typep mgr 'history-manager) (history-manager-messages mgr) *history*))
         (total (history-tokens history))
         (n (length history))
         (by-role (make-hash-table)))
    (loop for m in history
          do (incf (gethash (message-role m) by-role 0)
                   (message-tokens m)))
    (format t "~&=== Context Stats ===~%")
    (format t "Messages: ~A~%" n)
    (format t "Total tokens (est): ~A~%" total)
    (format t "Breakdown:~%")
    (maphash (lambda (k v) (format t "  ~A: ~A~%" k v)) by-role)
    (when *system-prompt*
      (format t "  system-prompt: ~A~%"
              (message-tokens *system-prompt*)))))

(format t "~&[harness.stage-0.protocol] Loaded~%")