#!/usr/bin/env bash
set -euo pipefail
cd /home/reflex/common-lisp/arch3.clean
exec rlwrap -n sbcl --noinform --load loader.lisp
