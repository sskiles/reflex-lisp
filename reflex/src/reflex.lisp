;;; Main file for the reflex system

(in-package #:reflex)

(defvar *session-history* nil
  "Live conversation history for the current query loop.
Unlike *DEFAULT-HISTORY*, this variable's value is mutated by QUERY-LOOP and
is preserved across save/restore so resuming from a saved core continues the
same conversation.")

(defun agent-send (line &key history)
  "Send LINE to the LLM via SEND-PROMPT and print the reply.
HISTORY is a list of prior message alists; when non-nil it is forwarded to
SEND-PROMPT so the model sees prior turns."
  (handler-case
      (let ((reply (send-prompt line :history history)))
        (format t "~%~A~%" reply)
        reply)
    (error (e)
      (format t "~%ERROR: ~A~%" e)
      nil)))

(defun %eval-lisp-line (line)
  "Read and eval LINE as a single Lisp form, printing the result."
  (format t "~%---------~%")
  (let ((expr (read-from-string line)))
    (format t "~S~%" (eval expr)))
  (format t "---------~%"))

(defun %llm-line (line)
  "Send LINE to the LLM using *SESSION-HISTORY*, append the turn, return reply."
  (let ((reply (agent-send line :history *session-history*)))
    (when reply
      (setf *session-history* (append-turn *session-history* line reply)))
    reply))

(defun query-loop ()
  "Interactive read-line loop.
Lines starting with '(' are evaluated as Lisp; everything else is sent to the
LLM via AGENT-SEND.  An empty line exits the loop.

History lives in the package-level variable *SESSION-HISTORY* so it survives
SAVE-IMAGE / restore.  Call (setf reflex:*session-history* nil) to reset."
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
  "Print startup information and enter the query loop."
  (format t "~2&Reflex ready.~%")
  (format t "Endpoint:   ~A~%" *default-endpoint*)
  (format t "Model:      ~A~%" *default-model*)
  (format t "API key:    ~A~%" (if *default-api-key* "SET" "NOT SET"))
  (format t "History:    ~A message(s)~%" (length *session-history*))
  (format t "~%Try: (setf reflex:*session-history* nil)~%")
  (format t "Or:  (reflex:ask \"Say hello.\")~2&")
  (query-loop))
