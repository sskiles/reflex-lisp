;;;; harness/tools/protocol.lisp - Tool protocol (Stage 0.5, cross-cutting)

(defpackage #:harness.tools.protocol
  (:use #:cl)
  (:export
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
   #:plist-to-hash
   #:hash-to-plist
   #:tool-error
   #:tool-not-found-error
   #:tool-validation-error
   #:tool-execution-error
   #:tool-to-schema
   #:tool-call
   #:make-tool-call
   #:tool-call-id
   #:tool-call-name
   #:tool-call-arguments))

(in-package #:harness.tools.protocol)

;;; --- Tool Call Structure ---------------------------------------------------

(defstruct tool-call
  id
  name
  arguments)

;;; --- Helper Functions (re-exported) ----------------------------------------

(defun plist-to-hash (plist &optional (test 'equal))
  "Convert a plist OR alist into a hash-table with string keys."
  (if (not (listp plist))
      plist
      (let ((ht (make-hash-table :test test)))
        (cond
          ;; Alist: list of cons cells ((k . v) ...) from cl-json decoding
          ((and plist (consp (first plist)))
           (dolist (pair plist)
             (when (consp pair)
               (let* ((k (car pair))
                      (v (cdr pair))
                      (key-str (cond
                                 ((stringp k) (string-downcase k))
                                 ((symbolp k) (string-downcase (symbol-name k)))
                                 (t (format nil "~A" k)))))
                 (setf (gethash key-str ht)
                       (if (and (listp v) (consp (first v)))
                           (plist-to-hash v test)
                           v))))))
          ;; Plist: flat list (k v k v ...) from tool parameter schema definitions
          (t
           (loop for (k v) on plist by #'cddr
                 do (setf (gethash k ht)
                          (cond
                            ((and (stringp k) (string= k "properties") (listp v))
                             (let ((props-ht (make-hash-table :test test)))
                               (loop for (pk pv) on v by #'cddr
                                     do (setf (gethash pk props-ht)
                                              (plist-to-hash pv test)))
                               props-ht))
                            (t v))))))
        ht)))

(defun hash-to-plist (ht)
  "Convert hash-table to plist."
  (loop for k being the hash-keys of ht
        using (hash-value v)
        append (list k v)))

;;; --- Tool Spec -------------------------------------------------------------

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defclass tool-spec ()
    ((name :initarg :name :reader tool-name :type string
           :documentation "Unique tool name, e.g. \"bash\", \"read-file\"")
     (description :initarg :description :reader tool-description :type string
                  :documentation "Human-readable description for LLM")
     (parameters :initarg :parameters :reader tool-parameters :type hash-table
                 :documentation "JSON Schema for tool parameters (hash-table)")
     (handler :initarg :handler :reader tool-handler :type function
              :documentation "Function (args-hash-table) -> (values result-string error-string)")
     (validator :initarg :validator :reader tool-validator :type (or function null)
                :documentation "Optional function (args) -> (values t error-string)"))
    (:documentation "Immutable tool specification."))

  (defun make-tool-spec (name description parameters handler &optional validator)
    "Convenience constructor."
    (make-instance 'tool-spec
                   :name name
                   :description description
                   :parameters parameters
                   :handler handler
                   :validator validator)))

;;; --- Tool Errors -----------------------------------------------------------

(define-condition tool-error (error)
  ((tool-name :initarg :tool-name :reader tool-error-name))
  (:report (lambda (c s) (format s "Tool error in ~A: ~A" (tool-error-name c) (slot-value c 'message)))))

(define-condition tool-not-found-error (tool-error)
  ()
  (:report (lambda (c s) (format s "Tool not found: ~A" (tool-error-name c)))))

(define-condition tool-validation-error (tool-error)
  ((reason :initarg :reason :reader validation-error-reason))
  (:report (lambda (c s) (format s "Tool validation error: ~A" (validation-error-reason c)))))

(define-condition tool-execution-error (tool-error)
  ()
  (:report (lambda (c s) (format s "Tool execution error: ~A" (slot-value c 'message)))))

;;; --- Tool Registry Protocol ------------------------------------------------

(defclass tool-registry ()
  ((tools :initform (make-hash-table :test 'equal) :accessor registry-tools
          :documentation "name -> tool-spec"))
  (:documentation "Tool registry. Extend for custom lookup/dispatch."))

(defgeneric register-tool (registry spec)
  (:documentation "Register a tool-spec. Returns the spec."))

(defgeneric unregister-tool (registry name)
  (:documentation "Remove tool by name. Returns T if removed."))

(defgeneric find-tool (registry name)
  (:documentation "Return tool-spec or NIL."))

(defgeneric execute-tool (registry name args)
  (:documentation "Look up tool, validate args, call handler.
Returns (values result-string error-string).
Errors signaled as tool-* conditions."))

(defgeneric list-tool-specs (registry)
  (:documentation "Return list of all tool-specs."))

;;; --- Tool Spec Accessors (for backward compatibility) ----------------------

(defgeneric tool-schemas-for-llm (registry)
  (:documentation "Return tool specs formatted for LLM function calling API."))

(format t "~&[harness.tools.protocol] Loaded~%")