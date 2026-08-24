;;;; test-db.lisp - Test harness for the Context Engine Database Layer

(defpackage #:harness.stage-0.db-test
  (:use #:cl #:harness.stage-0.db)
  (:export #:run-db-tests))

(in-package #:harness.stage-0.db-test)

(defun float-vector-equal (v1 v2 &key (epsilon 1.0e-5))
  (and (= (length v1) (length v2))
       (every (lambda (x y) (< (abs (- x y)) epsilon)) v1 v2)))

(defvar *test-db-path* "test-context-engine.db")

(defun run-db-tests ()
  (format t "Running Database Harness Tests...~%")
  (when (probe-file *test-db-path*)
    (delete-file *test-db-path*))
  
  (let ((db (init-db *test-db-path*)))
    (unwind-protect
         (progn
           ;; 1. Test insertion and retrieval of raw messages
           (format t "Testing Insertion & Retrieval... ")
           (let* ((msg-id (insert-message :session-id "session_123"
                                         :role "user"
                                         :content-raw "Hello database!"
                                         :db db))
                  (retrieved (get-message msg-id :db db)))
             (assert msg-id)
             (assert (string= (getf retrieved :session-id) "session_123"))
             (assert (string= (getf retrieved :role) "user"))
             (assert (string= (getf retrieved :content-raw) "Hello database!"))
             (assert (null (getf retrieved :embedding)))
             (assert (= (getf retrieved :processed) 0))
             (format t "PASS~%"))

           ;; 2. Test Blob / Vector conversion serialization
           (format t "Testing Embedding serialization & deserialization... ")
           (let* ((test-vector (make-array 4 :element-type 'single-float :initial-contents '(1.0 -2.5 3.14 0.0)))
                  (blob (vector-to-blob test-vector))
                  (restored (blob-to-vector blob)))
             (assert blob)
             (assert (float-vector-equal test-vector restored))
             (format t "PASS~%"))

           ;; 3. Test Cosine Similarity logic
           (format t "Testing Cosine Similarity calculation... ")
           (let ((v1 (make-array 3 :element-type 'single-float :initial-contents '(1.0 0.0 0.0)))
                 (v2 (make-array 3 :element-type 'single-float :initial-contents '(0.0 1.0 0.0)))
                 (v3 (make-array 3 :element-type 'single-float :initial-contents '(0.5 0.5 0.0))))
             ;; Orthogonal vectors similarity = 0
             (assert (< (abs (cosine-similarity v1 v2)) 1.0e-5))
             ;; Identical vector similarity = 1
             (assert (< (abs (- (cosine-similarity v1 v1) 1.0)) 1.0e-5))
             ;; Similarity between (1,0,0) and (0.5, 0.5, 0) is 1/sqrt(2) = 0.7071
             (assert (< (abs (- (cosine-similarity v1 v3) 0.70710678)) 1.0e-4))
             (format t "PASS~%"))

           ;; 4. Test Update operation
           (format t "Testing Update operation... ")
           (let* ((msg-id (insert-message :session-id "kb_facts"
                                         :role "system"
                                         :content-raw "Initial pure fact"
                                         :db db))
                  (embedding (make-array 3 :element-type 'single-float :initial-contents '(0.1 0.2 0.3))))
             (update-message msg-id :content-raw "Updated pure fact" :embedding embedding :processed 1 :db db)
             (let ((updated (get-message msg-id :db db)))
               (assert (string= (getf updated :content-raw) "Updated pure fact"))
               (assert (float-vector-equal (getf updated :embedding) embedding))
               (assert (= (getf updated :processed) 1)))
             (format t "PASS~%"))

           ;; 5. Test Vector Search operation
           (format t "Testing Semantic Vector Search... ")
           (let ((e1 (make-array 3 :element-type 'single-float :initial-contents '(1.0 0.0 0.0)))
                 (e2 (make-array 3 :element-type 'single-float :initial-contents '(0.0 1.0 0.0)))
                 (query (make-array 3 :element-type 'single-float :initial-contents '(0.9 0.1 0.0))))
             ;; Insert two candidates in KB namespace
             (insert-message :session-id "kb_facts" :role "system" :content-raw "Match A" :embedding e1 :processed 1 :db db)
             (insert-message :session-id "kb_facts" :role "system" :content-raw "Match B" :embedding e2 :processed 1 :db db)
             ;; Perform search
             (let ((hits (semantic-search-messages query :session-id "kb_facts" :limit 5 :db db)))
               (assert (= (length hits) 3)) ; including the updated message from test 4
               ;; The closest match should be "Match A"
               (assert (string= (getf (first hits) :content-raw) "Match A"))
               (assert (> (getf (first hits) :similarity) 0.9))))
           (format t "PASS~%"))
      
      ;; Cleanup database file
      (close-db)
      (when (probe-file *test-db-path*)
        (delete-file *test-db-path*)))))

(run-db-tests)
(sb-ext:exit)
