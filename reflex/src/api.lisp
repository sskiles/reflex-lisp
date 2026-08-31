(in-package #:reflex)

;;; Default endpoint parameters

(defparameter *default-endpoint* "https://integrate.api.nvidia.com/v1/chat/completions")
(defparameter *default-model* "openai/gpt-oss-20b")
(defparameter *default-api-key* (uiop:getenv "NVIDIA_API_KEY"))

;;; HTTP client for an OpenAI-compatible chat-completions endpoint.

(defun %request-headers (api-key)
  "Return HTTP request headers for the chat-completions request."
  (append '(("Content-Type" . "application/json"))
          (when api-key
            (list (cons "Authorization"
                        (format nil "Bearer ~A" api-key))))))

(defun %request-body (model prompt temperature max-tokens top-p stop)
  "Encode PROMPT as an OpenAI-compatible chat-completions request body."
  (json:encode-json-alist-to-string
   (append
    `(("model" . ,model)
      ("messages" . ((("role" . "user")
                      ("content" . ,prompt)))))
    (when temperature
      (list (cons "temperature" temperature)))
    (when max-tokens
      (list (cons "max_tokens" max-tokens)))
    (when top-p
      (list (cons "top_p" top-p)))
    (when stop
      (list (cons "stop" stop))))))

(defun %json-value (key object)
  "Return the value associated with KEY in decoded JSON alist OBJECT."
  (cdr (assoc key object)))

(defun %response-content (body)
  "Extract the first assistant message from a JSON response BODY string.
When the response is not the expected chat-completions shape, return BODY."
  (let ((decoded (handler-case
                     (json:decode-json-from-string body)
                   (error () nil))))
    (let* ((choices (and decoded (%json-value :CHOICES decoded)))
           (first-choice (and (listp choices) (first choices)))
           (message (and first-choice (%json-value :MESSAGE first-choice)))
           (content (and message (%json-value :CONTENT message))))
      (or content body))))

(define-condition llm-request-error (error)
  ((url :initarg :url :reader llm-request-error-url)
   (status :initarg :status :reader llm-request-error-status)
   (body :initarg :body :reader llm-request-error-body))
  (:report
   (lambda (condition stream)
     (format stream "LLM request to ~A failed with HTTP status ~A~%"
             (llm-request-error-url condition)
             (llm-request-error-status condition))
     (format stream "Response body: ~A" (llm-request-error-body condition))))
  (:documentation "Signalled when the endpoint returns a non-2xx response."))

(defun send-prompt (prompt &key
                    (endpoint *default-endpoint*)
                    (model *default-model*)
                    (api-key *default-api-key*)
                    (temperature 0.7d0)
                    (max-tokens 512)
                    (top-p 1.0d0)
                    stop
                    (request-function #'dexador:request))
  "Send PROMPT to an OpenAI-compatible chat-completions endpoint.

PROMPT is the string sent as the single user message.  ENDPOINT defaults to
*DEFAULT-ENDPOINT*, MODEL defaults to *DEFAULT-MODEL*, and API-KEY defaults to
*DEFAULT-API-KEY*.  The function returns the response text as a string.

REQUEST-FUNCTION exists primarily for tests and protocol adapters; it is called
with the same arguments accepted by DEXADOR:REQUEST."
  (let ((api-key (or api-key (uiop:getenv "NVIDIA_API_KEY"))))
    (multiple-value-bind (body status response-headers response-uri response-method)
        (funcall request-function
                 endpoint
                 :method :post
                 :headers (%request-headers api-key)
                 :content (%request-body model prompt temperature max-tokens top-p stop))
      (declare (ignore response-headers response-uri response-method))
      (unless (and (integerp status)
                   (<= 200 status)
                   (<= status 299))
        (error 'llm-request-error
               :url endpoint
               :status status
               :body body))
      (%response-content body))))

(defun ask (prompt &rest options)
  "Convenience wrapper around SEND-PROMPT."
  (apply #'send-prompt prompt options))
