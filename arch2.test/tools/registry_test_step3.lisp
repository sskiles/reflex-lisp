;;;; Test step 3 - add json:encode-json-to-string

(defpackage #:harness.tools.registry.test5withjson
  (:use #:cl #:harness.tools.protocol))
(in-package #:harness.tools.registry.test5withjson)

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
                    (values (if (stringp result) result
                                (json:encode-json-to-string result))
                            nil)))
            (tool-validation-error (e) (values nil (format nil "Validation error: ~A" e)))
            (error (e)
              (values nil (format nil "Tool ~A error: ~A" name e)))))))

(format t "Loaded~%")
