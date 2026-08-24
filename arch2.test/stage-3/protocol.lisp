;;;; harness/stage-3/protocol.lisp - History management (Stage 3)

(defpackage #:harness.stage-3.protocol
  (:use #:cl #:harness.stage-0.protocol #:harness.stage-1.protocol #:harness.tools.protocol)
  (:export
   #:history-max-tokens
   #:history-model
   #:history-context-percentage
   #:history-token-estimator
   #:history-injectors
   #:history-summarizer
   #:history-rewriters
   #:get-history
   #:wrap-eval-loop-with-history
   #:history-aware-eval-loop
   #:truncate-string
   #:create-history-manager
   #:create-context-injector
   #:create-summarizer
   #:create-rewriter
   #:make-history-aware-config
   #:history-token-count
   #:inject-context
   #:add-injector
   #:summarize-history
   #:rewrite-history
   #:add-rewriter))

(in-package #:harness.stage-3.protocol)

;;; --- History Manager Class ---

;; history-manager struct is defined in stage-0/protocol.lisp

(defun history-max-tokens (hm) (history-manager-max-tokens hm))
(defun (setf history-max-tokens) (val hm) (setf (history-manager-max-tokens hm) val))

(defun history-model (hm) (history-manager-model hm))
(defun (setf history-model) (val hm) (setf (history-manager-model hm) val))

(defun history-context-percentage (hm) (history-manager-context-percentage hm))
(defun (setf history-context-percentage) (val hm) (setf (history-manager-context-percentage hm) val))

(defun create-history-manager (&key (max-tokens 6000) (model "openai/gpt-oss-20b")
                               (context-percentage 0.7) token-estimator)
  (make-history-manager
   :max-tokens max-tokens
   :model model
   :context-percentage context-percentage
   :token-estimator (or token-estimator #'message-tokens)))


(defun history-token-count (manager)
  "Total estimated tokens in history."
  (reduce #'+ (history-manager-messages manager) :key #'message-tokens :initial-value 0))

;; Context injection
;; context-injector struct is defined in stage-0/protocol.lisp

(defun create-context-injector (name fn &key (priority 0))
  (make-context-injector :name name :fn fn :priority priority))

(defgeneric inject-context (manager input)
  (:documentation "Run all injectors, return list of injected messages."))

(defmethod inject-context ((manager history-manager) input)
  (loop for inj in (sort (history-manager-injectors manager) #'> :key #'context-injector-priority)
        append (funcall (context-injector-fn inj) manager input)))

(defmethod add-injector ((manager history-manager) (injector context-injector))
  (push injector (history-manager-injectors manager))
  injector)

;; Summarization
;; summarizer struct is defined in stage-0/protocol.lisp

(defun create-summarizer (name fn &key (trigger-threshold 0.8) (target-ratio 0.5))
  (make-summarizer :name name :fn fn
                 :trigger-threshold trigger-threshold
                 :target-ratio target-ratio))

(defgeneric summarize-history (manager)
  (:documentation "Run summarizer if triggered. Returns T if summarized."))

(defmethod summarize-history ((manager history-manager))
  (let ((summarizer (history-manager-summarizer manager)))
    (when (and summarizer
               (> (history-token-count manager)
                  (* (summarizer-trigger-threshold summarizer) (history-manager-max-tokens manager))))
      (let* ((messages (history-manager-messages manager))
             (target (floor (* (summarizer-target-ratio summarizer) (history-manager-max-tokens manager))))
             (to-summarize (loop for m in messages
                                 while (> (reduce #'+ messages :key #'message-tokens :initial-value 0) target)
                                 collect m))
             (remaining (nthcdr (length to-summarize) messages))
             (summary (funcall (summarizer-fn summarizer) manager to-summarize)))
        (setf (history-manager-messages manager)
              (append (list (make-message :role :system
                                          :content (format nil "[Summary of previous conversation]: ~A" summary)))
                      remaining))
        (format t "~&[History] Summarized ~A messages (~A tokens saved)~%"
                (length to-summarize)
                (- (reduce #'+ to-summarize :key #'message-tokens :initial-value 0)
                   (message-tokens (make-message :role :system :content summary))))
        t))))

;; History Rewriting
;; rewriter struct is defined in stage-0/protocol.lisp

(defun create-rewriter (name fn)
  (make-rewriter :name name :fn fn))

(defgeneric rewrite-history (manager)
  (:documentation "Apply all rewriters to history."))

(defmethod rewrite-history ((manager history-manager))
  (let ((messages (history-manager-messages manager)))
    (dolist (rwr (history-manager-rewriters manager))
      (setf messages (funcall (rewriter-fn rwr) manager messages)))
    (setf (history-manager-messages manager) messages)
    (values)))

(defmethod add-rewriter ((manager history-manager) (rewriter rewriter))
  (push rewriter (history-manager-rewriters manager))
  rewriter)

(defun get-history (hm)
  (history-manager-messages hm))

;; Eval Loop Integration
(defstruct (history-aware-eval-loop-config (:include eval-loop-config))
  (history-manager nil :type (or null history-manager)))

(defun make-history-aware-config (base-config manager)
  "Wrap a base eval-loop-config with history management."
  (make-history-aware-eval-loop-config
   :provider (eval-loop-config-provider base-config)
   :tool-registry (eval-loop-config-tool-registry base-config)
   :max-iterations (eval-loop-config-max-iterations base-config)
   :system-prompt (eval-loop-config-system-prompt base-config)
   :on-iteration (eval-loop-config-on-iteration base-config)
   :on-tool-call (eval-loop-config-on-tool-call base-config)
   :on-response (eval-loop-config-on-response base-config)
   :history-manager manager))

(defun wrap-eval-loop-with-history (base-config history-manager)
  (make-history-aware-config base-config history-manager))

(defmethod eval-loop ((input string) (config history-aware-eval-loop-config))
  (let ((hm (history-aware-eval-loop-config-history-manager config)))
    (if hm
        (progn
          (summarize-history hm)
          (rewrite-history hm)
          (add-message hm (make-message :role :user :content input))
          (let* ((injected (inject-context hm input))
                 (sys-prompt (eval-loop-config-system-prompt config))
                 (messages (append (when sys-prompt (list (make-message :role :system :content sys-prompt)))
                                   injected
                                   (history-manager-messages hm)))
                 (max-iter (eval-loop-config-max-iterations config)))
            (loop for iter from 1 to max-iter do
              (multiple-value-bind (new-msgs result)
                  (eval-loop-step messages config iter)
                (setf messages new-msgs)
                (when result
                  (setf (result-iterations result) iter)
                  (let ((last-msg (car (last new-msgs))))
                    (when (and last-msg (eq (message-role last-msg) :assistant))
                      (add-message hm last-msg)))
                  (return-from eval-loop result))))
            (make-eval-result :error (format nil "Max iterations (~A) exceeded" max-iter)
                              :iterations max-iter)))
        (call-next-method))))

(defun history-aware-eval-loop (input config history-manager)
  (let ((hw-config (make-history-aware-config config history-manager)))
    (eval-loop input hw-config)))

(format t "~&[harness.stage-3.protocol] Loaded~%")