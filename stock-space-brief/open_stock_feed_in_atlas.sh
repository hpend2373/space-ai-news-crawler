#!/bin/zsh

# Temporarily silence stderr so any inherited xtrace/verbose settings don't
# spam automation output before we can disable them.
exec 9>&2 2>/dev/null
unsetopt XTRACE VERBOSE 2>/dev/null || true
set +x 2>/dev/null || true
exec 2>&9 9>&-

set -u

# Some automation environments enable zsh's BG_NICE, which tries to call nice(5)
# for background jobs and can fail with "operation not permitted". We don't
# need bg-nice here.
unsetopt BG_NICE 2>/dev/null || true

DASHBOARD_PATH="${HOME}/SPACE/stock_feed.html"
DASHBOARD_URL="file://${HOME}/SPACE/stock_feed.html"
ATLAS_BIN="/Applications/ChatGPT Atlas.app/Contents/MacOS/ChatGPT Atlas"
SAFARI_BIN="/Applications/Safari.app/Contents/MacOS/Safari"
LOG_PATH="${HOME}/SPACE/.space_stock_agent_open.log"
LOCK_DIR="${HOME}/SPACE/.space_stock_agent_open.lock"
LOCK_WAIT_SECS="${LOCK_WAIT_SECS:-30}"
TOTAL_TIMEOUT_SECS="${TOTAL_TIMEOUT_SECS:-180}"
SLEEP_ON_CONN_INVALID_SECS="${SLEEP_ON_CONN_INVALID_SECS:-8}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-20}"
CMD_TIMEOUT_SECS="${CMD_TIMEOUT_SECS:-25}"
LAUNCHCTL_PATH="/bin/launchctl"
ASUSER_UID="${ASUSER_UID:-}"

# Keep automation output clean: send all incidental stdout/stderr (xtrace,
# tool noise, etc.) to the dedicated log file. The script prints only a final
# status line via FD 3 (original stdout).
exec 3>&1
exec 1>>"$LOG_PATH"
exec 2>>"$LOG_PATH"
XTRACEFD=2 2>/dev/null || true

_ts() {
  # ISO-ish local timestamp
  date "+%Y-%m-%d %H:%M:%S %Z"
}

_log() {
  printf "%s %s\n" "$(_ts)" "$*" >> "$LOG_PATH"
}

_acquire_lock() {
  # Prevent concurrent Atlas open attempts (AppleScript/LaunchServices can flake
  # under contention).
  local start epoch_now lock_pid
  start="$(date +%s)"

  while true; do
    if /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
      LOCK_ACQUIRED=1
      printf "%s\n" "$$" > "$LOCK_DIR/pid" 2>/dev/null || true
      date -u "+%Y-%m-%dT%H:%M:%SZ" > "$LOCK_DIR/started_at" 2>/dev/null || true
      _log "LOCK: acquired pid=$$"
      return 0
    fi

    # Stale lock cleanup: if the recorded pid is not running, remove the lock.
    if [[ -f "$LOCK_DIR/pid" ]]; then
      lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
      if [[ -n "$lock_pid" && "$lock_pid" == <-> ]]; then
        if ! /bin/kill -0 "$lock_pid" 2>/dev/null; then
          _log "LOCK: removing stale lock (pid ${lock_pid} not running)"
          /bin/rm -rf "$LOCK_DIR" 2>/dev/null || true
          continue
        fi
      fi
    fi

    epoch_now="$(date +%s)"
    if (( epoch_now - start >= LOCK_WAIT_SECS )); then
      _log "LOCK: timeout after ${LOCK_WAIT_SECS}s"
      echo "SKIP: Atlas 자동 열기가 이미 실행 중이거나(macOS 자동화 경합), 잠금 해제 대기 시간이 초과되었습니다." >&3
      return 2
    fi

    sleep 1
  done
}

_release_lock() {
  if [[ "${LOCK_ACQUIRED:-0}" == "1" ]]; then
    _log "LOCK: release pid=$$"
    /bin/rm -rf "$LOCK_DIR" 2>/dev/null || true
  fi
}

_record_error() {
  # Usage: _record_error <priority_int> <label>
  local priority="$1"
  local label="$2"

  if (( priority > BEST_PRIORITY )); then
    BEST_PRIORITY="$priority"
    BEST_LABEL="$label"
    BEST_OUT="$LAST_OUT"
    BEST_RC="$LAST_RC"
  fi
}

