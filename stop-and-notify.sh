#!/usr/bin/env bash
# Stop claude-auto-approve and DM Rithvik on Slack

/Users/rjavgal/rjavgal/claude-auto-approve/claude-auto-approve.sh --stop

/Users/rjavgal/.mcp/send-slack-dm.sh WCFP79CM6 "Auto approve has been disabled (9am stop)"
