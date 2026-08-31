;;;; reflex.asd

(asdf:defsystem #:reflex
  :description "Minimal, self-modifying agent harness foundation."
  :author "Reflex contributors"
  :license "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on ("dexador" "cl-json")
  :components ((:file "src/package")
               (:file "src/api")
               (:file "src/reflex")))

(asdf:defsystem #:reflex/test
  :description "Self-contained smoke tests for Reflex."
  :author "Reflex contributors"
  :license "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on ("reflex")
  :components ((:file "test/test-api"))
  :perform (asdf:test-op (operation component)
                         (declare (ignore operation component))
                         (uiop:symbol-call :reflex-test :run-tests)))
