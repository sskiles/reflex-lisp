;;; Tests for the sqlite-sql tool.

(in-package #:reflex-test)

(defun %check-sqlite (arguments predicate format-string)
  (let* ((result (reflex.tools:execute-tool-call "sqlite-sql" arguments))
         (ok (and (stringp result) (funcall predicate result))))
    (check ok "sqlite-sql(~S): ~A, got ~S" arguments format-string result)))

(defun test-sqlite ()
  ;; Use a temporary file-based DB so state persists across calls.
  (let ((db-path "/tmp/reflex-test.sqlite"))
    ;; Clean up any leftover DB from a previous run.
    (when (probe-file db-path)
      (delete-file db-path))
    ;; CREATE TABLE.
    (%check-sqlite (list (cons "db" db-path)
                         (cons "sql" "CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);"))
                   (lambda (s) (search "OK" s))
                   "CREATE TABLE should report OK")
    ;; INSERT.
    (%check-sqlite (list (cons "db" db-path)
                         (cons "sql" "INSERT INTO notes (body) VALUES ('hello'), ('world');"))
                   (lambda (s) (search "OK" s))
                   "INSERT should report OK")
    ;; SELECT.
    (%check-sqlite (list (cons "db" db-path)
                         (cons "sql" "SELECT * FROM notes;"))
                   (lambda (s) (and (search "hello" s) (search "world" s)))
                   "SELECT should return inserted rows")
    ;; SELECT with bound parameters - use separate calls.
    (%check-sqlite (list (cons "db" db-path)
                         (cons "sql" "CREATE TABLE p (n INTEGER);"))
                   (lambda (s) (search "OK" s))
                   "CREATE TABLE p should report OK")
    (%check-sqlite (list (cons "db" db-path)
                         (cons "sql" "INSERT INTO p VALUES (1),(2),(3);"))
                   (lambda (s) (search "OK" s))
                   "INSERT p should report OK")
    (%check-sqlite (list (cons "db" db-path)
                         (cons "sql" "SELECT * FROM p WHERE n > ?;")
                         (cons "params" (list "1")))
                   (lambda (s) (and (search "2" s) (search "3" s) (not (search "\"1\"" s))))
                   "SELECT with param should return rows > 1")

  ;; SQL error handling.
  (%check-sqlite (list (cons "db" db-path)
                       (cons "sql" "SELECT * FROM no_such_table"))
                 (lambda (s) (search "ERROR" s))
                 "missing table should return ERROR")

  ;; Empty / missing SQL.
  (%check-sqlite (list (cons "db" db-path))
                 (lambda (s) (search "ERROR" s))
                 "missing sql should error")

  ;; Cleanup
  (delete-file db-path)
  (format t "~&REFLEX sqlite tests passed.~%")
  (finish-output))
)