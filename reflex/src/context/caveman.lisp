(in-package #:reflex.context)

(defun %ctx-truncate (text limit)
  "Trim TEXT and truncate to LIMIT characters, appending ~ when cut."
  (let ((s (string-trim '(#\Space #\Tab #\Newline) text)))
    (if (> (length s) limit)
        (concatenate 'string (subseq s 0 (- limit 1)) "~")
        s)))

(defun %ctx-caveman-from-row (kind content)
  "Project a (KIND, CONTENT) pair into a compact caveman string."
  (let ((prefix (case kind
                  ((user) "U")
                  ((assistant) "A")
                  ((tool) "R")
                  ((decision) "D")
                  ((question) "Q")
                  ((file) "F")
                  (otherwise "T"))))
    (format nil "~A=~A" prefix (%ctx-truncate (or content "") 80))))
