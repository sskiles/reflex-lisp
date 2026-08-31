;;;; Test execute-tool with minimal handler

(defpackage #:harness.tools.registry.testmin
  (:use #:cl #:harness.tools.protocol))
(in-package #:harness.tools.registry.testmin)

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
          (tool-validation-error (e) (values nil (format nil "Validation error: ~A" e)))
          (error (e)
            (values nil (format nil "Tool ~A error: ~A" name e))))))

(format t "~&[harness.tools.registry.testmin] Loaded~%")