_run() {
  # Usage: _run <label> <cmd...>
  local label="$1"
  shift
  _log "-- ${label}"
  _log "CMD: $*"

  # Capture stdout/stderr for debugging.
  local out
  out="$("$@" 2>&1)" || {
    local rc=$?
    LAST_RC=$rc
    LAST_OUT=$out
    _log "RC: ${rc}"
    _log "OUT: ${out}"
    return ${rc}
  }

  LAST_RC=0
  LAST_OUT=$out
  _log "RC: 0"
  _log "OUT: ${out}"
  return 0
}

_run_timeout() {
  # Usage: _run_timeout <label> <timeout_secs> <cmd...>
  local label="$1"
  local timeout_s="$2"
  shift 2

  _log "-- ${label}"
  _log "CMD: $* (timeout ${timeout_s}s)"

  # Use python to enforce a hard timeout and kill the whole process group.
  local out
  out="$(
    /usr/bin/python3 -c '
import os, signal, subprocess, sys
timeout = float(sys.argv[1])
cmd = sys.argv[2:]
p = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    start_new_session=True,
)
try:
    out, _ = p.communicate(timeout=timeout)
except subprocess.TimeoutExpired:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except Exception:
        try:
            p.kill()
        except Exception:
            pass
    out2, _ = p.communicate()
    sys.stdout.write(out2 or "")
    sys.exit(124)
sys.stdout.write(out or "")
sys.exit(p.returncode if p.returncode is not None else 1)
' "$timeout_s" "$@" 2>&1
  )" || {
    local rc=$?
    LAST_RC=$rc
    LAST_OUT=$out
    _log "RC: ${rc}"
    _log "OUT: ${out}"
    return ${rc}
  }

  LAST_RC=0
  LAST_OUT=$out
  _log "RC: 0"
  _log "OUT: ${out}"
  return 0
}

_run_gui() {
  # Run a GUI-affecting command in the user's GUI bootstrap (helps in automations).
  # Usage: _run_gui <label> <cmd...>
  local label="$1"
  shift

  # In Codex Automations (no TTY), the process can run without a fully functional
  # GUI/LaunchServices/AppleEvents bootstrap. `launchctl asuser <uid>` often
  # restores access, even when EUID==uid. Fall back to direct execution if it
  # flakes.
  if [[ -x "$LAUNCHCTL_PATH" && -n "${ASUSER_UID:-}" && "$ASUSER_UID" == <-> ]]; then
    if [[ ! -t 1 && ! -t 2 ]] || [[ "${FORCE_ASUSER:-0}" == "1" ]]; then
      if _run "$label" "$LAUNCHCTL_PATH" asuser "$ASUSER_UID" "$@"; then
        return 0
      fi
      _log "INFO: ${label} failed under launchctl asuser; trying direct"
      _run "${label}_direct" "$@"
      return $?
    fi
  fi

  _run "$label" "$@"
}

_run_gui_timeout() {
  # Usage: _run_gui_timeout <label> <timeout_secs> <cmd...>
  local label="$1"
  local timeout_s="$2"
  shift 2

  if [[ -x "$LAUNCHCTL_PATH" && -n "${ASUSER_UID:-}" && "$ASUSER_UID" == <-> ]]; then
    if [[ ! -t 1 && ! -t 2 ]] || [[ "${FORCE_ASUSER:-0}" == "1" ]]; then
      if _run_timeout "$label" "$timeout_s" "$LAUNCHCTL_PATH" asuser "$ASUSER_UID" "$@"; then
        return 0
      fi
      _log "INFO: ${label} failed under launchctl asuser; trying direct"
      _run_timeout "${label}_direct" "$timeout_s" "$@"
      return $?
    fi
  fi

  _run_timeout "$label" "$timeout_s" "$@"
}

_run_gui_bg_exec() {
  # Start the Atlas binary without going through LaunchServices (works even if
  # LS lookups are flaky). Run in the user's GUI bootstrap when possible.
  # Usage: _run_gui_bg_exec <label> <binary> [args...]
  local label="$1"
  shift

  # Use a POSIX shell to avoid zsh bg-nice behavior in sub-shells.
  local cmd
  cmd="\"$1\""
  shift
  for arg in "$@"; do
    cmd="${cmd} \"${arg//\"/\\\"}\""
  done

  _run_gui "$label" /bin/sh -lc "/usr/bin/nohup ${cmd} >/dev/null 2>&1 &"
}

