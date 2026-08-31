;;;; reflex.asd

(asdf:defsystem #:reflex
  :description "Minimal, self-modifying agent harness foundation."
  :author "Reflex contributors"
  :license "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on ("dexador" "cl-json" "reflex/tools")
  :components ((:file "src/package")
               (:file "src/api")
               (:file "src/reflex")))

(asdf:defsystem #:reflex/tools
  :description "Tool registry and dispatch for Reflex."
  :author "Reflex contributors"
  :license "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on ("dexador" "cl-json")
  :components ((:file "src/tools/package")
               (:file "src/tools/registry")
               (:file "src/tools/define-tool")
               (:file "src/tools/eval-lisp")
               (:file "src/tools/read-file")
               (:file "src/tools/write-file")
               (:file "src/tools/edit-file")
               (:file "src/tools/bash")))

(asdf:defsystem #:reflex/test
  :description "Self-contained smoke tests for Reflex."
  :author "Reflex contributors"
  :license "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on ("reflex")
  :components ((:file "test/test-api")
               (:file "test/test-eval-lisp")
               (:file "test/test-file-tools"))
  :perform (asdf:test-op (operation component)
                         (declare (ignore operation component))
                         (uiop:symbol-call :reflex-test :run-tests)))
