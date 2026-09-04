(in-package #:reflex.context)

(defstruct zone-result
  "Result of building one zone of the context window.
  EXTRA holds zone-specific metadata: for zone C, ((hit . score) ...)
  pairs so the caller can see the ranking and similarity distribution."
  (label    ""    :type string)
  (lines    '()   :type list)
  (used     0     :type integer)
  (budget   0     :type integer)
  (skipped  0     :type integer)
  (extra    '()   :type list))

(defun %ctx-zone-format (zr)
  "One-line summary of ZR for the feedback report."
  (let* ((n (length (zone-result-lines zr)))
         (extra-count (length (zone-result-extra zr)))
         (skipped (zone-result-skipped zr))
         (parts (list (format nil "~D line~:P, ~D/~D tok"
                              n (zone-result-used zr) (zone-result-budget zr)))))
    (when (plusp skipped)
      (push (format nil "~D skipped" skipped) parts))
    (when (plusp extra-count)
      (push (format nil "~D hit~:P" extra-count) parts))
    (format nil "[~A] ~{~A~^; ~}"
            (zone-result-label zr) parts)))

(defun %ctx-zone-detail (zr)
  "Multi-line detail block for ZR.  Zone C shows the hit ranking;
  other zones show nothing extra."
  (cond
    ((string= (zone-result-label zr) "Relevant history (recall)")
     (format nil "~{~A~%~}"
             (mapcar (lambda (pair)
                       (destructuring-bind (hit . score) pair
                         (format nil "      ~A  score=~,3F"
                                 (or (getf hit :id) "?")
                                 (float score))))
                     (zone-result-extra zr))))
    (t "")))
