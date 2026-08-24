;;;; harness/test.lisp - Basic tests

(defpackage #:harness.test
  (:use #:cl #:harness.tools.protocol #:harness.tools.registry
        #:harness.stage-0.protocol #:harness.stage-0.nvidia
        #:harness.stage-1.protocol #:harness.stage-1.eval-loop
        #:harness.stage-3.protocol)
  (:export #:run-tests))

(in-package #:harness.test)

(defun test-tool-registry ()
  (format t "~&Testing tool registry...~%")
  (let ((reg (make-instance 'tool-registry)))
    (register-tool reg (make-tool-spec
                        "test-tool"
                        "A test tool"
                        (plist-to-hash '("type" "object" "properties" () "required" ()))
                        (lambda (args) (declare (ignore args)) (values "ok" nil))
                        nil))
    (assert (find-tool reg "test-tool"))
    (assert (string= "ok" (execute-tool reg "test-tool" (make-hash-table :test 'equal))))
    (assert (null (find-tool reg "nonexistent")))
    (multiple-value-bind (result err) (execute-tool reg "nonexistent" (make-hash-table :test 'equal))
      (assert (null result))
      (assert (search "not found" err)))
    (format t "  PASS~%")))

(defun test-tool-schemas ()
  (format t "~&Testing tool schemas...~%")
  (let ((reg (make-instance 'tool-registry)))
    (register-tool reg (make-tool-spec
                        "schema-test"
                        "Test schema"
                        (plist-to-hash '("type" "object"
                                         "properties" ("x" ("type" "integer"))
                                         "required" ("x")))
                        (lambda (args) (declare (ignore args)) (values "ok" nil))
                        nil))
    (let ((schemas (tool-schemas-for-llm reg)))
      (assert (= 1 (length schemas)))
      (let ((schema (first schemas)))
        (assert (string= "function" (gethash "type" schema)))
        (let ((fn (gethash "function" schema)))
          (assert (string= "schema-test" (gethash "name" fn)))
          (assert (string= "Test schema" (gethash "description" fn)))
          (let ((params (gethash "parameters" fn)))
            (assert (gethash "properties" params))))))
    (format t "  PASS~%")))

(defun test-history-manager ()
  (format t "~&Testing history manager...~%")
  (let ((mgr (make-history-manager :max-tokens 100)))
    (add-message mgr (make-history-message :role :user :content "Hello"))
    (add-message mgr (make-history-message :role :assistant :content "Hi there!"))
    (assert (= 2 (length (history-messages mgr))))
    (let ((tokens (history-token-count mgr)))
      (assert (> tokens 0))
      (format t "  Tokens: ~A~%" tokens))
    (clear-history mgr)
    (assert (= 0 (length (history-messages mgr))))
    (format t "  PASS~%")))

(defun test-history-pruning ()
  (format t "~&Testing history pruning...~%")
  (let ((mgr (make-history-manager :max-tokens 40)))
    (loop repeat 10 do (add-message mgr (make-history-message :role :user :content "x")))
    (let ((count (length (history-messages mgr))))
      (assert (< count 10))
      (format t "  Pruned to ~A messages~%" count)))
  (format t "  PASS~%"))

(defun test-history-injection ()
  (format t "~&Testing context injection...~%")
  (let ((mgr (make-history-manager :max-tokens 1000)))
    (add-injector mgr (create-context-injector "time" (lambda (mgr input)
                                                        (declare (ignore mgr input))
                                                        (list (make-history-message
                                                               :role :system
                                                               :content (format nil "Current time: ~A" (get-universal-time)))))))
    (let ((injected (inject-context mgr "test")))
      (assert (= 1 (length injected)))
      (assert (eq :system (history-message-role (first injected))))))
  (format t "  PASS~%"))

(defun test-eval-loop-config ()
  (format t "~&Testing eval-loop config...~%")
  (let ((config (make-eval-loop-config :max-iterations 5 :system-prompt "Test")))
    (assert (= 5 (eval-loop-config-max-iterations config)))
    (assert (string= "Test" (eval-loop-config-system-prompt config))))
  (format t "  PASS~%"))

(defun test-provider-config ()
  (format t "~&Testing provider config...~%")
  (let ((config (make-provider-config :name "test" :api-key "key" :base-url "http://x" :default-model "m1")))
    (assert (string= "test" (provider-config-name config)))
    (assert (string= "m1" (provider-config-default-model config))))
  (format t "  PASS~%"))

(defun test-eval-result-usage ()
  (format t "~&Testing eval-result usage format...~%")
  (let* ((alist-usage '((:PROMPT--TOKENS . 538) (:TOTAL--TOKENS . 618) (:COMPLETION--TOKENS . 80)))
         (res (make-eval-result :content "test" :usage alist-usage)))
    (assert (eval-result-usage res))
    (assert (= 538 (or (harness.stage-0.nvidia:json-get (eval-result-usage res) "prompt_tokens") 0))))
  (format t "  PASS~%"))

(defun run-tests ()
  (format t "~&=== Running Harness Tests ===~%")
  (test-tool-registry)
  (test-tool-schemas)
  (test-history-manager)
  (test-history-pruning)
  (test-history-injection)
  (test-eval-loop-config)
  (test-provider-config)
  (test-eval-result-usage)
  (format t "~&=== All Tests Passed ===~%"))