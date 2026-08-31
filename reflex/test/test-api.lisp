;;; Self-contained smoke tests for the HTTP prompt module.

(defpackage #:reflex-test
  (:use #:cl)
  (:export #:run-tests))

(in-package #:reflex-test)

(defvar *sample-body*
  "{\"choices\":[{\"message\":{\"content\":\"Hello from the endpoint.\"}}]}")

(defvar *fake-url*
  "https://example.test/v1/chat/completions")

(defun fake-request (url &key method headers content &allow-other-keys)
  "Return a canned successful OpenAI-compatible response."
  (declare (ignore headers))
  (unless (string= url *fake-url*)
    (error "Test client called the wrong URL: ~A" url))
  (unless (eq method :post)
    (error "Test client used ~S instead of :POST" method))
  (unless (search "\"content\":\"Hello, test endpoint.\"" content)
    (error "Prompt was not serialized into the request body: ~A" content))
  (unless (search "\"model\":\"test-model\"" content)
    (error "Model was not serialized into the request body: ~A" content))
  (values *sample-body* 200 nil url method))

(defun failing-request (url &key method &allow-other-keys)
  "Return a canned HTTP failure."
  (declare (ignore method))
  (values "{\"error\":\"boom\"}" 429 nil url :post))

(defun check (condition format-control &rest format-arguments)
  "Signal a plain error when CONDITION is false."
  (unless condition
    (error (apply #'format nil format-control format-arguments))))

(defun run-tests ()
  "Run all smoke tests and signal an error on failure."
  (let ((reply (reflex:send-prompt
                "Hello, test endpoint."
                :url *fake-url*
                :api-key "test-key"
                :model "test-model"
                :request-function #'fake-request)))
    (check (string= reply "Hello from the endpoint.")
           "Expected extracted message content; got ~S" reply))

  (let ((caught-condition nil))
    (handler-case
        (reflex:send-prompt "Should fail."
                            :url *fake-url*
                            :api-key "test-key"
                            :model "test-model"
                            :request-function #'failing-request)
      (reflex:llm-request-error (condition)
        (setf caught-condition condition)))
    (check caught-condition
           "Expected REFLEX:LLM-REQUEST-ERROR for HTTP status 429.")
    (when caught-condition
      (check (= (reflex:llm-request-error-status caught-condition) 429)
             "Expected status 429; got ~A"
             (reflex:llm-request-error-status caught-condition))))

  (format t "~&REFLEX API smoke tests passed.~%")
  t)
