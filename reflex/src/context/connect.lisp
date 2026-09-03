(in-package #:reflex.context)

(defparameter *context-ddl*
  (list
   (format nil "
CREATE TABLE IF NOT EXISTS ~A (
  id            INTEGER PRIMARY KEY,
  ts            INTEGER NOT NULL,
  kind          TEXT    NOT NULL,
  role          TEXT,
  content       TEXT    NOT NULL,
  content_hash  TEXT    NOT NULL,
  token_count   INTEGER NOT NULL DEFAULT 0,
  session_id    TEXT,
  turn_id       INTEGER,
  seq           INTEGER NOT NULL,
  tags          TEXT,
  embedding     BLOB,
  embed_model   TEXT,
  embed_dim     INTEGER,
  embed_dtype   TEXT,
  embed_norm    REAL,
  caveman       TEXT,
  caveman_tokens INTEGER,
  caveman_v     INTEGER,
  tool_name     TEXT,
  tool_call_id  TEXT
);"
           *context-table-name*)
   (format nil "CREATE INDEX IF NOT EXISTS ~A_session_seq ON ~A (session_id, seq);"
           *context-table-name* *context-table-name*)
   (format nil "CREATE INDEX IF NOT EXISTS ~A_kind_ts     ON ~A (kind, ts);"
           *context-table-name* *context-table-name*)
   (format nil "CREATE INDEX IF NOT EXISTS ~A_hash        ON ~A (content_hash);"
           *context-table-name* *context-table-name*)
   (format nil "CREATE INDEX IF NOT EXISTS ~A_turn        ON ~A (turn_id);"
           *context-table-name* *context-table-name*))
  "List of DDL statements executed at schema-bootstrap time.")

(defun %ctx-connect ()
  "Open a fresh SQLite connection to *context-db-path*."
  (sqlite:connect *context-db-path*))

(defun %ctx-execute-ddl (db stmt)
  "Prepare, execute, and finalize a single DDL statement."
  (let ((p (sqlite:prepare-statement db stmt)))
    (unwind-protect
         (sqlite:step-statement p)
      (sqlite:finalize-statement p))))

(defun %ctx-ensure-schema ()
  "Create the context table + indexes if missing.  Idempotent."
  (ensure-directories-exist *context-db-path*)
  (let ((db (%ctx-connect)))
    (unwind-protect
         (progn
           (dolist (stmt *context-ddl*)
             (%ctx-execute-ddl db stmt)))
      (sqlite:disconnect db))))

(eval-when (:load-toplevel :execute)
  (handler-case (%ctx-ensure-schema)
    (error (e)
      (format *error-output*
              "~&[reflex.context] schema bootstrap failed: ~A~%" e))))
