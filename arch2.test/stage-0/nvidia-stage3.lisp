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
                                              (tool-call-arguments tc)))))
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

