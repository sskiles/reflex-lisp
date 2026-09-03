(in-package #:reflex.context)

(defun %ctx-replay-rows (db session-id)
  "Return a list of (id kind role content caveman tokens) for SESSION-ID."
  (let ((rows '())
        (stmt (sqlite:prepare-statement
               db
               (format nil
                       "SELECT id, kind, role, content, caveman, token_count
                        FROM ~A
                        WHERE session_id = ?
                        ORDER BY seq ASC"
                       *context-table-name*))))
    (unwind-protect
         (progn
           (sqlite:bind-parameter stmt 1 session-id)
           (loop while (sqlite:step-statement stmt) do
                 (push (list (sqlite:statement-column-value stmt 0)
                             (sqlite:statement-column-value stmt 1)
                             (sqlite:statement-column-value stmt 2)
                             (sqlite:statement-column-value stmt 3)
                             (sqlite:statement-column-value stmt 4)
                             (sqlite:statement-column-value stmt 5))
                       rows))
           (nreverse rows))
      (sqlite:finalize-statement stmt))))

(defun %ctx-format-line (mode row)
  "Format a single replay row according to MODE (:FULL/:CAVEMAN/:SUMMARY)."
  (destructuring-bind (id kind role content caveman _ &rest ignore) row
    (declare (ignore ignore))
    (ecase mode
      (:full
       (format nil "[~A] ~A: ~A" id (or role kind) content))
      (:caveman
       (format nil "[~A] ~A" id (or caveman (context-caveman id))))
      (:summary
       (format nil "[~A] ~A" id (or caveman (context-caveman id)))))))

(defun context-replay (session-id &key (mode :caveman) (budget 1500))
  "Build a compact transcript for SESSION-ID within BUDGET tokens."
  (check-type mode (member :caveman :summary :full))
  (let ((db (%ctx-connect))
        (rows '())
        (used 0))
    (unwind-protect
         (progn
           (dolist (row (%ctx-replay-rows db session-id))
             (let* ((tokens (sixth row))
                    (line (%ctx-format-line mode row)))
               (when (> (+ used tokens) budget)
                 (return))
               (push line rows)
               (incf used tokens)))
           (nreverse rows))
      (sqlite:disconnect db))))
