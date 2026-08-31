#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

QUICKLISP_SETUP="${HOME}/quicklisp/setup.lisp"
if [[ ! -f "${QUICKLISP_SETUP}" ]]; then
  echo "Quicklisp not found at ${QUICKLISP_SETUP}" >&2
  echo "Install Quicklisp before starting the harness." >&2
  exit 1
fi

exec rlwrap -n sbcl --noinform \
  --eval "(load \"${QUICKLISP_SETUP}\")" \
  --eval "(require :asdf)" \
  --eval "(ql:quickload '(\"dexador\" \"cl-json\") :silent t)" \
  --eval "(asdf:load-asd (merge-pathnames #p\"reflex.asd\" (truename #p\".\")))" \
  --eval "(asdf:load-system :reflex)" \
  --eval "(reflex:start)"
