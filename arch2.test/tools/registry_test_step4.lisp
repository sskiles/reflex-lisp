;;;; Test step 4 - handler-case with json:

(defpackage #:harness.tools.registry.testhandler
  (:use #:cl #:harness.tools.protocol))
(in-package #:harness.tools.registry.testhandler)

(defun test-fn ()
  (handler-case
      (json:encode-json-to-string "test")
    (error (e) (format nil "Error: ~A" e))))

(format t "Loaded~%")
