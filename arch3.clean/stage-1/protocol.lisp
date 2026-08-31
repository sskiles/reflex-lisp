;;;; harness/stage-1/protocol.lisp - Eval loop protocol (Stage 1)

(defpackage #:harness.stage-1.protocol
  (:use #:cl #:harness.tools.protocol #:harness.stage-0.protocol #:harness.stage-1.conditions)
  (:export
   #:eval-loop
   #:eval-loop-step
   #:eval-loop-config
   #:make-eval-loop-config
   #:make-eval-loop-config*
   #:eval-loop-config-provider
   #:eval-loop-config-tool-registry
   #:eval-loop-config-max-iterations
   #:eval-loop-config-system-prompt
   #:eval-loop-config-on-iteration
   #:eval-loop-config-on-tool-call
   #:eval-loop-config-on-response
   #:config-provider
   #:config-tool-registry
   #:config-max-iterations
   #:config-system-prompt
   #:config-on-iteration
   #:config-on-tool-call
   #:config-on-response
   #:get-lisp-eval-tool-spec
   #:make-lisp-eval-tool-fn
   #:eval-result
   #:make-eval-result
   #:result-content
   #:result-thinking
   #:result-tool-calls
   #:result-usage
   #:result-iterations
   #:result-error
   #:eval-result-content
   #:eval-result-thinking
   #:eval-result-tool-calls
   #:eval-result-usage
   #:eval-result-iterations
   #:eval-result-error
   #:eval-loop-error
   #:eval-loop-error-message
   #:max-iterations-exceeded
   #:max-iterations-count))

(defpackage #:harness.stage-1.eval-loop
  (:use #:cl
        #:harness.tools.protocol
        #:harness.tools.registry
        #:harness.stage-0.protocol
        #:harness.stage-0.nvidia
        #:harness.stage-1.protocol
        #:harness.stage-1.conditions)
  (:export #:eval-loop
           #:eval-loop-step
           #:agent-send
           #:start
           #:query-loop
           #:tool-query))


(in-package #:harness.stage-1.protocol)

;;; --- Eval Loop Config ------------------------------------------------------

(defstruct (eval-loop-config
             (:constructor make-eval-loop-config*))
  (provider nil)
  (tool-registry nil)
  (max-iterations 10 :type integer)
  (system-prompt nil :type (or null string))
  (on-iteration nil :type (or null function))
  (on-tool-call nil :type (or null function))
  (on-response nil :type (or null function)))

(defun make-eval-loop-config (&rest args)
  (apply #'make-eval-loop-config* args))

;; Accessors for config (for backward compatibility)
(defun config-provider (config) (eval-loop-config-provider config))
(defun config-tool-registry (config) (eval-loop-config-tool-registry config))
(defun config-max-iterations (config) (eval-loop-config-max-iterations config))
(defun config-system-prompt (config) (eval-loop-config-system-prompt config))
(defun config-on-iteration (config) (eval-loop-config-on-iteration config))
(defun config-on-tool-call (config) (eval-loop-config-on-tool-call config))
(defun config-on-response (config) (eval-loop-config-on-response config))

;;; --- Eval Result -----------------------------------------------------------

(defstruct (eval-result (:conc-name result-))
  (content nil :type (or null string))
  (thinking nil :type (or null string))
  (tool-calls nil :type list)
  (usage nil)
  (iterations 0 :type integer)
  (error nil :type (or null string)))

(defun eval-result-content (r) (result-content r))
(defun eval-result-thinking (r) (result-thinking r))
(defun eval-result-tool-calls (r) (result-tool-calls r))
(defun eval-result-usage (r) (result-usage r))
(defun eval-result-iterations (r) (result-iterations r))
(defun eval-result-error (r) (result-error r))

;;; --- Conditions ------------------------------------------------------------

;; Conditions defined in stage-1/conditions.lisp

;;; --- Protocol Generics -----------------------------------------------------

(defgeneric eval-loop (input config)
  (:documentation "Top-level eval loop. INPUT is a string (user message).
Returns eval-result. Runs until final response or max iterations."))

(defgeneric eval-loop-step (messages config &optional iteration)
  (:documentation "Single iteration: messages -> provider -> tool execution -> updated messages.
Returns (values new-messages result-or-nil)."))

;;; --- Built-in Lisp Eval Tool -----------------------------------------------

(defun get-lisp-eval-tool-spec ()
  (make-tool-spec
   "eval-lisp"
   "Evaluate a Lisp expression in the running image. Use for computation, inspection, and harness modification."
   (plist-to-hash '("type" "object"
                    "properties" ("expression" ("type" "string"))
                    "required" ("expression")
                    "additionalProperties" nil))
   (lambda (args)
     (let ((expr-str (cond
                       ((typep args 'hash-table)
                        (or (gethash "expression" args)
                            (gethash "code" args)
                            (gethash "lisp" args)
                            (gethash "body" args)))
                       ((listp args)
                        (cdr (or (assoc "expression" args :test #'string=)
                                 (assoc "code" args :test #'string=)
                                 (assoc "lisp" args :test #'string=)
                                 (assoc "body" args :test #'string=)))))))
       (if (not (stringp expr-str))
           (values nil "Error: Missing string argument 'expression'")
           (handler-case
               (let* ((expr (read-from-string expr-str))
                      (result (eval expr)))
                 (values (format nil "~S" result) nil))
             (error (e)
               (values nil (format nil "Eval error: ~A" e)))))))
   nil))

(defun make-lisp-eval-tool-fn ()
  (get-lisp-eval-tool-spec))

(format t "~&[harness.stage-1.protocol] Loaded~%")