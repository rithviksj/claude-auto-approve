# claude-watcher

Watches your iTerm2 sessions and auto-approves Claude Code confirmation prompts — so you can walk away from long unattended sessions without babysitting them.

Claude Code occasionally pauses with:
```
Do you want to make this edit to file.py?
 ❯ 1. Yes
   2. Yes, allow all edits during this session (shift+tab)
   3. No
```
claude-watcher detects this within 3 seconds and presses Enter for you.

## Features

- **All-session mode** — approves every iTerm2 session simultaneously (default)
- **Session-specific mode** — target one or more sessions by TTY, leave others untouched
- **Session picker** — lists all open sessions with TTY, name, and what's currently running so you can pick intelligently
- **Timed stop with Slack DM** — set a stop time; get a DM when it disables
- **Buried session detection** — warns you when a Claude process exists but has no visible window (prompt is unreachable)
- **Secondary iTerm2 instance support** — handles edge cases where a rogue iTerm2 subprocess intercepts AppleScript routing
- Runs as a background daemon with PID file, no terminal kept open

## Requirements

- macOS
- iTerm2
- Claude Code CLI

## Usage

```bash
# Start — approve all sessions
./claude-auto-approve.sh

# List current sessions (TTY + name + what's running)
./claude-auto-approve.sh --list-sessions

# Start — approve specific sessions only
./claude-auto-approve.sh --sessions /dev/ttys003,/dev/ttys005

# Check status
./claude-auto-approve.sh --status

# Stop
./claude-auto-approve.sh --stop
```

### Session picker example

```
$ ./claude-auto-approve.sh --list-sessions

#    TTY            Session Name                        Doing
---- -------------- ----------------------------------- ------------------------------
1    /dev/ttys001   rithvik-iterm-theme-light (ping)    ping
2    /dev/ttys002   rithvik-iterm-theme-dark             caffeinate
3    /dev/ttys005   rithvik-iterm-theme-light (mcp)     claude
4    /dev/ttys007   rithvik-iterm-theme-light (ssh)     ssh

# Approve only the Claude session:
./claude-auto-approve.sh --sessions /dev/ttys005
```

### Timed stop with Slack notification

Schedule a stop via launchd and notify yourself when it fires:

```bash
# stop-and-notify.sh
./claude-auto-approve.sh --stop
~/.mcp/send-slack-dm.sh YOUR_SLACK_USER_ID "claude-watcher has been disabled"
```

Load it via `launchd` with a `StartCalendarInterval` for the desired stop time.

## How it works

- Polls iTerm2 sessions every 3 seconds via AppleScript
- Reads the last 3000 characters of each session (captures prompts even after long diffs)
- Checks session TTY against the filter list (if set) before scanning content
- Injects a newline via iTerm2's native `write text` AppleScript API (not TIOCSTI — blocked on modern macOS)
- Detects and warns about Claude processes running in buried/windowless sessions

## Logs

```
[2026-03-16 09:00:01] Started (PID 14553, checking every 3s, mode: all sessions)
[2026-03-16 09:00:07] Approved 1 session(s)
[2026-03-16 09:00:17] Approved 2 session(s)
[2026-03-16 09:15:00] WARNING: 1 Claude session(s) in buried/windowless state
```

```bash
tail -f /tmp/claude-auto-approve.log
```

## Installation

```bash
git clone https://github.com/rithviksj/claude-watcher
cd claude-watcher
chmod +x claude-auto-approve.sh

# Optional: add to PATH
ln -s "$PWD/claude-auto-approve.sh" /usr/local/bin/claude-watcher
```

## Why not `--dangerously-skip-permissions`?

Sometimes you want Claude to ask before running destructive commands, but trust it enough to auto-approve. This gives you that middle ground — Claude still shows you what it's about to do, it just doesn't wait for you to be at the keyboard.

## Notes

- Works across all windows, tabs, and split panes
- If two sessions hit a prompt simultaneously, both are approved in the same cycle
- If iTerm2 isn't running, backs off to 10s polling and logs the error
- Writing directly to `/dev/ttys*` does **not** work for input injection on macOS — AppleScript `write text` is the correct approach
