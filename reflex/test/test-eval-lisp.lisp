;;; Tests for the eval-lisp tool.

(in-package #:reflex-test)

(defun %check-eval-lisp (input expected)
  (let* ((result (reflex.tools:execute-tool-call "eval-lisp"
                                                (list (cons "expression" input))))
         (ok (and (stringp result)
                  (or (string= result expected)
                      (search expected result)))))
    (check ok "eval-lisp(~S): expected ~S, got ~S" input expected result)))

(defun test-eval-lisp ()
  ;; Basic arithmetic.
  (%check-eval-lisp "(+ 1 2)" "3")
  (%check-eval-lisp "(* 6 7)" "42")
  ;; String return.
  (%check-eval-lisp "\"hello\"" "hello")
  ;; Symbol return.
  (%check-eval-lisp "'foo" "FOO")
  ;; List return.
  (%check-eval-lisp "(list 1 2 3)" "(1 2 3)")
  ;; Error handling: malformed expression should not crash the tool.
  (%check-eval-lisp "(+ 1" "ERROR:")
  ;; Side effect: defining a function and then calling it.  Use a unique
  ;; name to avoid colliding with SB-ALIEN:DOUBLE.
  (%check-eval-lisp "(defun reflex-test::dbl (x) (* 2 x))" "REFL")
  (%check-eval-lisp "(reflex-test::dbl 21)" "42")
  ;; Inspect reflex:*default-model*.
  (%check-eval-lisp "reflex:*default-model*" "openai/gpt-oss-20b")
  (format t "~&REFLEX eval-lisp tests passed.~%")
  (finish-output))