_atlas_running() {
  pgrep -x "ChatGPT Atlas" >/dev/null 2>&1 && return 0
  pgrep -f "/Applications/ChatGPT Atlas.app/Contents/MacOS/ChatGPT Atlas" >/dev/null 2>&1
}

_python_for_atlas_cli() {
  # atlas_cli.py requires Python >= 3.10 (dataclasses slots).
  local -a candidates
  local py_from_path

  candidates=()

  py_from_path="$(command -v python3 2>/dev/null || true)"
  [[ -n "$py_from_path" ]] && candidates+=("$py_from_path")

  # Automations sometimes run with a minimal PATH (finding /usr/bin/python3 3.9).
  # Probe common Homebrew/Python locations explicitly.
  candidates+=(
    /opt/homebrew/bin/python3
    /opt/homebrew/opt/python@3.13/libexec/bin/python3
    /opt/homebrew/opt/python@3.12/libexec/bin/python3
    /opt/homebrew/opt/python@3.11/libexec/bin/python3
    /usr/local/bin/python3
  )

  local py major minor
  for py in $candidates; do
    [[ -x "$py" ]] || continue
    read -r major minor <<< "$("$py" -c 'import sys; print(sys.version_info[0], sys.version_info[1])' 2>/dev/null)" || continue

    if (( major > 3 || (major == 3 && minor >= 10) )); then
      printf "%s" "$py"
      return 0
    fi
  done

  return 1
}

_atlas_cli_open_and_focus() {
  # Open the dashboard in Atlas and then focus the tab so the user can see it.
  # Returns 0 only if we can verify the tab exists and focusing succeeds.
  local py="$1"

  # First try to focus an existing tab to avoid creating duplicates on every run.
  if _run_gui_timeout "atlas_cli_tabs_json" "$CMD_TIMEOUT_SECS" "$py" ${HOME}/.codex/skills/atlas/scripts/atlas_cli.py tabs --json; then
    local focus_ids_existing
    focus_ids_existing="$(printf "%s" "$LAST_OUT" | "$py" -c '
import json, sys
url = "file://${HOME}/SPACE/stock_feed.html"
rows = json.load(sys.stdin)
match = [r for r in rows if r.get("url") == url]
if not match:
    raise SystemExit(2)
m = sorted(match, key=lambda r: (int(r.get("window_id", 0) or 0), int(r.get("tab_index", 0) or 0)))[-1]
print(m.get("window_id", 0), m.get("tab_index", 0))
' 2>/dev/null || true)"

    local window_id_existing tab_index_existing
    window_id_existing="$(printf "%s" "$focus_ids_existing" | /usr/bin/awk '{print $1}' 2>/dev/null || true)"
    tab_index_existing="$(printf "%s" "$focus_ids_existing" | /usr/bin/awk '{print $2}' 2>/dev/null || true)"

    if [[ -n "$window_id_existing" && -n "$tab_index_existing" && "$window_id_existing" == <-> && "$tab_index_existing" == <-> ]]; then
      if _run_gui_timeout "atlas_cli_focus_existing" "$CMD_TIMEOUT_SECS" "$py" ${HOME}/.codex/skills/atlas/scripts/atlas_cli.py focus-tab "$window_id_existing" "$tab_index_existing"; then
        return 0
      fi
      _record_error 98 "atlas_cli_focus_existing"
    fi
  else
    _record_error 99 "atlas_cli_tabs_json"
  fi

  if ! _run_gui_timeout "atlas_cli_open" "$CMD_TIMEOUT_SECS" "$py" ${HOME}/.codex/skills/atlas/scripts/atlas_cli.py open-tab "$DASHBOARD_URL"; then
    _record_error 100 "atlas_cli_open"
    return 1
  fi

  if ! _run_gui_timeout "atlas_cli_tabs_json_after_open" "$CMD_TIMEOUT_SECS" "$py" ${HOME}/.codex/skills/atlas/scripts/atlas_cli.py tabs --json; then
    _record_error 99 "atlas_cli_tabs_json_after_open"
    return 1
  fi

  local focus_ids
  focus_ids="$(printf "%s" "$LAST_OUT" | "$py" -c '
	import json, sys
	url = "file://${HOME}/SPACE/stock_feed.html"
	rows = json.load(sys.stdin)
	match = [r for r in rows if r.get("url") == url]
	if not match:
	    raise SystemExit(2)
	m = sorted(match, key=lambda r: (int(r.get("window_id", 0) or 0), int(r.get("tab_index", 0) or 0)))[-1]
	print(m.get("window_id", 0), m.get("tab_index", 0))
	' 2>/dev/null || true)"

  local window_id tab_index
  window_id="$(printf "%s" "$focus_ids" | /usr/bin/awk '{print $1}' 2>/dev/null || true)"
  tab_index="$(printf "%s" "$focus_ids" | /usr/bin/awk '{print $2}' 2>/dev/null || true)"

  if [[ -z "$window_id" || -z "$tab_index" || "$window_id" != <-> || "$tab_index" != <-> ]]; then
    _log "WARN: could not parse focus target from tabs json"
    _record_error 98 "atlas_cli_focus_parse"
    return 1
  fi

  if ! _run_gui_timeout "atlas_cli_focus" "$CMD_TIMEOUT_SECS" "$py" ${HOME}/.codex/skills/atlas/scripts/atlas_cli.py focus-tab "$window_id" "$tab_index"; then
    _record_error 98 "atlas_cli_focus"
    return 1
  fi

  return 0
}

