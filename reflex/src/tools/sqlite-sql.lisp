;;; sqlite-sql tool — run a single SQL statement against a SQLite database.
;;;
;;; Connection is opened and closed per call so no stale handles survive a
;;; save/restore.  The DB file is the source of truth.

(in-package #:reflex.tools)

(defparameter *default-sqlite-path*
  (merge-pathnames "reflex.sqlite"
                   (merge-pathnames ".cache/reflex/"
                                    (user-homedir-pathname)))
  "Default SQLite database path used by sqlite-sql when no :db is supplied.")

(defun %resolve-db-path (path)
  (cond
    ((null path) *default-sqlite-path*)
    ((string= path ":memory:") ":memory:")
    (t (merge-pathnames path))))

(defun %starts-with-select-p (sql)
  (let ((s (string-trim '(#\Space #\Tab #\Newline #\Return) sql)))
    (or (string-equal s "SELECT" :end1 6)
        (string-equal s "WITH" :end1 4)
        (string-equal s "PRAGMA" :end1 6)
        (string-equal s "EXPLAIN" :end1 7))))

(defun %bind-params (stmt params)
  (loop for p in params
        for i from 1
        do (sqlite:bind-parameter stmt i p)))

(defun %execute-select (db sql params)
  (let ((stmt (sqlite:prepare-statement db sql)))
    (unwind-protect
         (progn
           (when params (%bind-params stmt params))
           (let ((columns (sqlite:statement-column-names stmt))
                 (rows '()))
             (loop
               (when (not (sqlite:step-statement stmt))
                 (return))
               (push (loop for i from 0 below (length columns)
                           collect (sqlite:statement-column-value stmt i))
                     rows))
             (json:encode-json-alist-to-string
              (list (cons "columns" columns)
                    (cons "rows" (nreverse rows))))))
      (sqlite:finalize-statement stmt))))

(defun %execute-write (db sql params)
  (apply #'sqlite:execute-non-query db sql params)
  (format nil "OK; last-insert-rowid=~A" (sqlite:last-insert-rowid db)))

(defun %sqlite-sql (arguments)
  (let* ((path (%resolve-db-path (cdr (assoc "db" arguments :test #'string=))))
         (sql (cdr (assoc "sql" arguments :test #'string=)))
         (params (cdr (assoc "params" arguments :test #'string=))))
    (if (null sql)
        "ERROR: missing required parameter 'sql'"
        (handler-case
            (let ((db (sqlite:connect path)))
              (unwind-protect
                   (if (%starts-with-select-p sql)
                       (%execute-select db sql params)
                       (%execute-write db sql params))
                (sqlite:disconnect db)))
          (sqlite:sqlite-error (e)
            (format nil "ERROR: ~A" (sqlite:sqlite-error-message e)))
          (error (e)
            (format nil "ERROR: ~A" e))))))

(define-tool "sqlite-sql"
    (:description "Run a single SQL statement against a SQLite database and return the result. For SELECT/WITH/PRAGMA/EXPLAIN queries, returns a JSON object with 'columns' and 'rows' arrays. For INSERT/UPDATE/DELETE/CREATE/DROP, returns 'OK' and the last-insert-rowid. The connection is opened and closed per call, so it is safe across save-image/restore. Pass ':memory:' as the db to use an ephemeral in-memory database."
     :parameters
     (list (cons "type" "object")
           (cons "properties"
                 (list (cons "db"
                             (list (cons "type" "string")
                                   (cons "description" "Path to SQLite database file, or ':memory:' for an in-memory database. Defaults to ~/.cache/reflex/reflex.sqlite (created if it does not exist).")))
                       (cons "sql"
                             (list (cons "type" "string")
                                   (cons "description" "SQL statement to execute. May contain ? placeholders for bound parameters.")))
                       (cons "params"
                             (list (cons "type" "array")
                                   (cons "description" "Optional list of values to bind to ? placeholders in order.")
                                   (cons "items" (list (cons "type" "string")))))))
           (cons "required" (list "sql")))
     :function #'%sqlite-sql))