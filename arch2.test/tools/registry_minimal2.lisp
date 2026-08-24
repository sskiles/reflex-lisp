;;;; Minimal registry test - define condition locally

(defpackage #:harness.tools.registry.test2
  (:use #:cl))
(in-package #:harness.tools.registry.test2)

(define-condition tool-error (error)
  ((tool-name :initarg :tool-name :reader tool-error-name))
  (:report (lambda (c s) (format s "Tool error in ~A" (tool-error-name c)))))

(define-condition tool-validation-error (tool-error)
  ((reason :initarg :reason :reader validation-error-reason))
  (:report (lambda (c s) (format s "Validation failed: ~A" (validation-error-reason c)))))

(defclass tool-registry ()
  ((tools :initform (make-hash-table :test 'equal) :accessor registry-tools)))

(defclass tool-spec ()
  ((name :initarg :name :reader tool-name :type string)
   (handler :initarg :handler :reader tool-handler :type function)
   (validator :initarg :validator :reader tool-validator :type (or function null))))

(defmethod find-tool ((registry tool-registry) (name string))
  (gethash name (registry-tools registry)))

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
            (tool-validation-error (e) (values nil (format nil "Validation error: ~A" e)))
            (error (e)
              (values nil (format nil "Tool ~A error: ~A" name e)))))))

(format t "Loaded~%")
