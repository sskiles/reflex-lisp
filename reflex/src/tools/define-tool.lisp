;;; `define-tool` macro: registers a tool from a name, schema, and function.

(in-package #:reflex.tools)

(defmacro define-tool (name (&key description parameters function))
  "Define a tool from explicit pieces.
NAME is the tool name (string designator).
:DESCRIPTION is a string sent to the LLM.
:PARAMETERS is a JSON-schema-style parameter description (alist).
:FUNCTION is the function (or symbol naming a function) that takes the
decoded JSON argument alist as its single argument and returns a string
(or any value, formatted with ~S by execute-tool-call)."
  (let ((tool-name (string name)))
    `(register-tool
      (make-instance 'tool
                     :name ,tool-name
                     :description ,description
                     :parameters ,parameters
                     :function ,function))))
