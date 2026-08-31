;;;; harness/stage-1/conditions.lisp - Error conditions for eval loop

(defpackage #:harness.stage-1.conditions
  (:use #:cl)
  (:export #:eval-loop-error
           #:eval-loop-error-message
           #:max-iterations-exceeded
           #:max-iterations-count))

(in-package #:harness.stage-1.conditions)

(define-condition eval-loop-error (error)
  ((message :initarg :message :reader eval-loop-error-message))
  (:report (lambda (c s) (format s "Eval loop error: ~A" (eval-loop-error-message c)))))

(define-condition max-iterations-exceeded (eval-loop-error)
  ((iterations :initarg :iterations :reader max-iterations-count))
  (:report (lambda (c s) (format s "Max iterations (~A) exceeded" (max-iterations-count c)))))