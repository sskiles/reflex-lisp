(in-package #:reflex.context)

(defparameter *context-db-path*
  (merge-pathnames ".cache/reflex/reflex.sqlite"
                   (user-homedir-pathname))
  "SQLite database file used for persistent context storage.")

(defparameter *context-table-name* "context"
  "Table name for the context rows.")

(defparameter *caveman-version* 1
  "Bump when the caveman grammar changes; cached rows are regenerated lazily.")
