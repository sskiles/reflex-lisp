;;;; harness/tools/registry.lisp - Default tool registry implementation (from original)

(defpackage #:harness.tools.registry
  (:use #:cl #:harness.tools.protocol)
  (:export #:make-tool-registry
           #:register-tool-fn
           #:default-registry
           #:json-encode
           #:json-decode
           #:tool-to-schema
           #:list-tools
           #:get-tool-schemas
           #:execute-tool-call
           #:tool-spec
           #:make-tool-spec
           #:tool-name
           #:tool-description
           #:tool-parameters
           #:tool-handler
           #:tool-validator
           #:tool-registry
           #:registry-tools
           #:register-tool
           #:unregister-tool
           #:find-tool
           #:execute-tool
           #:list-tool-specs
           #:tool-schemas-for-llm
           #:tool-error
           #:tool-not-found-error
           #:tool-validation-error
           #:tool-execution-error))

(in-package #:harness.tools.registry)

(defvar *tools* (make-hash-table :test 'equal))

(defstruct tool-info
  name description fn params validator)

(defun tool-to-schema (tool-name tool-description tool-params)
  (let ((params-ht (cond
                     ((typep tool-params 'hash-table) tool-params)
                     ((listp tool-params) (plist-to-hash tool-params))
                     (t (make-hash-table)))))
    (let ((res (make-hash-table :test 'equal)))
      (setf (gethash "type" res) "function")
      (let ((fn (make-hash-table :test 'equal)))
        (setf (gethash "name" fn) tool-name)
        (setf (gethash "description" fn) tool-description)
        (setf (gethash "parameters" fn) params-ht)
        (setf (gethash "function" res) fn))
      res)))

(defun register-tool-fn (name description fn params validator)
  (setf (gethash name *tools*)
        (make-tool-info :name name :description description
                        :fn fn :params params :validator validator))
  name)

(defmethod register-tool ((registry tool-registry) (spec tool-spec))
  (setf (gethash (tool-name spec) (registry-tools registry)) spec)
  (register-tool-fn (tool-name spec)
                    (tool-description spec)
                    (tool-handler spec)
                    (tool-parameters spec)
                    (tool-validator spec))
  spec)

(defmethod unregister-tool ((registry tool-registry) (name string))
  (remhash name *tools*)
  (remhash name (registry-tools registry)))

(defmethod find-tool ((registry tool-registry) (name string))
  (or (gethash name (registry-tools registry))
      (let ((info (gethash name *tools*)))
        (when info
          (make-tool-spec (tool-info-name info)
                          (tool-info-description info)
                          (tool-info-params info)
                          (tool-info-fn info)
                          (tool-info-validator info))))))

(defmethod list-tool-specs ((registry tool-registry))
  (loop for v being the hash-values of (registry-tools registry)
        collect v))

(defun get-tool-schemas ()
  (loop for v being the hash-values of *tools*
        collect (tool-to-schema
                 (tool-info-name v)
                 (tool-info-description v)
                 (tool-info-params v))))

(defmethod tool-schemas-for-llm ((registry tool-registry))
  (let ((specs (list-tool-specs registry)))
    (if specs
        (loop for spec in specs
              collect (tool-to-schema (tool-name spec)
                                      (tool-description spec)
                                      (tool-parameters spec)))
        (get-tool-schemas))))


(defmethod execute-tool ((registry tool-registry) (name string) args)
  (let ((spec (find-tool registry name)))
    (if (null spec)
        (values nil (format nil "Tool not found: ~A" name))
        (handler-case
            (progn
              (when (tool-validator spec)
                (funcall (tool-validator spec) args))
              (multiple-value-bind (result err) (funcall (tool-handler spec) args)
                (if err
                    (values nil err)
                    (values (if (stringp result) result (json:encode-json-to-string result)) nil))))
          (error (e)
            (values nil (format nil "Tool ~A error: ~A" name e)))))))

(defun list-tools (&optional registry)
  (let ((ht (if (and registry (typep registry 'tool-registry))
                (registry-tools registry)
                *tools*)))
    (format t "~&=== Registered Tools (~A) ===~%" (hash-table-count ht))
    (maphash (lambda (k v)
               (declare (ignore k))
               (if (typep v 'tool-spec)
                   (format t "  ~A: ~A~%" (tool-name v) (tool-description v))
                   (format t "  ~A: ~A~%" (tool-info-name v) (tool-info-description v))))
             ht)))

(defun format-error (e)
  (format nil "~A: ~A" (type-of e) e))


(defun execute-tool-call (tool-call)
  (let* ((name (tool-call-name tool-call))
         (raw-args (tool-call-arguments tool-call))
         (args (if (listp raw-args) (plist-to-hash raw-args) raw-args))
         (def-reg-sym (find-symbol "*DEFAULT-REGISTRY*" "HARNESS.STAGE-4.TOOLS"))
         (def-reg (when (and def-reg-sym (boundp def-reg-sym)) (symbol-value def-reg-sym))))
    (if (and def-reg (typep def-reg 'tool-registry) (find-tool def-reg name))
        (execute-tool def-reg name args)
        (let ((info (gethash name *tools*)))
          (if (null info)
              (values nil (format nil "Unknown tool: ~A" name))
              (handler-case
                  (progn
                    (when (tool-info-validator info)
                      (funcall (tool-info-validator info) args))
                    (let ((result (funcall (tool-info-fn info) args)))
                      (values (if (stringp result) result
                                  (json:encode-json-to-string result))
                              nil)))
                (error (e)
                   (values nil (format nil "Tool ~A error: ~A" name (format-error e))))))))))

(format t "~&Tool registry loaded~%")