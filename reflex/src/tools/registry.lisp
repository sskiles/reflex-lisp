;;; Tool registry: a global alist of tool-name -> tool object.

(in-package #:reflex.tools)

(defvar *tools* nil
  "Global alist mapping tool name (string) to a tool object.
Persisted across save-image because it lives in a package-level defvar.")

(defclass tool ()
  ((name        :initarg :name        :reader tool-name
                :type string
                :documentation "Tool name as exposed to the LLM.")
   (description :initarg :description :reader tool-description
                :type string
                :documentation "Human-readable description sent to the LLM.")
   (parameters  :initarg :parameters  :reader tool-parameters
                :type list
                :documentation "JSON-schema-style parameter list (alist).")
   (function    :initarg :function    :reader tool-function
                :type (or symbol function)
                :documentation "Function called with a JSON-decoded argument alist."))
  (:documentation "A callable tool that the LLM may invoke."))

(defun register-tool (tool)
  "Register TOOL in *TOOLS*, replacing any existing tool with the same name."
  (let* ((name (tool-name tool))
         (existing (assoc name *tools* :test #'string=)))
    (if existing
        (setf (cdr existing) tool)
        (push (cons name tool) *tools*)))
  tool)

(defun find-tool (name)
  "Return the tool named NAME (string), or NIL."
  (cdr (assoc name *tools* :test #'string=)))

(defun list-tools ()
  "Return a fresh list of all registered tools."
  (mapcar #'cdr *tools*))

(defun tool-schemas-for-llm ()
  "Return the JSON `tools` payload describing every registered tool."
  (mapcar (lambda (tool)
            (list (cons "type" "function")
                  (cons "function"
                        (list (cons "name"        (tool-name tool))
                              (cons "description" (tool-description tool))
                              (cons "parameters"  (tool-parameters tool))))))
          (list-tools)))

(defun execute-tool-call (name arguments)
  "Dispatch a tool call. NAME is the tool name (string). ARGUMENTS is the
decoded JSON alist of parameter values. Returns a string describing the result
or the error."
  (let ((tool (find-tool name)))
    (cond
      ((null tool)
       (format nil "ERROR: unknown tool ~S" name))
      (t
       (handler-case
           (let ((result (funcall (tool-function tool) arguments)))
             (cond
               ((null result) "")
               ((stringp result) result)
               (t (format nil "~S" result))))
         (error (e)
           (format nil "ERROR: ~A" e)))))))
