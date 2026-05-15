#!/bin/zsh
set -u
set -o pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-/opt/homebrew/bin/python3}"
if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="/usr/bin/python3"
fi

OUT_MD="${ROOT}/stock_feed_inbox.md"
TMP_MD="${ROOT}/.stock_feed_inbox.$$.$RANDOM.tmp"
LOG_FILE="$HOME/space_stock_collector.log"

{
  echo "==== $(date '+%Y-%m-%d %H:%M:%S %Z') collector start ===="
  cd "${ROOT}" || {
    echo "collector: cd failed (${ROOT})"
    exit 1
  }

  if BRIEF_PREFLIGHT_WAIT_S="${BRIEF_PREFLIGHT_WAIT_S:-120}" \
     BRIEF_PREFLIGHT_RETRY_S="${BRIEF_PREFLIGHT_RETRY_S:-90}" \
     "${PYTHON_BIN}" "${ROOT}/space_stock_brief.py" | sed '/^<!-- /d' > "${TMP_MD}"; then
    mv "${TMP_MD}" "${OUT_MD}"
    echo "collector: success -> ${OUT_MD}"
  else
    rc=$?
    rm -f "${TMP_MD}"
    echo "collector: failed (rc=${rc})"
    exit "${rc}"
  fi
} >> "${LOG_FILE}" 2>&1
