;;;; Test loader for staged nvidia.lisp

;; Load stages in order
(load "stage-0/nvidia-stage1.lisp")
(load "stage-0/nvidia-stage2.lisp")
(load "stage-0/nvidia-stage3.lisp")
(load "stage-0/nvidia-stage4.lisp")
(load "stage-0/nvidia-stage5.lisp")

(format t "~&All stages loaded successfully~%")