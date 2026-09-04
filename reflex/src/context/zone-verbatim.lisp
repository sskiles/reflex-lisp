(in-package #:reflex.context)

(defun %ctx-fetch-recent (db session-id n)
  "Return the last N rows for SESSION-ID, oldest-first.
Each row: (id kind role content caveman tokens)."
  (let* ((sql (format nil
                      "SELECT id, kind, role, content, caveman, token_count
                       FROM ~A
                       WHERE session_id = ?
                       ORDER BY seq DESC
                       LIMIT ?"
                      *context-table-name*))
         (stmt (sqlite:prepare-statement db sql))
         (rows '()))
    (unwind-protect
         (progn
           (sqlite:bind-parameter stmt 1 session-id)
           (sqlite:bind-parameter stmt 2 n)
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

(defun %ctx-format-verbatim (row)
  "Render ROW as a verbatim line for zone A."
  (destructuring-bind (id kind role content &rest ignore) row
    (declare (ignore ignore))
    (format nil "[~A] ~A: ~A" id (or role kind) content)))

(defun %ctx-zone-verbatim (session-id n &key (token-budget most-positive-fixnum))
  "Build zone A: the last N rows for SESSION-ID, verbatim, within TOKEN-BUDGET.
Returns a ZONE-RESULT plist."
  (let ((db (%ctx-connect))
        (lines '())
        (used 0)
        (skipped 0)
        (total-fetched 0))
    (unwind-protect
         (progn
           (dolist (row (%ctx-fetch-recent db session-id n))
             (incf total-fetched)
             (let* ((line (%ctx-format-verbatim row))
                    (cost (%ctx-tokens-of line)))
               (when (> (+ used cost) token-budget)
                 (incf skipped)
                 (return))
               (push line lines)
               (incf used cost)))
           (make-zone-result
            :label   "Recent (verbatim)"
            :lines   (nreverse lines)
            :used    used
            :budget  token-budget
            :skipped skipped))
      (sqlite:disconnect db))))
