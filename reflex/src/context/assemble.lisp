(in-package #:reflex.context)

(defun %ctx-join-zones (zones)
  "Concatenate a list of (label . lines) alists into a single labeled transcript."
  (format nil "~{~A~^~%~}"
          (mapcan (lambda (zone)
                    (let ((label (car zone))
                          (lines (cdr zone)))
                      (cons (format nil "## ~A" label) lines)))
                  zones)))

(defun context-assemble-prompt (query
                                &key
                                  (session-id "default")
                                  (total-budget 8000)
                                  (verbatim-turns 4)
                                  (caveman-turns 20)
                                  (recall-k 8)
                                  (zone-budget *default-zone-budget*)
                                  (embed-fn *embed-fn*))
  "Assemble a tiered context window for QUERY.
Zones (A verbatim → B caveman → C recall) are built in order, each capped
to its share of TOTAL-BUDGET.  Returns a string suitable for prepending to
the current user message."
  (let* ((alloc (%ctx-zone-allocations total-budget zone-budget))
         (vb (getf alloc :verbatim))
         (cb (getf alloc :caveman))
         (rb (getf alloc :recall))
         (zones '()))
    ;; Zone A — verbatim recent
    (multiple-value-bind (lines used)
        (%ctx-zone-verbatim session-id verbatim-turns :token-budget vb)
      (declare (ignore used))
      (push (cons "Recent (verbatim)" lines) zones))
    ;; Zone B — caveman mid-recent
    (multiple-value-bind (lines used)
        (%ctx-zone-caveman session-id verbatim-turns caveman-turns
                           :token-budget (max 0 cb))
      (declare (ignore used))
      (push (cons "Earlier (caveman)" lines) zones))
    ;; Zone C — semantic recall (skip if no embedder)
    (if embed-fn
        (handler-case
            (let ((query-vec (funcall embed-fn query)))
              (multiple-value-bind (lines used)
                  (%ctx-zone-recall query-vec
                                    :k recall-k
                                    :session-id nil
                                    :token-budget (max 0 rb))
                (declare (ignore used))
                (push (cons "Relevant history (recall)" lines) zones)))
          (error (e)
            (push (cons "Relevant history (recall)"
                        (list (format nil "[recall skipped: ~A]" e)))
                  zones)))
        (push (cons "Relevant history (recall)"
                    '("[recall skipped: no *embed-fn* configured]"))
              zones))
    (%ctx-join-zones (nreverse zones))))
