#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

QUICKLISP_SETUP="${HOME}/quicklisp/setup.lisp"
if [[ ! -f "${QUICKLISP_SETUP}" ]]; then
  echo "Quicklisp not found at ${QUICKLISP_SETUP}" >&2
  echo "Install Quicklisp before starting the harness." >&2
  exit 1
fi

cat > /tmp/load-reflex.lisp <<'EOF'
(load "/home/reflex/quicklisp/setup.lisp")
(require :asdf)
(ql:quickload '("dexador" "cl-json") :silent t)
(asdf:load-asd (merge-pathnames #p"reflex.asd" (truename #p".")))
(asdf:load-system :reflex)
(format t "~2&Reflex loaded.~%")
(format t "Endpoint: ~A~%" reflex:*default-endpoint*)
(format t "Model:    ~A~%" reflex:*default-model*)
(format t "API key:  ~A~%" (if reflex:*default-api-key* "SET" "NOT SET"))
(format t "Then: (reflex:ask \"Say hello.\")~2&")
(defun reflex::agent-send (line)
  (handler-case
      (let ((reply (reflex:send-prompt line)))
        (format t "~%~A~%" reply))
    (error (e)
      (format t "~%ERROR: ~A~%" e))))
(defun reflex::query (input)
  (declare (ignore input))
  (format t "~%[query called]~%")
  nil)
(defun reflex::query-loop ()
  (format t "~%--- Query Loop (empty line to exit) ---~%")
  (format t " Lisp expressions (start with '(') are evaluated~%")
  (format t " Anything else is sent to the LLM~%~%")
  (loop for line = (progn (format t "~&Operator> ") (finish-output) (read-line *standard-input* nil nil))
        while (and line (string/= line ""))
        do (handler-case
               (if (and (> (length line) 0) (char= (char line 0) #\())
                   (progn
                     (format t "~%---------~%")
                     (let ((expr (read-from-string line)))
                       (format t "~S~%" (eval expr)))
                     (format t "---------~%"))
                   (progn
                     (reflex::agent-send line)))
             (error (e)
               (format t "~%---------~%")
               (format t "WARN: ~A~%" e)
               (format t "---------~%")))))
(reflex::query-loop)
EOF

exec rlwrap -n sbcl --noinform --load /tmp/load-reflex.lisp