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

(defvar *last-finish-reason* nil
  "Finish reason from the most recent LLM call.  Set by AGENT-SEND when
the response is empty so %LLM-LINE can explain why.  Common values:
:STOP (normal end), :LENGTH (truncated by max_tokens), :CONTENT_FILTER
(blocked by safety), :TOOL_CALLS (model chose to call a tool).")

(defvar *last-raw-body* nil
  "Raw response body from the most recent LLM call.  Useful for debugging
empty or malformed responses.  Set by AGENT-SEND.")

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
  "Make a single LLM call. Returns (values content tool-calls meta)."
  (send-prompt prompt :history history :return-meta t :max-tokens 1024))

(defun %dispatch-tools (tool-calls history)
  "Append assistant + tool messages to HISTORY and return the new history."
  (let* ((assistant-msg (%make-tool-call-message tool-calls))
         (results (%run-tools tool-calls)))
    (format t "~%[tool calls]~%")
    (dolist (tc tool-calls) (%format-tool-call tc))
    (dolist (r results) (%format-tool-result r))
    ;; Persist the assistant turn (tool-call request)
    (handler-case
        (reflex.context::%persist-turn "assistant" "assistant" "" )
      (error () nil))
    ;; Persist each tool result
    (dolist (r results)
      (handler-case
          (reflex.context::%persist-turn "tool" "tool"
                                        (cdr (assoc :content r))
                                        :tool-name (cdr (assoc :name r))
                                        :tool-call-id (cdr (assoc :id r)))
        (error () nil)))
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
SEND-PROMPT. Returns (values final-content updated-history)."
  (let ((history (or history *session-history*))
        (final-content ""))
    ;; Add user message to history so it's visible to the model on all rounds
    (setf history (append history (list (make-message "user" line))))
    ;; Persist the user turn
    (handler-case
        (reflex.context::%persist-turn "user" "user" line)
      (error () nil))
    (loop repeat max-iterations do
          (handler-case
              (let* ((context-prompt
                       (reflex.context:context-assemble-prompt
                        line
                        :session-id *current-session-id*
                        :report-stream *standard-output*)))
                (multiple-value-bind (content tool-calls meta)
                    (send-prompt ""
                                 :history history
                                 :system-prompt context-prompt
                                 :return-meta t
                                 :max-tokens 1024)
                  (cond
                    ((null tool-calls)
                     (setf final-content content)
                     ;; If empty, leave a diagnostic on *last-finish-reason*
                     ;; so %llm-line can explain why.
                     (when (and (string= content "")
                                meta (getf meta :finish-reason))
                       (setf *last-finish-reason* (getf meta :finish-reason)))
                     ;; Persist the final assistant reply
                     (handler-case
                         (reflex.context::%persist-turn "assistant" "assistant"
                                                       content)
                       (error () nil))
                     (return-from agent-send (values final-content history)))
                    (t
                     (setf history (%dispatch-tools tool-calls history))))))
            (error (e)
              (format t "~%ERROR: ~A~%" e)
              (return-from agent-send (values nil history)))))
    (format t "~%WARN: max tool iterations (~A) reached~%" max-iterations)
    (values final-content history)))

(defun %eval-lisp-line (line)
  (format t "~%---------~%")
  (let ((expr (read-from-string line)))
    (format t "~S~%" (eval expr)))
  (format t "---------~%"))

(defun %llm-line (line)
  (setf *last-finish-reason* nil)
  (multiple-value-bind (reply new-history)
      (agent-send line :history *session-history*)
    (setf *session-history* new-history)
    (cond
      ((null reply)
       (format t "~%[no response from LLM]~%"))
      ((string= reply "")
       (let ((reason *last-finish-reason*))
         (format t "~%[empty response~@[ (finish_reason=~A)~]]~%"
                 reason)))
      (t
       ;; Streaming mode already prints tokens as they arrive; only print
       ;; here when we received the full reply at once.
       (unless *use-streaming*
         (format t "~%~A~%" reply))))
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

(defun menu ()
  "Print a cheat sheet of the commands available to the user."
  (format t "~2&==== Reflex cheat sheet ====~%")
  (format t "~%-- Core entry points --~%")
  (format t "  (reflex:start)              Start the interactive query loop~%")
  (format t "  (reflex:ask \"...\")        One-shot prompt; returns the assistant reply~%")
  (format t "  (reflex:query-loop)         Same as START but without the startup banner~%")
  (format t "  (reflex:agent-send line)    Send LINE through the tool-calling agent~%")
  (format t "  (reflex:send-prompt ...)    Raw HTTP call to the chat-completions API~%")
  (format t "~%-- Streaming --~%")
  (format t "  (setf reflex:*use-streaming* t)    Stream the next response~%")
  (format t "  (setf reflex:*use-streaming* nil)  Return the full reply at once (default)~%")
  (format t "  (reflex:send-prompt ... :stream-p t)   Per-call streaming override~%")
  (format t "~%-- History & state --~%")
  (format t "  reflex:*session-history*      Live conversation (mutated by AGENT-SEND)~%")
  (format t "  reflex:*default-history*      Initial history handed to SEND-PROMPT~%")
  (format t "  (setf reflex:*session-history* nil)    Clear the conversation~%")
  (format t "  (reflex:make-message \"user\" \"hi\")     Build a single message alist~%")
  (format t "  (reflex:append-turn hist u a)          Append a user/assistant turn~%")
  (format t "~%-- Tools --~%")
  (format t "  (reflex.tools:list-tools)               List every registered tool~%")
  (format t "  (reflex.tools:execute-tool-call name args)~%")
  (format t "  eval-lisp / read-file / write-file / edit-file / bash / sqlite-sql~%")
  (format t "~%-- Image save / restore --~%")
  (format t "  (reflex:save-image \"reflex.core\")        Save state to a plain .core~%")
  (format t "  (reflex:save-image \"reflex\" :executable t)   Save a standalone binary~%")
  (format t "  sbcl --core reflex.core                 Restart the saved image~%")
  (format t "~%-- Endpoint configuration --~%")
  (format t "  reflex:*default-endpoint*     URL of the chat-completions API~%")
  (format t "  reflex:*default-model*        Model name sent in each request~%")
  (format t "  reflex:*default-api-key*      Reads NVIDIA_API_KEY at load time~%")
  (format t "  reflex:*default-system-prompt* Default system prompt~%")
  (format t "~%-- Misc --~%")
  (format t "  reflex:*max-tool-iterations*  Safety cap on tool-call loops (default 10)~%")
  (format t "  (reflex:menu)                  Show this cheat sheet again~%")
  (format t "~%-- Examples --~%")
  (format t "  (reflex:ask \"Summarise the README\")~%")
  (format t "  (setf reflex:*use-streaming* t)~%")
  (format t "  (reflex:ask \"Tell me a long story\")~%")
  (format t "  (setf reflex:*use-streaming* nil)~%")
  (format t "  (reflex:agent-send \"List every *.lisp file under src/\")~%")
  (format t "  (reflex:save-image \"reflex.core\")~%")
  (format t "~&================================~2&"))

