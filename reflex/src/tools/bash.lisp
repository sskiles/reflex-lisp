;;; bash tool — execute a shell command and return stdout+stderr+exit code.

(in-package #:reflex.tools)

(defun %read-available (stream)
  "Read all currently-available data from STREAM.  Returns a string.
Does NOT wait for more data — only reads what's buffered right now."
  (with-output-to-string (out)
    (loop while (listen stream) do
          (let ((c (read-char-no-hang stream nil :eof)))
            (when (eq c :eof) (return))
            (write-char c out)))))

(defun %bash-runner (cmd timeout)
  "Run CMD via /bin/sh, return (stdout stderr exit-code).  Kills the process
after TIMEOUT seconds if still alive."
  (let* ((proc (sb-ext:run-program "/bin/sh"
                                   (list "-c" cmd)
                                   :output :stream
                                   :error :stream
                                   :wait nil))
         (out (sb-ext:process-output proc))
         (err (sb-ext:process-error proc))
         (stdout "")
         (stderr "")
         (deadline (+ (get-internal-real-time)
                      (* timeout internal-time-units-per-second))))
    ;; Poll until process finishes or times out, draining output incrementally
    ;; to avoid deadlock on commands that produce lots of output.
    (loop
      (when (not (sb-ext:process-alive-p proc))
        ;; Process finished; drain any remaining buffered output.
        (setf stdout (concatenate 'string stdout (%read-available out)))
        (setf stderr (concatenate 'string stderr (%read-available err)))
        (return-from %bash-runner
          (values stdout stderr (sb-ext:process-exit-code proc))))
      (when (> (get-internal-real-time) deadline)
        (sb-ext:process-kill proc 9)
        (return-from %bash-runner
          (values ""
                  (format nil "killed after ~As timeout" timeout)
                  -1)))
      (setf stdout (concatenate 'string stdout (%read-available out)))
      (setf stderr (concatenate 'string stderr (%read-available err)))
      (sleep 0.05))))

(defun %bash (arguments)
  (let* ((cmd     (or (cdr (assoc "command" arguments :test #'string=))
                      (cdr (assoc :command arguments :test #'eq))))
         (timeout (or (cdr (assoc "timeout" arguments :test #'string=))
                      (cdr (assoc :timeout arguments :test #'eq))
                      30)))
    (handler-case
        (multiple-value-bind (stdout stderr exit-code)
            (%bash-runner cmd timeout)
          (format nil "exit=~A~%stdout=~A~%stderr=~A" exit-code stdout stderr))
      (error (e)
        (format nil "ERROR: ~A" e)))))

(define-tool "bash"
    (:description "Execute a shell command and return its stdout, stderr, and exit code as a string. Use this for any action that doesn't have a dedicated tool (running scripts, listing directories, inspecting system state)."
     :parameters
     (list (cons "type" "object")
           (cons "properties"
                 (list (cons "command"
                             (list (cons "type" "string")
                                   (cons "description" "Shell command line to execute.")))
                       (cons "timeout"
                             (list (cons "type" "integer")
                                   (cons "description" "Timeout in seconds. Defaults to 30.")))))
           (cons "required" (list "command")))
     :function #'%bash))
