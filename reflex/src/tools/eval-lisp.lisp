;;; eval-lisp tool — execute a Lisp expression in the running SBCL image.

(in-package #:reflex.tools)

(defun %eval-lisp (arguments)
  "Tool implementation: evaluate the Lisp expression in ARGUMENTS[\"expression\"]
and return the result as a string. Errors are caught and returned as ERROR:..."
  (let ((expression (or (cdr (assoc "expression" arguments :test #'string=))
                        (cdr (assoc :expression arguments :test #'eq)))))
    (handler-case
        (let* ((form (read-from-string expression))
               (result (eval form)))
          (cond
            ((null result) "NIL")
            ((stringp result) result)
            (t (format nil "~S" result))))
      (error (e)
        (format nil "ERROR: ~A" e)))))

(define-tool "eval-lisp"
    (:description "Evaluate a Lisp expression in the running SBCL image and return the result as a string. Use this to actually RUN Lisp code, not just print it. The image is fully interactive; you can define functions, modify variables, load files, and inspect any state."
     :parameters
     (list (cons "type" "object")
           (cons "properties"
                 (list (cons "expression"
                             (list (cons "type" "string")
                                   (cons "description" "A Lisp expression to evaluate, e.g. \"(+ 1 2)\".")))))
           (cons "required" (list "expression")))
     :function #'%eval-lisp))