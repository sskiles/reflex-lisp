#!/usr/bin/env bash
# restart-core.sh — resume a previously saved Reflex core.
# Usage: ./restart-core.sh [path/to/reflex.core]
# Defaults to ./reflex.core if no argument is given.
set -euo pipefail

cd "$(dirname "$0")"

CORE_PATH="${1:-./reflex.core}"
if [[ ! -f "${CORE_PATH}" ]]; then
  echo "Core file not found: ${CORE_PATH}" >&2
  echo "Save one first with (reflex:save-image \"reflex.core\")" >&2
  exit 1
fi

exec rlwrap -n sbcl --noinform --core "${CORE_PATH}"
