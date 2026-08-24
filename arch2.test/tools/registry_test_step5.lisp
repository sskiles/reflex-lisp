;;;; Test step 5 - execute-tool with json but no validator

(defpackage #:harness.tools.registry.testnoVal
  (:use #:cl #:harness.tools.protocol))
(in-package #:harness.tools.registry.testnoVal)

(defmethod execute-tool ((registry tool-registry) (name string) (args hash-table))
  (let ((spec (find-tool registry name)))
    (if (null spec)
        (values nil (format nil "Tool not found: ~A" name))
        (handler-case
            (multiple-value-bind (result err) (funcall (tool-handler spec) args)
              (if err
                  (values nil err)
                  (values (if (stringp result) result
                              (json:encode-json-to-string result))
                          nil)))
          (error (e)
            (values nil (format nil "Tool ~A error: ~A" name e))))))

(format t "Loaded~%")
