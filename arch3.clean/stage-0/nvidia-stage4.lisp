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
    (progn
      ;; Lazily load Dexador if it hasn't been loaded yet (avoids foreign lib in core)
      (unless (fboundp 'dexador:post)
        (ql:quickload :dexador))
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
               (msg (json-get choice "message"))
               (reasoning (or (json-get msg "reasoning_content")
                              (json-get msg "reasoning")
                              (json-get msg "thinking"))))
          (values
           `(("content" . ,(json-get msg "content"))
             ("reasoning_content" . ,reasoning)
             ("role" . ,(json-get msg "role"))
             ("tool_calls" . ,(json-get msg "tool_calls"))
             ("usage" . ,usage))
           parsed))))
      (dexador:http-request-failed (e)
        (error "NVIDIA API request failed: ~A" e))
      (t (e)
        (error "Unexpected error calling NVIDIA API: ~A" e)))))


(defun fetch-models-from-nvidia ()
  "Fetch available models from NVIDIA API."
  (unless *nvidia-api-key*
    (error "NVIDIA_API_KEY not set in environment"))
  ;; Lazy‑load Dexador for the model‑list request (avoids foreign lib in saved image)
  (unless (fboundp 'dexador:get)
    (ql:quickload :dexador))
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

