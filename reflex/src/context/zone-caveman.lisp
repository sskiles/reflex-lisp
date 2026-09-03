(in-package #:reflex.context)

(defun %ctx-fetch-caveman (db session-id skip n)
  "Return rows for SESSION-ID offset by SKIP, then up to N more, oldest-first.
Each row: (id kind role content caveman tokens)."
  (let* ((sql (format nil
                      "SELECT id, kind, role, content, caveman, token_count
                       FROM ~A
                       WHERE session_id = ?
                       ORDER BY seq DESC
                       LIMIT ? OFFSET ?"
                      *context-table-name*))
         (stmt (sqlite:prepare-statement db sql))
         (rows '()))
    (unwind-protect
         (progn
           (sqlite:bind-parameter stmt 1 session-id)
           (sqlite:bind-parameter stmt 2 n)
           (sqlite:bind-parameter stmt 3 skip)
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

(defun %ctx-format-caveman (row)
  "Render ROW as a caveman line for zone B.
Uses cached caveman; falls back to context-caveman for stale rows."
  (destructuring-bind (id kind role content caveman tokens &rest ignore) row
    (declare (ignore role content tokens ignore))
    (declare (ignorable kind))
    (format nil "[~A] ~A"
            id
            (or caveman
                (and kind (context-caveman id))))))

(defun %ctx-zone-caveman (session-id skip n &key (token-budget most-positive-fixnum))
  "Build zone B: rows offset by SKIP (e.g. after zone A), caveman form.
Returns (values lines used-tokens)."
  (let ((db (%ctx-connect))
        (lines '())
        (used 0))
    (unwind-protect
         (progn
           (dolist (row (%ctx-fetch-caveman db session-id skip n))
             (let* ((line (%ctx-format-caveman row))
                    (cost (%ctx-tokens-of line)))
               (when (> (+ used cost) token-budget)
                 (return))
               (push line lines)
               (incf used cost)))
           (values (nreverse lines) used))
      (sqlite:disconnect db))))
