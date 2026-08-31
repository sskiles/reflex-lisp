;;;; db.lisp - Context Engine SQLite Database Harness

(defpackage #:harness.stage-0.db
  (:use #:cl)
  (:export
   #:init-db
   #:close-db
   #:with-db
   #:insert-message
   #:get-message
   #:update-message
   #:delete-message
   #:list-messages
   #:vector-to-blob
   #:blob-to-vector
   #:cosine-similarity
   #:semantic-search-messages))

(in-package #:harness.stage-0.db)

;;; --- SQLite Global Connection Management ---

(defvar *db-path* "data/context-engine.db"
  "Path to the context engine SQLite database.")

(defvar *db* nil
  "Thread-local or global database connection handle.")

(defun init-db (&optional (path *db-path*))
  "Initialize the database connection and create the tables if they do not exist."
  (setf *db-path* path)
  (let ((db (sqlite:connect path)))
    (sqlite:execute-non-query db "PRAGMA busy_timeout = 5000;")
    (sqlite:execute-non-query
     db
     "CREATE TABLE IF NOT EXISTS messages (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         session_id TEXT NOT NULL,
         timestamp INTEGER NOT NULL,
         role TEXT NOT NULL,
         content_raw TEXT NOT NULL,
         content_caveman TEXT,
         embedding BLOB,
         processed INTEGER DEFAULT 0
      );")
    (sqlite:execute-non-query
     db
     "CREATE INDEX IF NOT EXISTS idx_session_time ON messages(session_id, timestamp DESC);")
    (setf *db* db)
    db))

(defun close-db ()
  "Close the global database connection."
  (when *db*
    (sqlite:disconnect *db*)
    (setf *db* nil)))

(defmacro with-db ((db-var &optional (path '*db-path*)) &body body)
  "Execute body within a dynamically opened/closed database context."
  `(let ((,db-var (sqlite:connect ,path)))
     (sqlite:execute-non-query ,db-var "PRAGMA busy_timeout = 5000;")
     (unwind-protect
          (progn ,@body)
       (sqlite:disconnect ,db-var))))

;;; --- Vector & Embedding Serialization Helpers ---

(defun vector-to-blob (vec)
  "Convert a Common Lisp vector of single-float values to a binary static array/byte vector (little endian IEEE-754 floats)."
  (if (null vec)
      nil
      (let* ((len (length vec))
             (bytes (make-array (* len 4) :element-type '(unsigned-byte 8))))
        (loop for i from 0 below len
              for val = (coerce (aref vec i) 'single-float)
              for bits = (sb-kernel:single-float-bits val)
              do (setf (aref bytes (+ (* i 4) 0)) (ldb (byte 8 0) bits)
                       (aref bytes (+ (* i 4) 1)) (ldb (byte 8 8) bits)
                       (aref bytes (+ (* i 4) 2)) (ldb (byte 8 16) bits)
                       (aref bytes (+ (* i 4) 3)) (ldb (byte 8 24) bits)))
        bytes)))

(defun blob-to-vector (blob)
  "Convert a binary blob (vector of bytes representing little-endian floats) back to a Lisp array of floats."
  (if (null blob)
      nil
      (let* ((byte-len (length blob))
             (float-len (truncate byte-len 4))
             (vec (make-array float-len :element-type 'single-float)))
        (loop for i from 0 below float-len
              for unsigned-bits = (logior (aref blob (+ (* i 4) 0))
                                          (ash (aref blob (+ (* i 4) 1)) 8)
                                          (ash (aref blob (+ (* i 4) 2)) 16)
                                          (ash (aref blob (+ (* i 4) 3)) 24))
              ;; Convert unsigned 32-bit to signed 32-bit integer for sb-kernel:make-single-float
              for bits = (if (logbitp 31 unsigned-bits)
                             (- unsigned-bits (ash 1 32))
                             unsigned-bits)
              do (setf (aref vec i) (sb-kernel:make-single-float bits)))
        vec)))

;;; --- Vector Similarity Logic ---

(defun cosine-similarity (vec1 vec2)
  "Calculate the cosine similarity between two single-float vectors."
  (if (or (null vec1) (null vec2) (/= (length vec1) (length vec2)))
      0.0
      (let ((dot-product 0.0)
            (norm1 0.0)
            (norm2 0.0))
        (loop for i from 0 below (length vec1)
              for x = (aref vec1 i)
              for y = (aref vec2 i)
              do (incf dot-product (* x y))
                 (incf norm1 (* x x))
                 (incf norm2 (* y y)))
        (if (or (zerop norm1) (zerop norm2))
            0.0
            (/ dot-product (* (sqrt norm1) (sqrt norm2)))))))

;;; --- CRUD Operations ---

(defun insert-message (&key session-id role content-raw content-caveman embedding (processed 0) (db *db*))
  "Insert a message record. Returns the new record ID."
  (let ((timestamp (get-universal-time))
        (blob (vector-to-blob embedding)))
    (sqlite:execute-non-query
     db
     "INSERT INTO messages (session_id, timestamp, role, content_raw, content_caveman, embedding, processed)
      VALUES (?, ?, ?, ?, ?, ?, ?);"
     session-id timestamp role content-raw content-caveman blob processed)
    (sqlite:execute-single db "SELECT last_insert_rowid();")))

(defun get-message (id &key (db *db*))
  "Retrieve a single message as a property list."
  (let ((row (first (sqlite:execute-to-list
                     db
                     "SELECT id, session_id, timestamp, role, content_raw, content_caveman, embedding, processed
                      FROM messages WHERE id = ?;" id))))
    (when row
      (destructuring-bind (mid session-id timestamp role content-raw content-caveman embedding processed) row
        (list :id mid
              :session-id session-id
              :timestamp timestamp
              :role role
              :content-raw content-raw
              :content-caveman content-caveman
              :embedding (blob-to-vector embedding)
              :processed processed)))))

(defun update-message (id &key session-id role content-raw content-caveman embedding processed (db *db*))
  "Update fields of a message by ID. Recalculates modified fields or resets processed status if content updates."
  (let* ((existing (get-message id :db db))
         (new-session-id (or session-id (getf existing :session-id)))
         (new-role (or role (getf existing :role)))
         (new-content-raw (or content-raw (getf existing :content-raw)))
         (new-content-caveman (or content-caveman (getf existing :content-caveman)))
         (new-embedding (if embedding (vector-to-blob embedding) (vector-to-blob (getf existing :embedding))))
         ;; If the raw content is explicitly changed, we default to processed = 0 (needs embedding recalculation)
         (new-processed (cond (processed processed)
                              (content-raw 0)
                              (t (getf existing :processed)))))
    (sqlite:execute-non-query
     db
     "UPDATE messages
      SET session_id = ?, role = ?, content_raw = ?, content_caveman = ?, embedding = ?, processed = ?
      WHERE id = ?;"
     new-session-id new-role new-content-raw new-content-caveman new-embedding new-processed id)
    t))

(defun delete-message (id &key (db *db*))
  "Delete a message by ID."
  (sqlite:execute-non-query db "DELETE FROM messages WHERE id = ?;" id)
  t)

(defun list-messages (&key session-id limit (db *db*))
  "List all messages, optionally filtered by session-id and limited to latest N."
  (let* ((query "SELECT id, session_id, timestamp, role, content_raw, content_caveman, embedding, processed FROM messages")
         (params '()))
    (when session-id
      (setf query (concatenate 'string query " WHERE session_id = ?"))
      (push session-id params))
    (setf query (concatenate 'string query " ORDER BY timestamp DESC"))
    (when limit
      (setf query (format nil "~A LIMIT ~D" query limit)))
    (let ((rows (apply #'sqlite:execute-to-list db query (nreverse params))))
      (mapcar (lambda (row)
                (destructuring-bind (mid sess time role raw caveman embed proc) row
                  (list :id mid
                        :session-id sess
                        :timestamp time
                        :role role
                        :content-raw raw
                        :content-caveman caveman
                        :embedding (blob-to-vector embed)
                        :processed proc)))
              rows))))

;;; --- Semantic Vector Search Harness ---

(defun semantic-search-messages (query-embedding &key (session-id "kb_facts") (limit 5) (threshold 0.0) (db *db*))
  "Search messages in a namespace (session_id) comparing query-embedding via cosine similarity.
   Returns a list of plists containing message fields and a :similarity score."
  (let ((all-candidates (sqlite:execute-to-list
                         db
                         "SELECT id, session_id, timestamp, role, content_raw, content_caveman, embedding, processed
                          FROM messages WHERE session_id = ? AND processed = 1 AND embedding IS NOT NULL;"
                         session-id))
        (results '()))
    (dolist (row all-candidates)
      (destructuring-bind (mid sess time role raw caveman embed-blob proc) row
        (let* ((candidate-embed (blob-to-vector embed-blob))
               (similarity (cosine-similarity query-embedding candidate-embed)))
          (when (>= similarity threshold)
            (push (list :id mid
                        :session-id sess
                        :timestamp time
                        :role role
                        :content-raw raw
                        :content-caveman caveman
                        :similarity similarity
                        :processed proc)
                  results)))))
    ;; Sort by similarity descending, then slice limit
    (let ((sorted (sort results #'> :key (lambda (x) (getf x :similarity)))))
      (if (> (length sorted) limit)
          (subseq sorted 0 limit)
          sorted))))
