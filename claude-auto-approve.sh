#!/usr/bin/env bash
# claude-auto-approve
# Watches iTerm2 sessions for Claude Code confirmation prompts and auto-approves them.
# Useful when running long Claude Code sessions unattended.
#
# Usage:
#   ./claude-auto-approve.sh           # start (default: check every 3s)
#   ./claude-auto-approve.sh --stop    # kill running instance
#   ./claude-auto-approve.sh --status  # check if running
#
# Requires: iTerm2, macOS

set -euo pipefail

PIDFILE="/tmp/claude-auto-approve.pid"
LOGFILE="/tmp/claude-auto-approve.log"
INTERVAL=3
PROMPT_TEXT="Do you want to proceed"
TAIL_CHARS=800   # only check recent terminal content to avoid stale matches

# ── helpers ────────────────────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }

stop() {
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid=$(cat "$PIDFILE")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" && log "Stopped (PID $pid)"
    else
      log "Process $pid not found — cleaning up"
    fi
    rm -f "$PIDFILE"
  else
    echo "Not running."
  fi
  exit 0
}

status() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Running (PID $(cat "$PIDFILE"))"
    echo "Log: $LOGFILE"
  else
    echo "Not running."
  fi
  exit 0
}

check_and_approve() {
  osascript << ASCRIPT
tell application "iTerm2"
  set approvedCount to 0
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set c to contents of s
        set cLen to length of c
        if cLen > $TAIL_CHARS then
          set c to text (cLen - $TAIL_CHARS) thru cLen of c
        end if
        if c contains "$PROMPT_TEXT" then
          tell s
            write text ""
          end tell
          set approvedCount to approvedCount + 1
        end if
      end repeat
    end repeat
  end repeat
  if approvedCount > 0 then
    return "APPROVED:" & approvedCount
  end if
  return "NONE"
end tell
ASCRIPT
}

watch_loop() {
  log "Started (PID $$, checking every ${INTERVAL}s)"
  echo $$ > "$PIDFILE"

  trap 'rm -f "$PIDFILE"; log "Stopped."; exit 0' INT TERM

  while true; do
    result=$(check_and_approve 2>/dev/null || echo "ERROR")
    if [[ "$result" == APPROVED:* ]]; then
      count="${result#APPROVED:}"
      log "Approved $count session(s)"
      sleep 5   # back off after approving, give session time to advance
    elif [[ "$result" == "ERROR" ]]; then
      log "AppleScript error (iTerm2 not running?)"
      sleep 10
    else
      sleep "$INTERVAL"
    fi
  done
}

# ── main ───────────────────────────────────────────────────────────────────────

case "${1:-}" in
  --stop)   stop ;;
  --status) status ;;
  --help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
    exit 0
    ;;
  "")
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "Already running (PID $(cat "$PIDFILE")). Use --stop first."
      exit 1
    fi
    nohup bash "$0" --_loop >> "$LOGFILE" 2>&1 &
    echo "Started (PID $!). Log: $LOGFILE"
    echo $! > "$PIDFILE"
    ;;
  --_loop) watch_loop ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
esac
