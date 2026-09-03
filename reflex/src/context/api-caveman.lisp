(in-package #:reflex.context)

(defun %ctx-fetch-row (db row-id)
  "Return (values kind content cached version) for ROW-ID, or NIL if absent."
  (let ((stmt (sqlite:prepare-statement
               db
               (format nil
                       "SELECT kind, content, caveman, caveman_v
                        FROM ~A WHERE id = ?"
                       *context-table-name*))))
    (unwind-protect
         (progn
           (sqlite:bind-parameter stmt 1 row-id)
           (if (sqlite:step-statement stmt)
               (values (sqlite:statement-column-value stmt 0)
                       (sqlite:statement-column-value stmt 1)
                       (sqlite:statement-column-value stmt 2)
                       (sqlite:statement-column-value stmt 3))
               nil))
      (sqlite:finalize-statement stmt))))

(defun %ctx-update-caveman (db row-id fresh)
  "Write FRESH caveman projection back to ROW-ID."
  (sqlite:execute-non-query
   db
   (format nil
           "UPDATE ~A SET caveman=?, caveman_tokens=?, caveman_v=? WHERE id=?"
           *context-table-name*)
   fresh (%ctx-estimate-tokens fresh) *caveman-version* row-id))

(defun context-caveman (row-id)
  "Return the caveman string for ROW-ID, regenerating if stale."
  (let ((db (%ctx-connect)))
    (unwind-protect
         (multiple-value-bind (kind content cached version)
             (%ctx-fetch-row db row-id)
           (cond
             ((null kind) nil)
             ((and cached (= version *caveman-version*))
              cached)
             (t
              (let ((fresh (%ctx-caveman-from-row kind content)))
                (%ctx-update-caveman db row-id fresh)
                fresh))))
      (sqlite:disconnect db))))
