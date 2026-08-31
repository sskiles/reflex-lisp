;;; Package definition for the reflex system.

(defpackage #:reflex
  (:use #:cl)
  (:export
   #:ask
   #:send-prompt
   #:agent-send
   #:query-loop
   #:start
   #:make-message
   #:append-turn
   #:save-image
   #:*default-api-key*
   #:*default-endpoint*
   #:*default-model*
   #:*default-system-prompt*
   #:*default-history*
   #:*session-history*
   #:llm-request-error
   #:llm-request-error-body
   #:llm-request-error-status
   #:llm-request-error-url))
