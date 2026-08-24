(load "tools/protocol.lisp")
(load "tools/registry.lisp")
(load "stage-0/protocol.lisp")
(load "stage-1/conditions.lisp")
(load "stage-1/protocol.lisp")
(load "stage-3/protocol.lisp")
(load "stage-4/tools.lisp")

(in-package #:harness.stage-4.tools)

(format t "fboundp register-standard-tools: ~A~%" (fboundp 'register-standard-tools))