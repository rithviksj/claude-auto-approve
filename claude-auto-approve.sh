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
FILTERFILE="/tmp/claude-auto-approve-filter.ttys"  # pipe-delimited ttys, empty = all
INTERVAL=3
PROMPT_TEXT="1. Yes"
TAIL_CHARS=3000  # enough to capture prompt even after long diffs

# ── helpers ────────────────────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

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
  rm -f "$FILTERFILE"
  exit 0
}

list_sessions() {
  local raw
  raw=$(osascript << 'ASCRIPT' 2>/dev/null
tell application "iTerm2"
  set output to ""
  set idx to 1
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set output to output & idx & "|" & (tty of s) & "|" & (name of s) & "
"
        set idx to idx + 1
      end repeat
    end repeat
  end repeat
  return output
end tell
ASCRIPT
)
  if [[ -z "$raw" ]]; then
    echo "No iTerm2 sessions found."
    return
  fi
  printf "\n%-4s %-14s %-35s %s\n" "#" "TTY" "Session Name" "Doing"
  printf "%-4s %-14s %-35s %s\n" "----" "--------------" "-----------------------------------" "------------------------------"
  while IFS='|' read -r idx tty name; do
    [[ -z "$idx" ]] && continue
    local short_tty="${tty#/dev/}"
    local doing
    doing=$(ps -t "$short_tty" -o args= 2>/dev/null \
      | grep -Ev '^\s*(-bash|-zsh|bash|zsh|login|ps |grep)' \
      | head -1 \
      | sed 's|.*/||; s/ .*$//' \
      | cut -c1-30)
    [[ -z "$doing" ]] && doing="idle"
    printf "%-4s %-14s %-35s %s\n" "$idx" "$tty" "$name" "$doing"
  done <<< "$raw"
  echo ""
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
  local allowed_ttys=""
  [[ -f "$FILTERFILE" ]] && allowed_ttys=$(cat "$FILTERFILE")
  local result
  result=$(osascript << ASCRIPT 2>/dev/null
tell application "iTerm2"
  set approvedCount to 0
  set allowedTtys to "$allowed_ttys"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set sessionTty to tty of s
        if allowedTtys is "" or allowedTtys contains ("|" & sessionTty & "|") then
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
)
  echo "${result:-NONE}"
}

