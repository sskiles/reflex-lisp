(in-package #:reflex.context)

(defun %ctx-pack-f32-embedding (vector)
  "Pack a list/number-vector of floats into a little-endian float32 BLOB."
  (let* ((dim (length vector))
         (bytes (make-array (* dim 4) :element-type '(unsigned-byte 8))))
    (loop for v across vector
          for i from 0
          for off = (* i 4)
          do (let ((bits (ieee-floats:encode-float32 v)))
               (setf (aref bytes (+ off 0)) (ldb (byte 8  0) bits))
               (setf (aref bytes (+ off 1)) (ldb (byte 8  8) bits))
               (setf (aref bytes (+ off 2)) (ldb (byte 8 16) bits))
               (setf (aref bytes (+ off 3)) (ldb (byte 8 24) bits))))
    bytes))

(defun %ctx-unpack-f32-embedding (blob dim)
  "Decode a BLOB produced by %CTX-PACK-F32-EMBEDDING into a list of floats."
  (unless (and blob dim)
    (return-from %ctx-unpack-f32-embedding nil))
  (let* ((expected (* dim 4))
         (actual (length blob)))
    (when (/= actual expected)
      (error "Embedding byte length ~A does not match dim=~A (~A bytes)~%"
             actual dim expected))
    (loop for i from 0 below dim
          for off = (* i 4)
          collect (ieee-floats:decode-float32
                    (logior (ash (aref blob (+ off 3)) 24)
                            (ash (aref blob (+ off 2)) 16)
                            (ash (aref blob (+ off 1))  8)
                            (aref blob (+ off 0)))))))

(defun %ctx-l2-norm (vec)
  "Euclidean L2 norm of VEC (list or vector)."
  (let ((list (if (listp vec) vec (coerce vec 'list))))
    (sqrt (reduce #'+ (mapcar (lambda (x) (* x x)) list)))))

(defun %ctx-cosine (a b)
  "Cosine similarity between two vectors (lists or vectors)."
  (let* ((la (if (listp a) a (coerce a 'list)))
         (lb (if (listp b) b (coerce b 'list)))
         (na (%ctx-l2-norm a))
         (nb (%ctx-l2-norm b))
         (dot 0.0d0))
    (loop for x in la
          for y in lb
          do (incf dot (* x y)))
    (if (or (zerop na) (zerop nb))
        0.0d0
        (/ dot (* na nb)))))
