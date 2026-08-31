;;;; Test just referencing protocol classes

(defpackage #:harness.tools.registry.test4
  (:use #:cl #:harness.tools.protocol))
(in-package #:harness.tools.registry.test4)

;; Just reference the class names
(defmethod foo ((x tool-registry))
  (format t "tool-registry method~%"))

(defmethod bar ((x tool-spec))
  (format t "tool-spec method~%"))

(format t "Loaded~%")
