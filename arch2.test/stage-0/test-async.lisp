;;;; test-async.lisp - Test harness for the Context Engine Async Processor

(defpackage #:harness.stage-0.async-test
  (:use #:cl
        #:harness.stage-0.db
        #:harness.stage-0.async-processor)
  (:export #:run-async-tests))

(in-package #:harness.stage-0.async-test)

(defvar *test-db-path* "test-async-context-engine.db")

(defun run-async-tests ()
  (format t "Running Async Background Processor Tests...~%")
  
  ;; 1. Test Caveman Generation logic
  (format t "Testing Caveman String transformation... ")
  (let* ((input "The quick brown fox jumps over the lazy dog! And it's a test.")
         (caveman (process-caveman-string input)))
    (assert (string= caveman "quick brown fox jumps lazy dog test"))
    (format t "PASS~%"))

  ;; 2. Verify API key is available for integration testing
  (unless harness.stage-0.nvidia:*nvidia-api-key*
    (format t "Skipping live NVIDIA Embedding API tests because NVIDIA_API_KEY is not set.~%")
    (sb-ext:exit))

  ;; 3. Live test of NVIDIA Embedding API
  (format t "Testing Live NVIDIA Embedding API... ")
  (handler-case
      (let ((embed (get-embedding-via-nvidia "Lisp macros are powerful.")))
        (assert (vectorp embed))
        (assert (= (length embed) 4096))
        (assert (typep (aref embed 0) 'single-float))
        (format t "PASS (Length: ~D)~%" (length embed)))
    (error (e)
      (format t "FAIL (~A)~%" e)
      (sb-ext:exit :code 1)))

  ;; 4. Live Background Thread processing loop test
  (format t "Testing Background Thread integration... ")
  (when (probe-file *test-db-path*)
    (delete-file *test-db-path*))

  (let ((db (init-db *test-db-path*)))
    (unwind-protect
         (progn
           ;; Insert an unprocessed raw message
           (let ((rowid (insert-message :session-id "session_async"
                                        :role "user"
                                        :content-raw "Test async integration."
                                        :db db)))
             (assert rowid)
             (close-db) ; Close main thread connection handle to avoid lock

             ;; Start background thread
             (start-background-processor *test-db-path*)
             
             ;; Wait for background thread to run and update processed flag (max 5 seconds)
             (loop for attempt from 1 to 25
                   do (sleep 0.2)
                      (with-db (chk-db *test-db-path*)
                        (let ((msg (get-message rowid :db chk-db)))
                          (when (= (getf msg :processed) 1)
                            (assert (string= (getf msg :content-caveman) "test async integration"))
                            (assert (= (length (getf msg :embedding)) 4096))
                            (return))))
                   finally (error "Background processor did not process message within timeout"))
             
             (stop-background-processor)
             (format t "PASS~%")))
      
      (close-db)
      (stop-background-processor)
      (when (probe-file *test-db-path*)
        (delete-file *test-db-path*)))))

(run-async-tests)
(sb-ext:exit)
