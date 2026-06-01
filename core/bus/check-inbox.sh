#!/usr/bin/env bash
# warren bus — UserPromptSubmit hook. Injects "you have N messages" context.
#
# Wired per-agent in <agent-dir>/.claude/settings.json:
#   "command": "/abs/path/core/bus/check-inbox.sh <agent-name>"
#
# Reads stdin (Claude Code hook JSON) but ignores it. Emits hook JSON only when
# the agent's inbox has unread messages.

AGENT="$1"
[ -z "$AGENT" ] && exit 0

SELF="$(cd "$(dirname "$0")" && pwd)"
WARREN_ROOT="$(cd "$SELF/../.." && pwd)"
. "$WARREN_ROOT/core/lib/warren.sh"

INBOX="$BUS_TO/$(warren_lc "$AGENT")"
[ ! -d "$INBOX" ] && exit 0

COUNT=$(find "$INBOX" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -eq 0 ] && exit 0

LIST=$(find "$INBOX" -maxdepth 1 -type f -name "*.md" 2>/dev/null | xargs -n1 basename | sort)

CONTEXT="📬 You have ${COUNT} unread message(s) in your inbox (vault/bus/to/$(warren_lc "$AGENT")/):
${LIST}

ORDER OF OPERATIONS:
1. First answer the user's request as usual.
2. Then read and process each inbox message yourself — no confirmation needed.
   A message from another agent = an action it expects you to take.
3. After processing, append a log.md entry, then move the file to vault/bus/sent/
   with a 'done__' prefix (keep the exact original filename).
4. End with a 1-2 line summary of what was processed.

Ask first ONLY if a message: requires a destructive action, conflicts with what the
user just asked, or is genuinely ambiguous."

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: $ctx }
}'
exit 0