# Scan sessions belonging to a specific iTerm2 PID by briefly raising its window
check_and_approve_pid() {
  local target_pid="$1"
  local allowed_ttys=""
  [[ -f "$FILTERFILE" ]] && allowed_ttys=$(cat "$FILTERFILE")
  osascript << ASCRIPT 2>/dev/null
tell application "System Events"
  set targetProcs to every process whose unix id is $target_pid
  if (count of targetProcs) > 0 then
    set targetProc to item 1 of targetProcs
    if (count of windows of targetProc) > 0 then
      perform action "AXRaise" of window 1 of targetProc
    end if
  end if
end tell
delay 0.1
tell application "iTerm2"
  set approvedCount to 0
  set allowedTtys to "$allowed_ttys"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set sessionTty to tty of s
        if allowedTtys is "" or allowedTtys contains ("|" & sessionTty & "|") then
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

get_iterm2_ttys() {
  osascript << 'ASCRIPT' 2>/dev/null
tell application "iTerm2"
  set ttyList to ""
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set ttyList to ttyList & (tty of s) & "|"
      end repeat
    end repeat
  end repeat
  return ttyList
end tell
ASCRIPT
}

check_stuck_sessions() {
  local iterm_ttys
  iterm_ttys=$(get_iterm2_ttys)
  local stuck=0
  while IFS= read -r line; do
    local tty
    tty="/dev/$(echo "$line" | awk '{print $7}')"
    if [[ -n "$tty" && "$tty" != "/dev/" && "$iterm_ttys" != *"$tty"* ]]; then
      stuck=$((stuck + 1))
    fi
  done < <(ps aux | awk '/claude$/ && !/grep/ && !/auto-approve/ {print}')
  if [[ $stuck -gt 0 ]]; then
    log "WARNING: $stuck Claude session(s) in buried/windowless state — prompts invisible, auto-approve cannot reach them. Reopen iTerm2 windows for those sessions."
  fi
}

watch_loop() {
  local mode="all sessions"
  [[ -f "$FILTERFILE" ]] && mode="filtered: $(cat "$FILTERFILE")"
  log "Started (PID $$, checking every ${INTERVAL}s, mode: $mode)"
  echo $$ > "$PIDFILE"

  trap 'rm -f "$PIDFILE"; log "Stopped."; exit 0' INT TERM

  # Detect secondary iTerm2 instances (e.g. spawned by `iTerm2 --version`)
  # Primary instance is the one launched by launchd (ppid=1)
  get_secondary_iterm_pids() {
    ps aux | awk '/\/iTerm2$|\/iTerm2 / && !/grep/' | while read -r line; do
      pid=$(echo "$line" | awk '{print $2}')
      ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
      if [[ "$ppid" != "1" ]]; then
        echo "$pid"
      fi
    done
  }

  local stuck_check_counter=0
  while true; do
    result=$(check_and_approve || echo "ERROR")
    if [[ "$result" == APPROVED:* ]]; then
      count="${result#APPROVED:}"
      log "Approved $count session(s)"
      sleep 5
    elif [[ "$result" == "ERROR" ]]; then
      log "AppleScript error (iTerm2 not running?)"
      sleep 10
    else
      # Also check any secondary iTerm2 instances
      while IFS= read -r sec_pid; do
        [[ -z "$sec_pid" ]] && continue
        sec_result=$(check_and_approve_pid "$sec_pid" 2>/dev/null || true)
        if [[ "$sec_result" == APPROVED:* ]]; then
          count="${sec_result#APPROVED:}"
          log "Approved $count session(s) in secondary iTerm2 (PID $sec_pid)"
          sleep 5
          break
        fi
      done < <(get_secondary_iterm_pids)
      sleep "$INTERVAL"
    fi
    # Check for stuck sessions every ~5 minutes (100 cycles × 3s)
    stuck_check_counter=$((stuck_check_counter + 1))
    if [[ $stuck_check_counter -ge 100 ]]; then
      stuck_check_counter=0
      check_stuck_sessions
    fi
  done
}

# ── main ───────────────────────────────────────────────────────────────────────

case "${1:-}" in
  --stop)   stop ;;
  --status) status ;;
  --list-sessions) list_sessions; exit 0 ;;
  --help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
    exit 0
    ;;
  --sessions)
    # --sessions /dev/ttys001,/dev/ttys003
    if [[ -z "${2:-}" ]]; then
      echo "Usage: $0 --sessions /dev/ttys001,/dev/ttys003"
      exit 1
    fi
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "Already running (PID $(cat "$PIDFILE")). Use --stop first."
      exit 1
    fi
    # Build pipe-delimited filter: |/dev/ttys001|/dev/ttys003|
    filter="|$(echo "$2" | tr ',' '|')|"
    echo "$filter" > "$FILTERFILE"
    echo "Filter set: $2"
    nohup bash "$0" --_loop >> "$LOGFILE" 2>&1 &
    echo "Started (PID $!) for selected sessions. Log: $LOGFILE"
    echo $! > "$PIDFILE"
    ;;
  "")
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "Already running (PID $(cat "$PIDFILE")). Use --stop first."
      exit 1
    fi
    rm -f "$FILTERFILE"  # no filter = approve all sessions
    nohup bash "$0" --_loop >> "$LOGFILE" 2>&1 &
    echo "Started (PID $!) for all sessions. Log: $LOGFILE"
    echo $! > "$PIDFILE"
    ;;
  --_loop) watch_loop ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
esac
