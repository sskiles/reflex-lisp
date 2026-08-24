(load "tools/protocol.lisp")
(load "tools/registry.lisp")
(load "stage-0/protocol.lisp")
(load "stage-1/conditions.lisp")
(load "stage-1/protocol.lisp")

(in-package #:harness.stage-1.protocol)

(format t "fboundp get-lisp-eval-tool-spec: ~A~%" (fboundp 'get-lisp-eval-tool-spec))
(format t "fboundp make-tool-spec: ~A~%" (fboundp 'make-tool-spec))