_launch_atlas_best_effort() {
  # Prefer LaunchServices. If LS is flaky, fall back to direct exec.
  _run_gui "launch_open_bundle_id" /usr/bin/open -g -b com.openai.atlas >/dev/null && return 0
  _run_gui "launch_open_app_path" /usr/bin/open -g -a "/Applications/ChatGPT Atlas.app" >/dev/null && return 0
  _run_gui "launch_open_app_name" /usr/bin/open -g -a "ChatGPT Atlas" >/dev/null && return 0

  local bin="/Applications/ChatGPT Atlas.app/Contents/MacOS/ChatGPT Atlas"
  if [[ -x "$bin" ]]; then
    _run_gui_bg_exec "launch_exec" "$bin"
  fi
  return 0
}

_open_via_local_http() {
  # Serve the workspace directory briefly and open the dashboard via http://.
  # This can work when opening file:// URLs is flaky in some automation contexts.
  local py
  py="$(_python_for_atlas_cli)" || py="$(command -v python3 2>/dev/null || true)"
  [[ -n "$py" && -x "$py" ]] || return 1

  local port
  port="$("$py" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)" || port=""
  [[ -n "$port" && "$port" == <-> ]] || return 1

  "$py" -m http.server "$port" --bind 127.0.0.1 --directory "${HOME}/SPACE" >/dev/null 2>&1 &
  local server_pid=$!
  _log "http_server: started pid=${server_pid} port=${port}"
  # Ensure we don't leave servers around.
  /bin/sh -lc "sleep 120; /bin/kill ${server_pid} >/dev/null 2>&1" >/dev/null 2>&1 &
  sleep 0.8

  local url="http://127.0.0.1:${port}/stock_feed.html"
  if [[ -x "$SAFARI_BIN" ]]; then
    if _run_gui_bg_exec "safari_exec_http" "$SAFARI_BIN" "$url"; then
      echo "OK: opened dashboard via local http server (Safari direct exec)" >&3
      return 0
    fi
    _record_error 6 "safari_exec_http"
  fi

  if _run_gui "open_local_http_safari" /usr/bin/open -a "Safari" "$url"; then
    echo "OK: opened dashboard via local http server (Safari)" >&3
    return 0
  fi
  _record_error 5 "open_local_http_safari"

  if _run_gui "open_local_http_default" /usr/bin/open "$url"; then
    echo "OK: opened dashboard via local http server (default browser)" >&3
    return 0
  fi
  _record_error 5 "open_local_http_default"

  return 1
}

_io_console_locked() {
  # Best-effort lock status. Returns "Yes"/"No"/"".
  /usr/sbin/ioreg -n Root -d1 -w0 2>/dev/null | /usr/bin/awk -F'= ' '/"IOConsoleLocked"/ {gsub(/[",]/,"",$2); print $2; exit}' 2>/dev/null || true
}

