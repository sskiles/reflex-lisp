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
           #:*model-context-sizes*))

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
    (setf (gethash "openai/gpt-oss-20b" ht) 8192
          (gethash "meta/llama-3.1-8b-instruct" ht) 8192
          (gethash "minimaxai/minimax-m3" ht) 32768)
    ht)
  "Hash table mapping model ID strings to their context window size (in tokens).")

(format t "~&[harness.stage-0.nvidia-stage1] Loaded~%");;;; harness/stage-0/nvidia-stage2.lisp
;; Helper functions

(in-package #:harness.stage-0.nvidia)

(defun json-get (obj key)
  "Get KEY from OBJ (alist or hash-table). KEY can be a string or symbol."
  (let* ((key-str (if (symbolp key) (symbol-name key) key))
         (single-dash (substitute #\- #\_ key-str))
         (parts (cl-ppcre:split "_" key-str))
         (double (format nil "~{~A~^--~}" parts))
         (candidates (remove-duplicates
                      (list key-str
                            (string-downcase key-str)
                            (string-upcase key-str)
                            single-dash
                            (string-upcase single-dash)
                            double
                            (string-upcase double)
                            (string-downcase double))
                      :test #'string=)))
    (cond
      ((hash-table-p obj)
       (dolist (k candidates)
         (multiple-value-bind (v present) (gethash k obj)
           (when present
             (return-from json-get v)))))
      ((consp obj)
       (dolist (k candidates)
         (let ((pair (assoc k obj :test #'string=)))
           (when pair
             (return-from json-get (cdr pair))))))
      (t nil))
    nil))

(defun ht (&rest pairs)
  "Build a hash-table from alternating key/value pairs."
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k h) v))
    h))

(defun list-available-models ()
  "Return a list of available models with their context sizes."
  (loop for model being the hash-keys of *model-context-sizes*
        using (hash-value size)
        collect (list :model model :context-size size)))

(defun infer-context-size (model-id &optional raw-model-obj)
  "Determine context window size for MODEL-ID using API fields, ID regex heuristics, or catalog defaults."
  (or (and raw-model-obj
           (or (let ((val (json-get raw-model-obj "context_length"))) (when (and (numberp val) (> val 0)) val))
               (let ((val (json-get raw-model-obj "context_size"))) (when (and (numberp val) (> val 0)) val))
               (let ((val (json-get raw-model-obj "max_input_tokens"))) (when (and (numberp val) (> val 0)) val))
               (let ((val (json-get raw-model-obj "max_context_length"))) (when (and (numberp val) (> val 0)) val))
               (let ((val (json-get raw-model-obj "context_window"))) (when (and (numberp val) (> val 0)) val))))
      (let ((id (string-downcase (or model-id ""))))
        (cond
          ((cl-ppcre:scan "(?:^|[^0-9])128k(?:[^0-9]|$)" id) 131072)
          ((cl-ppcre:scan "(?:^|[^0-9])64k(?:[^0-9]|$)" id) 65536)
          ((cl-ppcre:scan "(?:^|[^0-9])32k(?:[^0-9]|$)" id) 32768)
          ((cl-ppcre:scan "(?:^|[^0-9])16k(?:[^0-9]|$)" id) 16384)
          ((cl-ppcre:scan "(?:^|[^0-9])8k(?:[^0-9]|$)" id) 8192)
          ((cl-ppcre:scan "(?:^|[^0-9])1m(?:[^0-9]|$)" id) 1048576)
          ((or (cl-ppcre:scan "llama-3\\.1" id)
               (cl-ppcre:scan "llama-3\\.2" id)
               (cl-ppcre:scan "llama-3\\.3" id)) 131072)
          ((cl-ppcre:scan "gpt-oss" id) 131072)
          ((cl-ppcre:scan "deepseek" id) 65536)
          ((cl-ppcre:scan "mistral-large" id) 128000)
          ((cl-ppcre:scan "mixtral-8x22b" id) 65536)
          ((cl-ppcre:scan "codestral" id) 32768)
          ((cl-ppcre:scan "minimax" id) 32768)
          ((cl-ppcre:scan "phi-3" id) 131072)
          ((cl-ppcre:scan "gemma-3" id) 32768)
          ((cl-ppcre:scan "gemma-2" id) 8192)
          ((cl-ppcre:scan "granite" id) 32768)
          (t nil)))))

(defun model-context-size (model)
  "Return the context window size for MODEL, or a default if unknown."
  (or (gethash model *model-context-sizes*)
      (let ((inferred (infer-context-size model)))
        (when inferred
          (setf (gethash model *model-context-sizes*) inferred)
          inferred))
      32768))

(defun set-default-model (model)
  "Change the default model at runtime."
  (setf *default-model* model)
  (format t "~&Default model set to: ~A~%" model))

(defvar *context-percentage* 0.7
  "Fraction of model's context size to allow for history (default 70%).")

(defvar *manual-max-tokens* nil
  "If non-nil, absolute maximum tokens for history; overrides percentage.")

(defvar *max-context-tokens* 6000
  "If history exceeds this many tokens, oldest messages are dropped.")

(defun compute-context-limit (&optional (model *default-model*))
  "Compute the maximum allowed tokens for history."
  (if *manual-max-tokens*
      *manual-max-tokens*
      (let ((size (model-context-size model)))
        (floor (* size *context-percentage*))))

(defun update-context-limit (&optional (model *default-model*))
  "Set *max-context-tokens* to the computed limit for MODEL."
  (let ((limit (compute-context-limit model)))
    (setf *max-context-tokens* limit)
    (format t "~&[Context] Model ~A context size ~A, limit set to ~A tokens.~%"
            model
            (model-context-size model)
            limit)))

(defun show-models ()
  "Display available models with their context sizes."
  (let ((models (list-available-models)))
    (format t "~&=== Available Models ===~%")
    (format t "~&Current default: ~A~%" *default-model*)
    (dolist (m models)
      (format t "  ~A ~A tokens~%"
              (getf m :model)
              (getf m :context-size)))))

(defun select-model (model)
  "Change the active model to MODEL."
  (if (gethash model *model-context-sizes*)
      (progn
        (set-default-model model)
        t)
      (progn
        (show-models)
        nil)))

(defun set-context-percentage (p)
  "Set the fraction of model context to use for history (0.0-1.0)."
  (setf *context-percentage* p))

(defun set-manual-max-tokens (n)
  "Set an absolute maximum token limit for history."
  (setf *manual-max-tokens* n))

(defun reset-manual-max-tokens ()
  "Clear manual limit and revert to percentage-based limit."
  (setf *manual-max-tokens* nil))

)
;;;; harness/stage-0/nvidia-stage3.lisp
;; Payload/message conversion functions

(in-package #:harness.stage-0.nvidia)

(defun message->payload (m)
  (cond
    ((eq (message-role m) :system)
     (ht "role" "system" "content" (message-content m)))
    ((eq (message-role m) :user)
     (ht "role" "user" "content" (message-content m)))
    ((eq (message-role m) :assistant)
     (let ((calls (message-tool-calls m)))
       (if calls
           (ht "role" "assistant"
               "content" (or (message-content m) "")
               "tool_calls"
               (mapcar (lambda (tc)
                         (ht "id" (tool-call-id tc)
                             "type" "function"
                             "function"
                             (ht "name" (tool-call-name tc)
                                 "arguments" (json:encode-json-to-string
                                              (tool-call-arguments tc))))
                       calls))
           (ht "role" "assistant"
               "content" (or (message-content m) "")))))
    ((eq (message-role m) :tool)
     (ht "role" "tool"
         "content" (message-content m)
         "tool_call_id" (message-tool-call-id m)
         "name" (message-name m)))
    (t (error "Unknown message role: ~A" (message-role m)))))

(defun messages-to-payload (messages)
  (mapcar #'message->payload messages))

(defun tool-to-schema (tool-name tool-description tool-params)
  (ht "type" "function"
      "function" (ht "name" tool-name
                     "description" tool-description
                     "parameters" tool-params)))

)
;;;; harness/stage-0/nvidia-stage4.lisp
;; HTTP request and API functions

(in-package #:harness.stage-0.nvidia)

(defun call-nvidia-chat (messages &key
                                          (model *default-model*)
                                          (temperature *default-temperature*)
                                          (max-tokens *default-max-tokens*)
                                          (tools nil)
                                          (tool-choice :auto))
  (unless *nvidia-api-key*
    (error "NVIDIA_API_KEY not set in environment"))
  (let* ((url (format nil "~A/chat/completions" *nvidia-base-url*))
         (payload (ht "model" model
                      "messages" (messages-to-payload messages)
                      "temperature" temperature
                      "max_tokens" max-tokens
                      "stream" nil)))
    (when tools
      (setf (gethash "tools" payload) tools)
      (setf (gethash "tool_choice" payload) tool-choice))
    (handler-case
        (let ((resp (dexador:post url
                    :content (json:encode-json-to-string payload)
                    :headers `(("Authorization" . ,(format nil "Bearer ~A" *nvidia-api-key*))
                               ("Content-Type" . "application/json"))
                    :connect-timeout *request-timeout*
                    :read-timeout *request-timeout*)))
          (let* ((parsed (json:decode-json-from-string resp))
                 (usage (json-get parsed "usage"))
                 (choices (json-get parsed "choices"))
                 (choice (first choices))
                 (msg (json-get choice "message")))
            (values
             `(("content" . ,(json-get msg "content"))
               ("role" . ,(json-get msg "role"))
               ("tool_calls" . ,(json-get msg "tool_calls"))
               ("usage" . ,usage))
             parsed)))
      (dexador:http-request-failed (e)
        (error "NVIDIA API request failed: ~A" e))
      (t (e)
        (error "Unexpected error calling NVIDIA API: ~A" e))))

(defun fetch-models-from-nvidia ()
  "Fetch available models from NVIDIA API."
  (unless *nvidia-api-key*
    (error "NVIDIA_API_KEY not set in environment"))
  (let* ((url (format nil "~A/models" *nvidia-base-url*))
         (resp (dexador:get url
                    :headers `(("Authorization" . ,(format nil "Bearer ~A" *nvidia-api-key*))
                               ("Content-Type" . "application/json"))
                    :connect-timeout *request-timeout*
                    :read-timeout *request-timeout*))
         (parsed (json:decode-json-from-string resp))
         (data (json-get parsed "data")))
    (loop for model in data
          for id = (json-get model "id")
          for ctx = (infer-context-size id model)
          collect (list :model id
                        :owned-by (or (json-get model "owned-by") (json-get model "owned_by"))
                        :context-size (or ctx (model-context-size id))))))

(defun refresh-model-list ()
  "Fetch models from NVIDIA API and update *model-context-sizes*."
  (let ((models (fetch-models-from-nvidia)))
    (loop for m in models
          for size = (getf m :context-size)
          when (and size (integerp size) (> size 0))
            do (setf (gethash (getf m :model) *model-context-sizes*) size))
    (format t "~&Refreshed model list from NVIDIA API: ~A models loaded.~%" (length models))
    models))

)
;;;; harness/stage-0/nvidia-stage5.lisp
;; Provider class and final integration

(in-package #:harness.stage-0.nvidia)

(defclass nvidia-provider (provider)
  ()
  (:default-initargs
   :name "NVIDIA"))

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