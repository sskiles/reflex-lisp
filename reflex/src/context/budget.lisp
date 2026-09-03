(in-package #:reflex.context)

(defstruct (zone-budget (:constructor make-zone-budget))
  (verbatim-pct 35)
  (caveman-pct  25)
  (recall-pct   20))

(defun %ctx-default-zone-budget ()
  (make-zone-budget))

(defparameter *default-zone-budget* (%ctx-default-zone-budget)
  "Default per-zone share of the context window.
Sums to less than 100; the remainder is reserved for system prompt + query.")

(defun %ctx-zone-allocations (total-tokens budget)
  "Return a plist (:VERBATIM n :CAVEMAN n :RECALL n) summing to ~80% of TOTAL."
  (let* ((v (floor (* total-tokens (zone-budget-verbatim-pct budget)) 100))
         (c (floor (* total-tokens (zone-budget-caveman-pct  budget)) 100))
         (r (floor (* total-tokens (zone-budget-recall-pct   budget)) 100)))
    (list :verbatim v :caveman c :recall r)))

(defun %ctx-tokens-of (text)
  "Estimate tokens for TEXT (string). Defaults to ~4 chars/token."
  (%ctx-estimate-tokens text))
