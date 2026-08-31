;;;; harness/loader.lisp - Load all stages in order

;; Quicklisp bootstrap
(require :asdf)
(let ((setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file setup)
    (load setup)))

;; Load core dependencies
(ql:quickload '(:dexador :cl-json :cl-ppcre :bordeaux-threads :babel :uiop :str :swank :sqlite) :silent t)

;; Load harness stages in dependency order (relative to harness directory)
(load "tools/protocol.lisp")
(load "tools/registry.lisp")

(load "stage-0/protocol.lisp")
(load "stage-0/db.lisp")
(load "stage-0/nvidia-stage1.lisp")
(load "stage-0/nvidia-stage2.lisp")
(load "stage-0/nvidia-stage3.lisp")
(load "stage-0/nvidia-stage4.lisp")
(load "stage-0/nvidia-stage5.lisp")
(load "stage-0/async-processor.lisp")

(load "stage-1/conditions.lisp")
(load "stage-1/protocol.lisp")
(load "stage-1/eval-loop.lisp")

(load "stage-3/protocol.lisp")

(load "stage-4/tools.lisp")

(load "core.lisp")
(load "test/test.lisp")

(load "post-restore.lisp")

(in-package #:harness.core)

;; Crash behavior - simple error handling
(setq sb-ext:*invoke-debugger-hook*
      (lambda (condition hook)
        (declare (ignore hook))
        (format t "~&;;; CRASH: ~A~%" condition)
        (format t "~&;;; Dropping into debugger.~%")
        nil))

;; Auto-start if run as script
(handler-case
    (progn
      (start)
      (query-loop))
  (error (c)
    (format t "~&;;; HARNESS ERROR: ~A~%" c)
    (format t "~&;;; Dropping into interactive REPL...~%")
    (loop (format t "~&[repl] ")
          (finish-output)
          (let ((form (read nil nil nil)))
            (when (null form) (return))
            (handler-case (print (eval form))
              (error (e) (format t ";;; REPL error: ~A~%" e)))))))
