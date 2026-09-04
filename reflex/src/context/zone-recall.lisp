(in-package #:reflex.context)

(defun %ctx-recall (query-embedding &key k session-id)
  "Search rows similar to QUERY-EMBEDDING, optionally filtered by SESSION-ID.
Returns a list of plists (:ID :KIND :CONTENT :SCORE)."
  (let* ((db (%ctx-connect))
         (results (context-search query-embedding :k k :session-id session-id))
         (db2 db))
    (declare (ignore db2))
    (sqlite:disconnect db)
    results))

(defun %ctx-fetch-content (db id)
  "Return the content string for row ID, or NIL."
  (let ((stmt (sqlite:prepare-statement
               db
               (format nil "SELECT content FROM ~A WHERE id = ?"
                       *context-table-name*))))
    (unwind-protect
         (progn
           (sqlite:bind-parameter stmt 1 id)
           (and (sqlite:step-statement stmt)
                (sqlite:statement-column-value stmt 0)))
      (sqlite:finalize-statement stmt))))

(defun %ctx-format-recall (hit &key snippet)
  "Render a recall HIT as a caveman line, optionally with a verbatim SNIPPET."
  (destructuring-bind (&key id kind content score) hit
    (declare (ignore kind))
    (let* ((cav (context-caveman id))
           (base (format nil "[~A] ~A  (score=~,3F)" id cav score)))
      (if snippet
          (format nil "~A~%      ~A" base (subseq content 0 (min 200 (length content))))
          base))))

(defun %ctx-zone-recall (query-embedding &key k session-id token-budget)
  "Build zone C: semantically recalled history.
Returns a ZONE-RESULT.  ZONE-RESULT-EXTRA holds (hit . score) pairs
for every hit returned by the search (including those that were
skipped due to budget), so the caller can see the full ranking."
  (let* ((hits (%ctx-recall query-embedding :k k :session-id session-id))
         (db (%ctx-connect))
         (lines '())
         (used 0)
         (skipped 0)
         (rank 0)
         (all-scores '()))
    (unwind-protect
         (progn
           (dolist (hit hits)
             (incf rank)
             (let* ((id (getf hit :id))
                    (score (getf hit :score))
                    (snippet (and (<= rank 2)
                                  (%ctx-fetch-content db id)))
                    (line (%ctx-format-recall hit :snippet snippet))
                    (cost (%ctx-tokens-of line)))
               (push (cons hit (coerce score 'double-float)) all-scores)
               (when (> (+ used cost) token-budget)
                 (incf skipped)
                 (return))
               (push line lines)
               (incf used cost)))
           (make-zone-result
            :label   "Relevant history (recall)"
            :lines   (nreverse lines)
            :used    used
            :budget  token-budget
            :skipped skipped
            :extra   (nreverse all-scores)))
      (sqlite:disconnect db))))
