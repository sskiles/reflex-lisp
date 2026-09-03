(in-package #:reflex.context)

(defun %ctx-build-where (session-id)
  "Return the WHERE clause suffix and bind list for SESSION-ID."
  (if session-id
      (values " WHERE session_id = ?" (list session-id))
      (values "" '())))

(defun %ctx-search-rows (db query-embedding session-id)
  "Collect scored rows into a list of plists."
  (multiple-value-bind (where binds)
      (%ctx-build-where session-id)
    (let* ((sql (format nil
                        "SELECT id, kind, content, embedding, embed_dim
                         FROM ~A~A"
                        *context-table-name* where))
           (results '())
           (stmt (sqlite:prepare-statement db sql)))
      (unwind-protect
           (progn
             (loop for i from 1
                   for b in binds
                   do (sqlite:bind-parameter stmt i b))
             (loop while (sqlite:step-statement stmt) do
                   (let* ((id     (sqlite:statement-column-value stmt 0))
                          (kind   (sqlite:statement-column-value stmt 1))
                          (content (sqlite:statement-column-value stmt 2))
                          (blob   (sqlite:statement-column-value stmt 3))
                          (dim    (sqlite:statement-column-value stmt 4)))
                     (when (and blob dim)
                       (let* ((vec (%ctx-unpack-f32-embedding blob dim))
                              (score (%ctx-cosine query-embedding vec)))
                         (push (list :id id :kind kind
                                     :content content :score score)
                               results)))))
             results)
        (sqlite:finalize-statement stmt)))))

(defun context-search (query-embedding &key (k 5) (session-id nil))
  "Return up to K best-matching rows as plists."
  (let ((db (%ctx-connect)))
    (unwind-protect
         (let* ((results (%ctx-search-rows db query-embedding session-id))
                (sorted (sort (copy-list results) #'>
                              :key (lambda (r) (getf r :score)))))
           (subseq sorted 0 (min k (length sorted))))
      (sqlite:disconnect db))))
