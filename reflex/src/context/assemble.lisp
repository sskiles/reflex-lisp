(in-package #:reflex.context)

(defun %ctx-join-zones (zones)
  "Concatenate a list of ZONE-RESULTs into a single labeled transcript."
  (format nil "~{~A~^~%~}"
          (mapcan (lambda (zr)
                    (cons (format nil "## ~A" (zone-result-label zr))
                          (zone-result-lines zr)))
                  zones)))

(defun context-assemble-prompt (query
                                &key
                                  (session-id "default")
                                  (total-budget 8000)
                                  (verbatim-turns 4)
                                  (caveman-turns 20)
                                  (recall-k 8)
                                  (zone-budget *default-zone-budget*)
                                  (embed-fn *embed-fn*)
                                  (report-stream *standard-output*))
  "Assemble a tiered context window for QUERY.
Zones (A verbatim → B caveman → C recall) are built in order, each capped
to its share of TOTAL-BUDGET.  Returns a string suitable for prepending to
the current user message.

If REPORT-STREAM is non-nil, prints a per-zone feedback report (line count,
token use, budget cap, skipped rows, recall hit scores) to that stream.
Pass NIL to suppress the report."
  (let* ((alloc (%ctx-zone-allocations total-budget zone-budget))
         (vb (getf alloc :verbatim))
         (cb (getf alloc :caveman))
         (rb (getf alloc :recall))
         (results '()))
    ;; Zone A — verbatim recent
    (let ((zr (%ctx-zone-verbatim session-id verbatim-turns :token-budget vb)))
      (push zr results))
    ;; Zone B — caveman mid-recent
    (let* ((used-a (zone-result-used (car results)))
           (skip  (max 0 (- used-a (* vb 1))))
           (zr (%ctx-zone-caveman session-id verbatim-turns caveman-turns
                                  :token-budget (max 0 cb))))
      (declare (ignore skip))
      (push zr results))
    ;; Zone C — semantic recall (skip if no embedder)
    (let ((zr
            (if embed-fn
                (handler-case
                    (%ctx-zone-recall (funcall embed-fn query)
                                      :k recall-k
                                      :session-id nil
                                      :token-budget (max 0 rb))
                  (error (e)
                    (make-zone-result
                     :label   "Relevant history (recall)"
                     :lines   (list (format nil "[recall skipped: ~A]" e))
                     :used    0
                     :budget  rb)))
                (make-zone-result
                 :label   "Relevant history (recall)"
                 :lines   '("[recall skipped: no *embed-fn* configured]")
                 :used    0
                 :budget  rb))))
      (push zr results))
    (setf results (nreverse results))
    (when report-stream
      (format report-stream "~A" (%ctx-format-report results total-budget)))
    (%ctx-join-zones results)))
