#!/usr/bin/env bash
# warren bus — send a message to another agent's inbox.
#
#   send.sh --to <agent> --from <agent> --title "..." --body "..."
#   send.sh --to health --from finance --title "X" --body-file /tmp/msg.md
#
# Long/multi-line bodies: ALWAYS use --body-file, never a giant inline --body.
set -e

SELF="$(cd "$(dirname "$0")" && pwd)"
WARREN_ROOT="$(cd "$SELF/../.." && pwd)"
. "$WARREN_ROOT/core/lib/warren.sh"

TO=""; FROM=""; TITLE=""; BODY=""; BODY_FILE=""; PRIORITY="normal"
while [ $# -gt 0 ]; do case "$1" in
  --to)        TO="$2"; shift 2 ;;
  --from)      FROM="$2"; shift 2 ;;
  --title)     TITLE="$2"; shift 2 ;;
  --body)      BODY="$2"; shift 2 ;;
  --body-file) BODY_FILE="$2"; shift 2 ;;
  --priority)  PRIORITY="$2"; shift 2 ;;
  *) echo "Unknown arg: $1" >&2; exit 1 ;;
esac; done

[ -z "$TO" ]    && { echo "Missing --to"    >&2; exit 1; }
[ -z "$FROM" ]  && { echo "Missing --from"  >&2; exit 1; }
[ -z "$TITLE" ] && { echo "Missing --title" >&2; exit 1; }

INBOX="$BUS_TO/$(warren_lc "$TO")"
[ ! -d "$INBOX" ] && { echo "Inbox not found: $INBOX" >&2; exit 1; }
[ -n "$BODY_FILE" ] && { [ -f "$BODY_FILE" ] || { echo "Body file not found: $BODY_FILE" >&2; exit 1; }; BODY=$(cat "$BODY_FILE"); }

TS=$(date +%Y-%m-%dT%H-%M-%S)
SLUG=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-50)
# <to> is in the filename so messages to different agents never collide in sent/
FILE="$INBOX/${TS}__${FROM}__to-${TO}__${SLUG}.md"

cat > "$FILE" <<EOF
---
from: $FROM
to: $TO
created: $(date +%Y-%m-%dT%H:%M:%S%z)
priority: $PRIORITY
status: unread
---

# $TITLE

$BODY
EOF

echo "Sent: $FILE"

# Live bus notification to your phone (so you watch agents talk).
PREVIEW=$(printf '%s' "$BODY" | cut -c1-300)
notify_telegram "🚌 Bus: ${FROM} → ${TO}
📋 ${TITLE}

${PREVIEW}" &
