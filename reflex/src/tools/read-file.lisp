;;; read-file tool — read a file's contents and return them as a string.

(in-package #:reflex.tools)

(defun %read-file (arguments)
  (let* ((path (cdr (assoc "path" arguments :test #'string=)))
         (limit (or (cdr (assoc "limit" arguments :test #'string=)) 1000000)))
    (handler-case
        (with-open-file (s path :direction :input)
          (let ((buf (make-string limit)))
            (let ((n (read-sequence buf s)))
              (subseq buf 0 n))))
      (error (e)
        (format nil "ERROR: ~A" e)))))

(define-tool "read-file"
    (:description "Read a file's contents and return them as a string. Use this to inspect files before editing."
     :parameters
     (list (cons "type" "object")
           (cons "properties"
                 (list (cons "path"
                             (list (cons "type" "string")
                                   (cons "description" "Filesystem path to read.")))
                       (cons "limit"
                             (list (cons "type" "integer")
                                   (cons "description" "Maximum number of characters to read. Defaults to 1,000,000.")))))
           (cons "required" (list "path")))
     :function #'%read-file))
