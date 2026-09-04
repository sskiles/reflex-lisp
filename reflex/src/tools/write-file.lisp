;;; write-file tool — create or overwrite a file.

(in-package #:reflex.tools)

(defun %write-file (arguments)
  (let* ((path    (or (cdr (assoc "path" arguments :test #'string=))
                      (cdr (assoc :path arguments :test #'eq))))
         (content (or (cdr (assoc "content" arguments :test #'string=))
                      (cdr (assoc :content arguments :test #'eq)))))
    (handler-case
        (progn
          (ensure-directories-exist path)
          (with-open-file (s path :direction :output :if-exists :supersede)
            (write-sequence content s))
          (format nil "wrote ~A chars to ~A" (length content) path))
      (error (e)
        (format nil "ERROR: ~A" e)))))

(define-tool "write-file"
    (:description "Create or overwrite a file with the given content. Useful for scaffolding new files or completely replacing existing ones."
     :parameters
     (list (cons "type" "object")
           (cons "properties"
                 (list (cons "path"
                             (list (cons "type" "string")
                                   (cons "description" "Filesystem path to write.")))
                       (cons "content"
                             (list (cons "type" "string")
                                   (cons "description" "File content.")))))
           (cons "required" (list "path" "content")))
     :function #'%write-file))