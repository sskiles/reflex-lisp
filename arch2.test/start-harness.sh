#!/usr/bin/env bash
set -euo pipefail
cd /home/reflex/lisp/arch2.test
exec rlwrap -n sbcl --noinform --load loader.lisp
