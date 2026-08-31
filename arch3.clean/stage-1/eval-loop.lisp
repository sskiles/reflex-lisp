;;;; harness/stage-1/eval-loop.lisp — Main agent loop

(in-package #:harness.stage-1.eval-loop)

(defvar *agent-running* nil
  "Whether agent loop is active.")

(defvar *current-config* nil)


;;; Method implementations for Stage 1 protocol

(defmethod eval-loop-step (messages (config eval-loop-config) &optional (iteration 1))
  (declare (ignore iteration))
  (let* ((prov (eval-loop-config-provider config))
         (reg (eval-loop-config-tool-registry config))
         (tools (when reg (tool-schemas-for-llm reg))))
    (multiple-value-bind (response raw)
        (if (and prov (typep prov 'provider))
            (provider-call prov messages :tools tools)
            (call-nvidia-chat messages :tools tools))
      (declare (ignore raw))
      (let* ((raw-content (json-get response "content"))
             (thinking (or (json-get response "reasoning_content")
                           (json-get response "thinking")
                           (json-get response "reasoning")))
             (content raw-content))
        (when (and (not thinking) (stringp raw-content))
          (let ((think-start (search "<think>" raw-content))
                (think-end (search "</think>" raw-content)))
            (when (and think-start think-end (< think-start think-end))
              (setf thinking (string-trim '(#\Space #\Newline #\Tab)
                                          (subseq raw-content (+ think-start 7) think-end)))
              (setf content (string-trim '(#\Space #\Newline #\Tab)
                                         (concatenate 'string
                                                      (subseq raw-content 0 think-start)
                                                      (subseq raw-content (+ think-end 8))))))))
        (let* ((tool-calls (json-get response "tool_calls"))
               (usage (json-get response "usage"))
               (tc-structs (when tool-calls
                             (mapcar (lambda (tc)
                                       (make-tool-call
                                        :id (json-get tc "id")
                                        :name (json-get (json-get tc "function") "name")
                                        :arguments (let ((arg-raw (json-get (json-get tc "function") "arguments")))
                                                     (if (stringp arg-raw)
                                                         (json:decode-json-from-string arg-raw)
                                                         arg-raw))))
                                     tool-calls)))
               (assistant-msg (make-message :role :assistant :content content :thinking thinking :tool-calls tc-structs)))
          (if tool-calls
              (let ((new-msgs (append messages (list assistant-msg))))
                (dolist (tc tc-structs)
                  (let* ((name (tool-call-name tc))
                         (id (tool-call-id tc))
                         (args (tool-call-arguments tc)))
                    (multiple-value-bind (res err)
                        (if reg
                            (execute-tool reg name (if (listp args) (plist-to-hash args) args))
                            (execute-tool-call tc))
                      (let ((tool-msg (make-message :role :tool
                                                    :content (or res err)
                                                    :tool-call-id id
                                                    :name name)))
                        (setf new-msgs (append new-msgs (list tool-msg)))))))
                (values new-msgs nil))
              (values (append messages (list assistant-msg))
                      (make-eval-result :content content
                                        :thinking thinking
                                        :tool-calls nil
                                        :usage usage
                                        :iterations 1))))))))

(defmethod eval-loop ((input string) (config eval-loop-config))
  (let* ((sys-prompt (eval-loop-config-system-prompt config))
         (max-iter (eval-loop-config-max-iterations config))
         (messages (append (when sys-prompt (list (make-message :role :system :content sys-prompt)))
                           (list (make-message :role :user :content input))))
         (accumulated-thinking nil))
    (loop for iter from 1 to max-iter do
      (multiple-value-bind (new-msgs result)
          (eval-loop-step messages config iter)
        (setf messages new-msgs)
        (let ((last-msg (car (last new-msgs))))
          (when (and last-msg (message-thinking last-msg))
            (setf accumulated-thinking
                  (if accumulated-thinking
                      (format nil "~A~%~A" accumulated-thinking (message-thinking last-msg))
                      (message-thinking last-msg)))))
        (when result
          (setf (result-iterations result) iter)
          (when (and accumulated-thinking (not (result-thinking result)))
            (setf (result-thinking result) accumulated-thinking))
          (return-from eval-loop result))))
    (make-eval-result :error (format nil "Max iterations (~A) exceeded" max-iter)
                      :iterations max-iter)))

;;; Build message list for API (system + history)
(defun build-api-messages ()
  (append (when *system-prompt* (list *system-prompt*))
          *history*))

;;; Set system prompt
(defun set-system-prompt (text)
  (setf *system-prompt* (make-message :role :system :content text))
  (format t "~&System prompt set (~A tokens).~%"
          (message-tokens *system-prompt*)))

;;; Quick helpers
(defun reset-history ()
  (clear-history)
  (format t "~&History reset.~%"))

(defun show-tools ()
  (list-tools))

;;; Main entry point: send a message to the agent
(defun agent-send (user-input &key (model *default-model*))
  "Send user input to agent, run loop until final response."
  (format t "~&---------~%")

  ;; Add user message
  (add-message (make-message :role :user :content user-input))

  ;; Build messages for API
  (let ((api-messages (build-api-messages))
        (tools (get-tool-schemas))
        (iterations 0)
        (max-iterations 10)
        (accumulated-thinking nil))
    (block agent-loop
      (loop
        (when (>= iterations max-iterations)
          (format t "~&[WARN] Max iterations (~A) reached, stopping.~%" max-iterations)
          (format t "---------~%")
          (return-from agent-send nil))
        (incf iterations)
        (prune-to-max-tokens)
        (multiple-value-bind (response raw)
            (call-nvidia-chat api-messages :model model :tools tools)
          (declare (ignore raw))
          (let* ((raw-content (json-get response "content"))
                 (thinking (or (json-get response "reasoning_content")
                               (json-get response "thinking")
                               (json-get response "reasoning")))
                 (tool-calls (json-get response "tool_calls"))
                 (usage (json-get response "usage"))
                 (content raw-content))
            (when (and (not thinking) (stringp raw-content))
              (let ((think-start (search "<think>" raw-content))
                    (think-end (search "</think>" raw-content)))
                (when (and think-start think-end (< think-start think-end))
                  (setf thinking (string-trim '(#\Space #\Newline #\Tab)
                                              (subseq raw-content (+ think-start 7) think-end)))
                  (setf content (string-trim '(#\Space #\Newline #\Tab)
                                             (concatenate 'string
                                                          (subseq raw-content 0 think-start)
                                                          (subseq raw-content (+ think-end 8))))))))
            (when thinking
              (setf accumulated-thinking
                    (if accumulated-thinking
                        (format nil "~A~%~A" accumulated-thinking thinking)
                        thinking)))

            ;; Add assistant message to history
            (let ((assistant-msg (make-message
                                   :role :assistant
                                   :content content
                                   :thinking thinking
                                   :tool-calls (when tool-calls
                                                 (mapcar (lambda (tc)
                                                           (make-tool-call
                                                            :id (json-get tc "id")
                                                            :name (json-get (json-get tc "function") "name")
                                                            :arguments (json:decode-json-from-string
                                                                         (json-get (json-get tc "function") "arguments"))))
                                                         tool-calls)))))
              (add-message assistant-msg))

            ;; If tool calls, execute them and loop again
            (if tool-calls
                (progn
                  (format t "~&[TOOL CALLS] ~A (round ~A)~%" (length tool-calls) iterations)
                  (dolist (tc tool-calls)
                    (let* ((fn-obj (json-get tc "function"))
                           (name (json-get fn-obj "name"))
                           (id (json-get tc "id"))
                           (args-str (json-get fn-obj "arguments")))
                      (format t "  ~A(~A)~%" name args-str)
                      (multiple-value-bind (result error)
                          (handler-case
                              (execute-tool-call
                               (make-tool-call :id id :name name
                                               :arguments (json:decode-json-from-string args-str)))
                            (error (e)
                              (values nil (format nil "Parse/exec error: ~A" e))))
                        (if error
                            (format t "    ERROR: ~A~%" error)
                            (format t "    OK (~A chars)~%" (length result)))
                        ;; Add tool result to history
                        (add-message (make-message
                                       :role :tool
                                       :content (or result error)
                                       :tool-call-id id
                                       :name name)))))
                  ;; Update api-messages for next iteration
                  (setf api-messages (build-api-messages)))
                ;; No tool calls = final response
                (progn
                  (format t "Thinking:~%")
                  (format t "~A~%" (or accumulated-thinking "Analyzing prompt and generating response..."))
                  (format t "---------~%")
                  (when content
                    (format t "~A~%" content))
                  (when usage
                    (format t "    [usage: ~A prompt + ~A completion = ~A total]~%"
                            (json-get usage "prompt_tokens")
                            (json-get usage "completion_tokens")
                            (json-get usage "total_tokens")))
                  (format t "---------~%")
                  (return-from agent-send content)))))))))

;;; Start function - loads everything, sets default system prompt
(defun start ()
  "Initialize the harness with default system prompt."
  (set-system-prompt
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

Work in the current directory. Prefer reading files before editing. Be concise. Show your work by executing code, not just describing it.")

  (update-context-limit)
  (format t "~&=== Lisp Harness Ready ===~%")
  (format t "Primary entry points:~%")
  (format t "  (agent-send \"msg\")    - Full agent (tools + thinking)~%")
  (format t "  (query \"expr|msg\")    - Eval if Lisp, else ask LLM~%")
  (format t "  (reset-history)        - Clear conversation~%")
  (format t "  (show-history [n])     - Show last N messages~%")
  (format t "  (show-stats)           - Token usage stats~%")
  (format t "  (show-tools)           - List available tools~%")
  (format t "~%Model: ~A~%" *default-model*)
  (format t "API Key: ~A~%"
          (if *nvidia-api-key* "SET" "NOT SET"))
  (values))

;;; --- Swank server --------------------------------------------------------
(defvar *swank-port* 4005
  "Default Swank server port.")

(defun start-swank-server (&key (port *swank-port*))
  "Start a Swank server for remote REPL access.
   A client can connect with (swank-client:slime-connect \"localhost\" PORT)
   or via the provided `connect-swank.sh` script.
   Returns the swank server object."
  (ql:quickload :swank)
  (format t "~&Starting Swank server on port ~A...~%" port)
  (let ((server (swank:create-server :port port :dont-close t)))
    (format t "~&Swank server listening on port ~A (server: ~A)~%" port server)
    server))

(defun tool-query (input)
  "If INPUT starts with '(', eval as Lisp. Otherwise, send to LLM."
  (if (and (> (length input) 0) (char= (char input 0) #\())
      (let ((expr (read-from-string input)))
        (format nil "~S" (eval expr)))
      (if (and *current-config* (typep *current-config* 'eval-loop-config))
          (let ((res (eval-loop input *current-config*)))
            (or (result-content res) (result-error res)))
          (agent-send input))))

;;; Simple read-line query loop (calls (tool-query ...))
(defun query-loop ()
  "Start interactive read-line loop using (tool-query ...).
   Type Lisp expressions (start with '(') to evaluate.
   Type anything else to send to the LLM.
   Empty line exits."
  (format t "~&~%--- Query Loop (empty line to exit) ---~%")
  (format t "    Lisp expressions (start with '(') are evaluated~%")
  (format t "    Anything else is sent to the LLM~%~%")
  (loop for line = (progn (format t "~&Operator> ") (finish-output) (read-line *standard-input* nil nil))
        while (and line (string/= line ""))
        do (handler-case
               (if (and (> (length line) 0) (char= (char line 0) #\())
                   (progn
                     (format t "~&---------~%")
                     (let ((expr (read-from-string line)))
                       (format t "~S~%" (eval expr)))
                     (format t "---------~%"))
                   (progn
                     (agent-send line)))
             (error (e)
               (format t "~&---------~%")
               (format t "⚠️  ~A~%" e)
               (format t "---------~%")))))