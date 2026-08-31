;;; Main file for the reflex system

(in-package #:reflex)

(defvar *session-history* nil
  "Live conversation history for the current query loop.
Unlike *DEFAULT-HISTORY*, this variable's value is mutated by QUERY-LOOP and
is preserved across save/restore so resuming from a saved core continues the
same conversation.")

(defvar *max-tool-iterations* 10
  "Maximum number of tool-call rounds per user turn.  Protects against
infinite loops when the LLM keeps calling tools indefinitely.")

(defun %make-tool-call-message (tool-calls)
  "Build an assistant message alist that contains every TOOL-CALL in a single
tool_calls array, as required by OpenAI."
  (let ((tc-alists
          (mapcar (lambda (tc)
                    (let* ((id       (cdr (assoc :id tc)))
                           (name     (cdr (assoc :name tc)))
                           (args     (cdr (assoc :arguments tc)))
                           (args-str (cond ((null args) "{}")
                                           ((stringp args) args)
                                           (t (handler-case
                                                   (json:encode-json-alist-to-string args)
                                                 (error () "{}"))))))
                      (list (cons "id" id)
                            (cons "type" "function")
                            (cons "function"
                                  (list (cons "name" name)
                                        (cons "arguments" args-str))))))
                  tool-calls)))
    (list (cons "role" "assistant")
          (cons "content" "")
          (cons "tool_calls" tc-alists))))

(defun %make-tool-result-message (tool-call-id tool-name content)
  (list (cons "role"         "tool")
        (cons "tool_call_id" tool-call-id)
        (cons "name"         tool-name)
        (cons "content"      content)))

(defun %run-tools (tool-calls)
  (mapcar (lambda (tc)
            (let* ((id      (cdr (assoc :id tc)))
                   (name    (cdr (assoc :name tc)))
                   (args    (cdr (assoc :arguments tc)))
                   (result  (handler-case
                                (reflex.tools:execute-tool-call name args)
                              (error (e)
                                (format nil "ERROR: ~A" e)))))
              (list (cons :id      id)
                    (cons :name    name)
                    (cons :content result))))
          tool-calls))

(defun %format-tool-call (tc)
  (format t "  ~A(~S)~%"
          (or (cdr (assoc :name tc)) "?")
          (cdr (assoc :arguments tc))))

(defun %format-tool-result (tr)
  (let* ((name    (cdr (assoc :name tr)))
         (content (cdr (assoc :content tr)))
         (preview (if (> (length content) 200)
                      (format nil "~A..." (subseq content 0 200))
                      content)))
    (format t "    ~A => ~A~%" name preview)))

(defun %single-round (prompt history)
  "Make a single LLM call. Returns (values content tool-calls)."
  (send-prompt prompt :history history))

(defun %dispatch-tools (tool-calls history)
  "Append assistant + tool messages to HISTORY and return the new history."
  (let* ((assistant-msg (%make-tool-call-message tool-calls))
         (results (%run-tools tool-calls)))
    (format t "~%[tool calls]~%")
    (dolist (tc tool-calls) (%format-tool-call tc))
    (dolist (r results) (%format-tool-result r))
    (let ((with-assistant (append history (list assistant-msg))))
      (reduce (lambda (acc result)
                (append acc
                        (list (%make-tool-result-message
                              (cdr (assoc :id result))
                              (cdr (assoc :name result))
                              (cdr (assoc :content result))))))
              results
              :initial-value with-assistant))))

(defun agent-send (line &key history (max-iterations *max-tool-iterations*))
  "Send LINE to the LLM and dispatch any tool calls.
HISTORY is a list of prior message alists; when non-nil it is forwarded to
SEND-PROMPT. Returns the final assistant content string and updates
*SESSION-HISTORY*."
  (let ((history (or history *session-history*))
        (prompt line)
        (final-content ""))
    (loop repeat max-iterations do
          (handler-case
              (multiple-value-bind (content tool-calls)
                  (%single-round prompt history)
                (cond
                  ((null tool-calls)
                   (setf final-content content)
                   (return-from agent-send final-content))
                  (t
                   (setf history (%dispatch-tools tool-calls history))
                   (setf prompt ""))))
            (error (e)
              (format t "~%ERROR: ~A~%" e)
              (return-from agent-send nil))))
    (format t "~%WARN: max tool iterations (~A) reached~%" max-iterations)
    (setf *session-history* history)
    final-content))

(defun %eval-lisp-line (line)
  (format t "~%---------~%")
  (let ((expr (read-from-string line)))
    (format t "~S~%" (eval expr)))
  (format t "---------~%"))

(defun %llm-line (line)
  (let ((reply (agent-send line :history *session-history*)))
    (when reply
      (setf *session-history*
            (append *session-history*
                    (list (make-message "user" line)
                          (make-message "assistant" reply)))))
    reply))

(defun query-loop ()
  (format t "~%--- Query Loop (empty line to exit) ---~%")
  (format t " Lisp expressions (start with '(') are evaluated~%")
  (format t " Anything else is sent to the LLM~%~%")
  (loop for line = (progn (format t "~&Operator> ") (finish-output) (read-line *standard-input* nil nil))
        while (and line (string/= line ""))
        do (handler-case
               (if (and (> (length line) 0) (char= (char line 0) #\())
                   (%eval-lisp-line line)
                   (%llm-line line))
             (error (e)
               (format t "~%---------~%")
               (format t "WARN: ~A~%" e)
               (format t "---------~%")))))

(defun start ()
  (format t "~2&Reflex ready.~%")
  (format t "Endpoint:   ~A~%" *default-endpoint*)
  (format t "Model:      ~A~%" *default-model*)
  (format t "API key:    ~A~%" (if *default-api-key* "SET" "NOT SET"))
  (format t "History:    ~A message(s)~%" (length *session-history*))
  (format t "Tools:      ~A registered~%" (length (reflex.tools:list-tools)))
  (format t "~%Try: (setf reflex:*session-history* nil)~%")
  (format t "Or:  (reflex:ask \"Say hello.\")~2&")
  (query-loop))