_schedule_deferred_retry() {
  # If AppleScript/GUI services are temporarily unavailable (common when the
  # screen is locked or the GUI session is not fully up), schedule a longer
  # background retry without blocking the automation run.
  #
  # Guard against infinite recursion with DEFERRED_RETRY=1.
  if [[ "${DEFERRED_RETRY:-0}" == "1" ]]; then
    return 0
  fi

  local delay_s="${DEFER_DELAY_SECS:-60}"
  local retry_timeout="${DEFER_TIMEOUT_SECS:-1800}" # 30 min
  local retry_attempts="${DEFER_MAX_ATTEMPTS:-60}"

  _log "DEFER: scheduling background retry delay=${delay_s}s timeout=${retry_timeout}s attempts=${retry_attempts}"

  # Run detached; all output goes to the same log file via this script's stderr redirection.
  /bin/sh -lc "/usr/bin/nohup /bin/sh -lc 'sleep ${delay_s}; DEFERRED_RETRY=1 TOTAL_TIMEOUT_SECS=${retry_timeout} MAX_ATTEMPTS=${retry_attempts} \"${0}\"' >>\"${LOG_PATH}\" 2>&1 &" >/dev/null 2>&1 || true
}

main() {
  # Global-ish run state for inspecting failures.
  typeset -g LAST_OUT=""
  typeset -g LAST_RC=0
  typeset -g BEST_OUT=""
  typeset -g BEST_LABEL=""
  typeset -g BEST_PRIORITY=0
  typeset -g BEST_RC=0
  typeset -g LOCK_ACQUIRED=0
  # Track whether we observed the common transient AppleScript/GUI failure mode
  # during this run. If we end up in weak fallbacks (Quick Look/Finder reveal),
  # we can still schedule a background retry to actually open in Atlas/browser.
  typeset -g CONN_INVALID_SEEN=0

  _acquire_lock
  local lock_rc=$?
  if (( lock_rc != 0 )); then
    return 0
  fi
  trap _release_lock EXIT INT TERM

  if [[ -z "$ASUSER_UID" ]]; then
    # Prefer the active console user when available (automations can run with
    # a different effective user / bootstrap context).
    local console_uid
    console_uid="$(( $(/usr/bin/stat -f%u /dev/console 2>/dev/null || echo 0) ))"
    if [[ "$console_uid" == <-> && "$console_uid" != "0" ]]; then
      ASUSER_UID="$console_uid"
    else
      ASUSER_UID="$EUID"
    fi
  fi

  if (( MAX_ATTEMPTS < 6 )); then
    MAX_ATTEMPTS=6
  fi

  local start_epoch deadline_epoch
  start_epoch="$(date +%s)"
  deadline_epoch=$(( start_epoch + TOTAL_TIMEOUT_SECS ))

  # Helpful diagnostics for automation runs.
  _log "ENV: uid=${ASUSER_UID} euid=${EUID} user=$(/usr/bin/id -un 2>/dev/null || true) shell=${SHELL:-}"
  _log "ENV: timeout=${TOTAL_TIMEOUT_SECS}s max_attempts=${MAX_ATTEMPTS} sleep_conn_invalid=${SLEEP_ON_CONN_INVALID_SECS}s ppid=$PPID parent=$(/bin/ps -p "$PPID" -o comm= 2>/dev/null || true)"
  _log "ENV: IOConsoleLocked=$(_io_console_locked)"

  if [[ ! -f "$DASHBOARD_PATH" ]]; then
    _log "ERROR: dashboard missing: ${DASHBOARD_PATH}"
    echo "FAIL: dashboard missing: ${DASHBOARD_PATH}" >&3
    return 1
  fi

  # If the console is locked, AppleScript/LaunchServices often fail. Don't burn
  # the whole time budget; schedule a deferred retry for after unlock.
  if [[ "${DEFERRED_RETRY:-0}" != "1" ]]; then
    local locked
    locked="$(_io_console_locked)"
    if [[ "$locked" == "Yes" ]]; then
      _log "INFO: console locked; deferring Atlas open"
      _schedule_deferred_retry
      echo "DEFER: 콘솔 잠금 상태로 Atlas 자동 열기를 지연합니다. 잠금 해제 후 백그라운드 재시도 예정 (로그: $LOG_PATH)" >&3
      return 0
    fi
  fi

  local attempt=1
  while (( attempt <= MAX_ATTEMPTS )); do
    local now_epoch time_left
    now_epoch="$(date +%s)"
    time_left=$(( deadline_epoch - now_epoch ))
    if (( time_left <= 0 )); then
      _log "TIMEOUT: exceeded ${TOTAL_TIMEOUT_SECS}s budget"
      break
    fi

    _log "==== open attempt (try ${attempt}/${MAX_ATTEMPTS}) (time_left ${time_left}s) ===="
    local this_conn_invalid=0

    if ! _atlas_running; then
      _log "Atlas not running; attempting to launch"
      _launch_atlas_best_effort || true
      # Wait for the process to appear (and give the UI stack time to initialize).
      local i=1
      while (( i <= 10 )); do
        _atlas_running && break
        sleep 1
        i=$(( i + 1 ))
      done
      sleep 2
    fi

    # 1) Atlas CLI (no uv) - uses AppleScript under the hood.
    local py
    py="$(_python_for_atlas_cli)" || py=""
    if [[ -n "$py" ]]; then
      if _atlas_cli_open_and_focus "$py"; then
        echo "OK: opened in Atlas via atlas_cli" >&3
        return 0
      fi
      # Prefer the most informative recent label when this helper fails.
      _record_error 100 "atlas_cli"

      if [[ "$LAST_OUT" == *"hiservices-xpcservice"* || "$LAST_OUT" == *"Connection invalid"* || "$LAST_OUT" == *"Connection Invalid"* ]]; then
        this_conn_invalid=1
        CONN_INVALID_SEEN=1
        _log "INFO: AppleScript connection invalid; retrying atlas_cli after short delay"
        sleep 3
        if _atlas_cli_open_and_focus "$py"; then
          echo "OK: opened in Atlas via atlas_cli (retry)" >&3
          return 0
        fi
        _record_error 95 "atlas_cli_retry"

        if [[ "$LAST_OUT" == *"hiservices-xpcservice"* || "$LAST_OUT" == *"Connection invalid"* || "$LAST_OUT" == *"Connection Invalid"* ]]; then
          this_conn_invalid=1
          CONN_INVALID_SEEN=1
        fi
      fi
    else
      _log "-- atlas_cli"
      _log "SKIP: python3 >= 3.10 not found"
    fi

    # 2) Bundle identifier (avoids app name quoting issues).
    if _run_gui "open_bundle_id" /usr/bin/open -b com.openai.atlas "$DASHBOARD_PATH"; then
      echo "OK: opened in Atlas via bundle id" >&3
      return 0
    fi
    _record_error 80 "open_bundle_id"

    # 3) App name (LaunchServices lookup by display name).
    if _run_gui "open_app_name" /usr/bin/open -a "ChatGPT Atlas" "$DASHBOARD_PATH"; then
      echo "OK: opened in Atlas via app name" >&3
      return 0
    fi
    _record_error 70 "open_app_name"

    # 4) Absolute app bundle path.
    if _run_gui "open_app_path" /usr/bin/open -a "/Applications/ChatGPT Atlas.app" "$DASHBOARD_PATH"; then
      echo "OK: opened in Atlas via app path" >&3
      return 0
    fi
    _record_error 75 "open_app_path"

    # 5) Direct AppleScript.
    if _run_gui "osascript" /usr/bin/osascript \
        -e 'tell application id "com.openai.atlas" to activate' \
        -e 'tell application id "com.openai.atlas" to open location "file://${HOME}/SPACE/stock_feed.html"'; then
      echo "OK: opened in Atlas via osascript" >&3
      return 0
    fi
    _record_error 90 "osascript"
    if [[ "$LAST_OUT" == *"hiservices-xpcservice"* || "$LAST_OUT" == *"Connection invalid"* || "$LAST_OUT" == *"Connection Invalid"* ]]; then
      this_conn_invalid=1
      CONN_INVALID_SEEN=1
    fi

    # 6) As a last resort, open via the default handler (may be Atlas if it is
    # set as the default browser/HTML viewer). This is better than doing
    # nothing, but we keep it as the final fallback.
    if _run_gui "open_default" /usr/bin/open "$DASHBOARD_PATH"; then
      echo "OK: opened dashboard via default handler" >&3
      return 0
    fi
    _record_error 10 "open_default"

    # 7) Fallback: open via Safari binary directly (bypasses LaunchServices lookups).
    if [[ -x "$SAFARI_BIN" ]]; then
      if _run_gui_bg_exec "safari_exec_file" "$SAFARI_BIN" "$DASHBOARD_URL"; then
        echo "OK: opened dashboard in Safari (direct exec; LaunchServices/Atlas 불안정)" >&3
        return 0
      fi
      _record_error 9 "safari_exec_file"
    fi

    # 8) Fallback: open via a temporary local HTTP server (best-effort).
    if _open_via_local_http; then
      return 0
    fi

    # 9) Fallback: open in a regular browser (even if Atlas is unavailable).
    # This is best-effort; if LaunchServices is unhealthy, it may still fail.
    if _run_gui "open_safari" /usr/bin/open -a "Safari" "$DASHBOARD_PATH"; then
      echo "OK: opened dashboard in Safari (Atlas unavailable)" >&3
      return 0
    fi
    _record_error 9 "open_safari"

    if _run_gui "open_chrome" /usr/bin/open -a "Google Chrome" "$DASHBOARD_PATH"; then
      echo "OK: opened dashboard in Chrome (Atlas unavailable)" >&3
      return 0
    fi
    _record_error 8 "open_chrome"

    # 10) Fallback: Quick Look preview. This does not require a browser association
    # and is often more resilient than LaunchServices when the system is flaky.
    if _run_gui "open_quicklook" /bin/sh -lc "/usr/bin/qlmanage -p \"${DASHBOARD_PATH}\" >/dev/null 2>&1 &"; then
      if (( CONN_INVALID_SEEN == 1 )); then
        _schedule_deferred_retry
        echo "OK: Quick Look로 대시보드 미리보기 열림(Atlas/브라우저 불안정으로 재시도 예약됨) (로그: $LOG_PATH)" >&3
        return 0
      fi
      echo "OK: Quick Look로 대시보드 미리보기 열림" >&3
      return 0
    fi
    _record_error 7 "open_quicklook"

    if _run_gui "open_finder_reveal" /usr/bin/open -R "$DASHBOARD_PATH"; then
      _schedule_deferred_retry
      echo "DEFER: Finder에서 파일 위치만 열었습니다(자동 열기 실패). 잠시 후 자동 재시도 예정 (로그: $LOG_PATH) : ${DASHBOARD_PATH}" >&3
      return 0
    fi
    _record_error 6 "open_finder_reveal"

    _log "WARN: attempt ${attempt} failed"
    # Respect the global timeout budget.
    local sleep_s
    sleep_s=$(( attempt * 2 ))
    now_epoch="$(date +%s)"
    time_left=$(( deadline_epoch - now_epoch ))
    if (( time_left <= 0 )); then
      break
    fi
    if (( sleep_s > time_left )); then
      sleep_s=$time_left
    fi
    if (( this_conn_invalid == 1 && sleep_s < SLEEP_ON_CONN_INVALID_SECS )); then
      sleep_s=$SLEEP_ON_CONN_INVALID_SECS
      if (( sleep_s > time_left )); then
        sleep_s=$time_left
      fi
    fi
    sleep "$sleep_s"
    attempt=$(( attempt + 1 ))
  done

  _log "ERROR: all methods failed"
  local last_snip
  last_snip="${BEST_OUT//$'\n'/ }"
  last_snip="${last_snip:0:180}"
  local hint=""
  if [[ "$BEST_OUT" == *"hiservices-xpcservice"* || "$BEST_OUT" == *"Connection invalid"* || "$BEST_OUT" == *"Connection Invalid"* ]]; then
    hint=" | hint: macOS AppleScript/GUI 서비스가 일시적으로 불안정합니다. 화면 잠금 해제 상태에서 다시 실행하거나, Atlas를 먼저 수동으로 1회 실행한 뒤 재시도하세요."

    _schedule_deferred_retry
    echo "DEFER: Atlas 자동 열기 실패(일시적) -> 백그라운드 재시도 예약됨 (로그: $LOG_PATH) | best_error(${BEST_LABEL}): ${last_snip}${hint}" >&3
    return 0
  fi

  echo "FAIL: could not open in Atlas (see $LOG_PATH) | best_error(${BEST_LABEL}): ${last_snip}${hint}" >&3
  return 1
}

main "$@"
