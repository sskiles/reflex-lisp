;;;; harness/stage-0/nvidia-stage5.lisp
;; Provider class and final integration

(in-package #:harness.stage-0.nvidia)

(defclass nvidia-provider (provider)
  ()
  (:default-initargs
   :name "NVIDIA"))

(defmethod provider-call ((p nvidia-provider) messages &key model temperature max-tokens tools tool-choice)
  (let ((config (provider-config p)))
    (call-nvidia-chat messages
                      :model (or model (provider-config-default-model config))
                      :temperature (or temperature (provider-config-default-temperature config))
                      :max-tokens (or max-tokens (provider-config-default-max-tokens config))
                      :tools tools
                      :tool-choice (or tool-choice :auto))))

(defmethod provider-list-models ((p nvidia-provider))
  (list-available-models))

(defmethod provider-model-context-size ((p nvidia-provider) model)
  (model-context-size model))

(defmethod provider-refresh-models ((p nvidia-provider))
  (refresh-model-list))

(defun make-nvidia-provider (&key config)
  "Create a NVIDIA provider instance."
  (make-instance 'nvidia-provider
                 :config (or config (make-provider-config
                                     :name "nvidia"
                                     :api-key (uiop:getenv "NVIDIA_API_KEY")
                                     :base-url "https://integrate.api.nvidia.com/v1"
                                     :default-model "openai/gpt-oss-20b"
                                     :context-sizes (let ((ht (make-hash-table :test 'equal)))
                                                      (setf (gethash "openai/gpt-oss-20b" ht) 131072
                                                            (gethash "meta/llama-3.1-8b-instruct" ht) 131072
                                                            (gethash "minimaxai/minimax-m3" ht) 32768)
                                                      ht)))))

(format t "~&[harness.stage-0.nvidia-stage5] Loaded~%")