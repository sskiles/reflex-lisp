;;;; Test execute-tool with validator only

(defpackage #:harness.tools.registry.testvalonly
  (:use #:cl #:harness.tools.protocol))
(in-package #:harness.tools.registry.testvalonly)

(defmethod execute-tool ((registry tool-registry) (name string) (args hash-table))
  (let ((spec (find-tool registry name)))
    (if (null spec)
        (values nil (format nil "Tool not found: ~A" name))
        (handler-case
            (progn
              (when (tool-validator spec)
                (multiple-value-bind (valid err) (funcall (tool-validator spec) args)
                  (unless valid
                    (error 'tool-validation-error
                           :tool-name name
                           :reason err))))
              (multiple-value-bind (result err) (funcall (tool-handler spec) args)
                (if err
                    (values nil err)
                    (values result nil))))
          (error (e)
            (values nil (format nil "Tool ~A error: ~A" name e))))))

(format t "~&[harness.tools.registry.testvalonly] Loaded~%")