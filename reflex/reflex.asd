;;;; reflex.asd

(asdf:defsystem #:reflex
  :description "Minimal, self-modifying agent harness foundation."
  :author "Reflex contributors"
  :license "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on ("dexador" "cl-json" "sqlite" "ironclad" "babel" "ieee-floats"
               "reflex/tools" "reflex/context")
  :components ((:file "src/package")
               (:file "src/api")
               (:file "src/reflex")))

(asdf:defsystem #:reflex/context
  :description "Persistent context storage with embeddings and caveman projection."
  :author "Reflex contributors"
  :license "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on ("sqlite" "ironclad" "babel" "ieee-floats")
  :components ((:file "src/context/package")
               (:file "src/context/config")
               (:file "src/context/connect")
               (:file "src/context/crypto")
               (:file "src/context/caveman")
               (:file "src/context/embedding")
               (:file "src/context/api-add")
               (:file "src/context/api-caveman")
               (:file "src/context/api-replay")
               (:file "src/context/api-search")))

(asdf:defsystem #:reflex/tools
  :description "Tool registry and dispatch for Reflex."
  :author "Reflex contributors"
  :license "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on ("dexador" "cl-json" "sqlite")
  :components ((:file "src/tools/package")
               (:file "src/tools/registry")
               (:file "src/tools/define-tool")
               (:file "src/tools/eval-lisp")
               (:file "src/tools/read-file")
               (:file "src/tools/write-file")
               (:file "src/tools/edit-file")
               (:file "src/tools/bash")
               (:file "src/tools/sqlite-sql")))

(asdf:defsystem #:reflex/test
  :description "Self-contained smoke tests for Reflex."
  :author "Reflex contributors"
  :license "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on ("reflex")
  :components ((:file "test/test-api")
               (:file "test/test-eval-lisp")
               (:file "test/test-file-tools")
               (:file "test/test-sqlite"))
  :perform (asdf:test-op (operation component)
                         (declare (ignore operation component))
                         (uiop:symbol-call :reflex-test :run-tests)))
