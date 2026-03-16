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

- Polls iTerm2 sessions every 3 seconds via AppleScript
- Reads only the last ~800 characters of terminal output (avoids false positives from scroll history)
- Injects a newline directly into the session when a prompt is detected
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
[2026-03-15 20:02:17] Prompt detected — approved
[2026-03-15 20:02:27] Prompt detected — approved
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

- Targets any iTerm2 session containing the prompt — works with split panes
- Safe to run alongside interactive Claude sessions (only fires on the prompt text)
- If iTerm2 isn't running, backs off to 10s polling and logs the error
- **Does not use TIOCSTI** (blocked on modern macOS) — uses iTerm2's native AppleScript input injection instead

## Why not `--dangerously-skip-permissions`?

Sometimes you want Claude to ask before running multi-line or destructive bash commands, but you trust it enough to auto-approve. This gives you that middle ground — Claude still shows you what it's about to do, it just doesn't wait for you.
