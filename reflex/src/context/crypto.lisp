(in-package #:reflex.context)

(defun %ctx-sha256 (string)
  "Return the lowercase hex SHA-256 digest of STRING."
  (let* ((octets (babel:string-to-octets string :encoding :utf-8))
         (digest (ironclad:digest-sequence :sha256 octets)))
    (ironclad:byte-array-to-hex-string digest)))

(defun %ctx-estimate-tokens (text)
  "Rough token estimate: 4 chars/token, minimum 1."
  (max 1 (floor (length text) 4)))
