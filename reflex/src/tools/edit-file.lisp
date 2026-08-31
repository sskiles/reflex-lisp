;;; edit-file tool — exact string replacement in a file.

(in-package #:reflex.tools)

(defun %edit-file (arguments)
  (let* ((path  (cdr (assoc "path" arguments :test #'string=)))
         (old   (cdr (assoc "old" arguments :test #'string=)))
         (new   (cdr (assoc "new" arguments :test #'string=))))
    (handler-case
        (let ((text (uiop:read-file-string path))
              (start (search old (uiop:read-file-string path))))
          (declare (ignore text))
          (cond
            ((null start)
             (format nil "ERROR: substring not found in ~A" path))
            (t
             (let* ((full (uiop:read-file-string path))
                    (head (subseq full 0 start))
                    (tail (subseq full (+ start (length old))))
                    (replacement (concatenate 'string head new tail)))
               (with-open-file (s path :direction :output :if-exists :supersede)
                 (write-sequence replacement s))
               (format nil "edited ~A (~A chars now)" path (length replacement))))))
      (error (e)
        (format nil "ERROR: ~A" e)))))

(define-tool "edit-file"
    (:description "Make an exact string replacement in a file. The OLD substring must appear exactly once in the file; otherwise the tool returns an error. Use this for surgical edits instead of full rewrites."
     :parameters
     (list (cons "type" "object")
           (cons "properties"
                 (list (cons "path"
                             (list (cons "type" "string")
                                   (cons "description" "Filesystem path.")))
                       (cons "old"
                             (list (cons "type" "string")
                                   (cons "description" "Exact substring to replace. Must appear once.")))
                       (cons "new"
                             (list (cons "type" "string")
                                   (cons "description" "Replacement string.")))))
           (cons "required" (list "path" "old" "new")))
     :function #'%edit-file))
