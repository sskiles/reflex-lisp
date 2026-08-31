;;;; harness/stage-0/nvidia-stage1.lisp
;; Package definition and variables

(defpackage #:harness.stage-0.nvidia
  (:use #:cl #:harness.stage-0.protocol #:harness.tools.protocol)
  (:export #:*nvidia-api-key*
           #:*nvidia-base-url*
           #:*default-model*
           #:*default-temperature*
           #:*default-max-tokens*
           #:*request-timeout*
           #:model-context-size
           #:*model-context-sizes*
           #:make-nvidia-provider
           #:nvidia-provider
           #:call-nvidia-chat
           #:set-default-model
           #:list-available-models
           #:fetch-models-from-nvidia
           #:refresh-model-list
           #:compute-context-limit
           #:update-context-limit
           #:show-models
           #:select-model
           #:json-get
           #:set-context-percentage
           #:set-manual-max-tokens
           #:reset-manual-max-tokens))

(in-package #:harness.stage-0.nvidia)

(defvar *nvidia-api-key* (uiop:getenv "NVIDIA_API_KEY")
  "NVIDIA API key from environment.")

(defvar *nvidia-base-url* "https://integrate.api.nvidia.com/v1"
  "NVIDIA API base URL (OpenAI-compatible).")

(defvar *default-model* "openai/gpt-oss-20b"
  "Default model. Can be overridden per-request.")

(defvar *default-temperature* 0.7
  "Default temperature for responses.")

(defvar *default-max-tokens* 8192
  "Default max tokens for responses.")

(defvar *request-timeout* 120
  "Request timeout in seconds.")

(defvar *model-context-sizes*
  (let ((ht (make-hash-table :test #'equal)))
    (setf (gethash "openai/gpt-oss-20b" ht) 131072
          (gethash "meta/llama-3.1-8b-instruct" ht) 131072
          (gethash "minimaxai/minimax-m3" ht) 32768)
    ht)
  "Hash table mapping model ID strings to their context window size (in tokens).")

(format t "~&[harness.stage-0.nvidia-stage1] Loaded~%")