;;;; Test step 7 - add progn wrapper

(defpackage #:harness.tools.registry.testprogn
  (:use #:cl #:harness.tools.protocol))
(in-package #:harness.tools.registry.testprogn)

(defmethod execute-tool ((registry tool-registry) (name string) (args hash-table))
  (let ((spec (find-tool registry name)))
    (if (null spec)
        (values nil (format nil "Tool not found: ~A" name))
        (handler-case
            (progn
              (multiple-value-bind (result err) (funcall (tool-handler spec) args)
                (if err
                    (values nil err)
                    (values result nil))))
          (error (e)
            (values nil (format nil "Tool ~A error: ~A" name e))))))

(format t "Loaded~%")
