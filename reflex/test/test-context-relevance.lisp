(in-package #:reflex-test)

(defvar *relevance-test-top-k* 5)
(defvar *relevance-test-verbose* nil)

(defun %corpus-table-name ()
  (symbol-value (find-symbol "*CONTEXT-TABLE-NAME*" :reflex.context)))

(defun %relevance-find-row-by-path (path)
  (let ((db (sqlite:connect "/home/reflex/.cache/reflex/reflex.sqlite")))
    (unwind-protect
         (let ((stmt (sqlite:prepare-statement
                      db
                      (format nil
                              "SELECT id FROM ~A WHERE session_id = 'corpus' AND tool_name = ? LIMIT 1"
                              (%corpus-table-name)))))
           (sqlite:bind-parameter stmt 1 path)
           (let ((found (sqlite:step-statement stmt)))
             (declare (ignore found))
             (and found (sqlite:statement-column-value stmt 0))))
      (sqlite:disconnect db))))

(defun %relevance-embed-fn ()
  (symbol-value (find-symbol "*EMBED-FN*" :reflex.context)))

(defun %relevance-context-search-fn ()
  (symbol-function (find-symbol "CONTEXT-SEARCH" :reflex.context)))

(defun %relevance-corpus ()
  (symbol-value (find-symbol "*FILE-CORPUS*" :reflex.context)))

(defun %relevance-corpus-count ()
  (let ((db (sqlite:connect "/home/reflex/.cache/reflex/reflex.sqlite")))
    (unwind-protect
         (let ((stmt (sqlite:prepare-statement
                      db
                      (format nil "SELECT count(*) FROM ~A WHERE session_id = 'corpus'"
                              (%corpus-table-name)))))
           (sqlite:step-statement stmt)
           (sqlite:statement-column-value stmt 0))
      (sqlite:disconnect db))))

(defun %relevance-run-cosine-test ()
  (let ((corpus (%relevance-corpus))
        (embed-fn (%relevance-embed-fn))
        (search-fn (%relevance-context-search-fn))
        (pass 0)
        (total 0))
    (unless embed-fn (return-from %relevance-run-cosine-test (values 0 0)))
    (dolist (entry corpus)
      (destructuring-bind (path . description) entry
        (incf total)
        (let* ((expected-id (%relevance-find-row-by-path path))
               (query-vec (funcall embed-fn description))
               (hits (funcall search-fn query-vec
                              :k *relevance-test-top-k*
                              :session-id "corpus"))
               (found-rank nil))
          (loop for hit in hits
                for rank from 1
                when (= (getf hit :id) expected-id)
                do (setf found-rank rank))
          (if found-rank
              (progn (incf pass)
                     (when *relevance-test-verbose*
                       (format t "  [PASS] ~A  rank=~D~%" path found-rank)))
              (when *relevance-test-verbose*
                (format t "  [FAIL] ~A  (expected id=~A)~%" path expected-id))))))
    (values pass total)))

(defun %relevance-assemble-fn ()
  (symbol-function (find-symbol "CONTEXT-ASSEMBLE-PROMPT" :reflex.context)))

(defun %relevance-run-assemble-test ()
  (let ((corpus (%relevance-corpus))
        (embed-fn (%relevance-embed-fn))
        (assemble-fn (%relevance-assemble-fn))
        (pass 0)
        (total 0))
    (unless embed-fn (return-from %relevance-run-assemble-test (values 0 0)))
    (dolist (entry corpus)
      (destructuring-bind (path . description) entry
        (incf total)
        (let ((prompt (funcall assemble-fn description
                                :session-id "corpus"
                                :total-budget 4000
                                :embed-fn embed-fn
                                :report-stream nil)))
          (if (search path prompt)
              (progn (incf pass)
                     (when *relevance-test-verbose*
                       (format t "  [PASS] ~A  found in prompt~%" path)))
              (when *relevance-test-verbose*
                (format t "  [FAIL] ~A  not in prompt~%" path))))))
    (values pass total)))

(defun %relevance-index-corpus-fn ()
  (symbol-function (find-symbol "%CTX-INDEX-FILE-CORPUS" :reflex.context)))

(defun test-context-relevance ()
  (format t "~&[relevance] Starting context relevance test...~%")
  (let ((existing (%relevance-corpus-count)))
    (format t "[relevance] corpus has ~D rows in session 'corpus'~%" existing)
    (when (zerop existing)
      (format t "[relevance] Indexing corpus...~%")
      (let ((n (funcall (%relevance-index-corpus-fn))))
        (format t "[relevance] Indexed ~D files~%" n))))
  (unless (%relevance-embed-fn)
    (format t "[relevance] No embedder configured (call reflex:install-nvidia-embedder first)~%")
    (return-from test-context-relevance))
  (format t "~&[relevance] === Cosine top-~A recall test ===~%"
          *relevance-test-top-k*)
  (multiple-value-bind (pass total)
      (%relevance-run-cosine-test)
    (format t "[relevance] Cosine: ~D/~D passed (~,1F%)~%"
            pass total
            (if (zerop total) 0.0 (* 100.0 (/ pass total)))))
  (format t "~&[relevance] === Assemble-prompt test ===~%")
  (multiple-value-bind (pass total)
      (%relevance-run-assemble-test)
    (format t "[relevance] Assemble: ~D/~D passed (~,1F%)~%"
            pass total
            (if (zerop total) 0.0 (* 100.0 (/ pass total))))))
