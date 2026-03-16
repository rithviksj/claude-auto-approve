# claude-auto-approve

Auto-approves Claude Code confirmation prompts so you can walk away from long unattended sessions.

Claude Code occasionally pauses with:
```
Do you want to proceed?
❯ 1. Yes
  2. No
```

This tool watches your iTerm2 sessions and presses Enter the moment that prompt appears.

## How it works

- Polls **all** iTerm2 sessions every 3 seconds via AppleScript (windows, tabs, split panes)
- Reads only the last ~800 characters of each session (avoids false positives from scroll history)
- Approves **every session** with a prompt in a single pass — works with multiple simultaneous sessions
- Injects a newline directly into the session via iTerm2's native input API
- Runs as a background daemon with a PID file

## Requirements

- macOS
- iTerm2
- Claude Code CLI

## Usage

```bash
# Start
./claude-auto-approve.sh

# Check status
./claude-auto-approve.sh --status

# Stop
./claude-auto-approve.sh --stop
```

Logs to `/tmp/claude-auto-approve.log`:
```
[2026-03-15 19:54:22] Started (PID 14553, checking every 3s)
[2026-03-15 20:02:17] Approved 1 session(s)
[2026-03-15 20:02:27] Approved 2 session(s)   ← multiple sessions at once
```

## Installation

```bash
git clone https://github.com/rithviksj/claude-auto-approve
cd claude-auto-approve
chmod +x claude-auto-approve.sh

# Optional: add to PATH
ln -s "$PWD/claude-auto-approve.sh" /usr/local/bin/claude-auto-approve
```

## Notes

- Works across all windows, tabs, and split panes simultaneously
- Safe alongside interactive Claude sessions — only fires on the exact prompt text
- If two sessions hit a prompt at the same time, both get approved in the same cycle
- If iTerm2 isn't running, backs off to 10s polling and logs the error
- **Does not use TIOCSTI** (blocked on modern macOS) — uses iTerm2's native AppleScript input injection instead
- Writing directly to the TTY device (`/dev/ttys*`) does **not** work — it writes to terminal output, not the input queue. AppleScript `write text` is the correct approach.

## Why not `--dangerously-skip-permissions`?

Sometimes you want Claude to ask before running multi-line or destructive bash commands, but you trust it enough to auto-approve. This gives you that middle ground — Claude still shows you what it's about to do, it just doesn't wait for you.
