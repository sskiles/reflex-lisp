;;;; harness/build.lisp - Compile all stages

(require :asdf)
(let ((setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file setup)
    (load setup)))

(ql:quickload '(:dexador :cl-json :cl-ppcre :bordeaux-threads :babel :uiop :str :swank :sqlite) :silent t)

;; Compile and load in dependency order
(load (compile-file "tools/protocol.lisp"))
(load (compile-file "tools/registry.lisp"))

(load (compile-file "stage-0/protocol.lisp"))
(load (compile-file "stage-0/db.lisp"))
(load (compile-file "stage-0/nvidia-stage1.lisp"))
(load (compile-file "stage-0/nvidia-stage2.lisp"))
(load (compile-file "stage-0/nvidia-stage3.lisp"))
(load (compile-file "stage-0/nvidia-stage4.lisp"))
(load (compile-file "stage-0/nvidia-stage5.lisp"))
(load (compile-file "stage-0/async-processor.lisp"))

(load (compile-file "stage-1/conditions.lisp"))
(load (compile-file "stage-1/protocol.lisp"))
(load (compile-file "stage-1/eval-loop.lisp"))

(load (compile-file "stage-3/protocol.lisp"))

(load (compile-file "stage-4/tools.lisp"))

(load (compile-file "core.lisp"))

(load (compile-file "test.lisp"))

(format t "~&=== All files compiled and loaded successfully ===~%")