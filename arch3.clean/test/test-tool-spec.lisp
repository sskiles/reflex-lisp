(load "tools/protocol.lisp")
(load "tools/registry.lisp")
(load "stage-0/protocol.lisp")
(load "stage-1/conditions.lisp")
(load "stage-1/protocol.lisp")

(in-package #:harness.stage-1.protocol)

(format t "Testing make-tool-spec directly:~%")
(let ((spec (make-tool-spec "eval-lisp" "desc" (make-hash-table) (lambda (x) x) nil)))
  (format t "Type: ~A~%" (type-of spec))
  (format t "Name: ~A~%" (tool-spec-name spec)))

(format t "~%Testing get-lisp-eval-tool-spec:~%")
(let ((spec (get-lisp-eval-tool-spec)))
  (format t "Type: ~A~%" (type-of spec))
  (when (typep spec 'tool-spec)
    (format t "Name: ~A~%" (tool-spec-name spec))))