;;; Package definition for the tool subsystem.

(defpackage #:reflex.tools
  (:use #:cl)
  (:export
   #:tool
   #:tool-name
   #:tool-function
   #:tool-description
   #:tool-parameters
   #:define-tool
   #:register-tool
   #:find-tool
   #:list-tools
   #:execute-tool-call
   #:tool-schemas-for-llm
   #:*tools*))
