;;; Package definition for the reflex system.

(defpackage #:reflex
  (:use #:cl)
  (:export
   #:ask
   #:send-prompt
   #:*default-api-key*
   #:*default-endpoint*
   #:*default-model*
   #:llm-request-error
   #:llm-request-error-body
   #:llm-request-error-status
   #:llm-request-error-url))
