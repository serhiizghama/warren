#!/usr/bin/env bash
# warren — (re)boot the whole agent network + bus daemon.
# Roster comes from agents.conf; settings from warren.config. No hand-editing.
#
#   bash core/restart-agents.sh        (or zsh)

SELF="$(cd "$(dirname "$0")" && pwd)"
WARREN_ROOT="$(cd "$SELF/.." && pwd)"
. "$WARREN_ROOT/core/lib/warren.sh"

BOOT_WAIT="${BOOT_WAIT:-10}"   # seconds to wait for claude to load
RC_WAIT="${RC_WAIT:-10}"       # seconds to wait for Remote Control

echo "→ Stopping bus daemon + agents..."
tmux kill-session -t bd 2>/dev/null
_kill() { tmux kill-session -t "$1" 2>/dev/null; }
warren_each_agent _kill

echo "→ Launching agents..."
_launch() {
  key="$1"; name="$2"; dir="$3"
  if [ "$dir" = "." ]; then wd="$VAULT_PATH"; else wd="$VAULT_PATH/$dir"; fi
  tmux new-session -d -s "$key" -c "$wd" \
    "claude --dangerously-skip-permissions --model '$MODEL' --name '$name'"
  echo "  ✓ $key ($name) — $wd"
}
warren_each_agent _launch

echo "→ Waiting ${BOOT_WAIT}s for Claude to load..."
sleep "$BOOT_WAIT"

echo "→ Activating Remote Control..."
_remote() {
  # ALWAYS target "$key:0" (session:window). Bare "$key" from inside a tmux
  # session resolves to the current client, not the target session.
  tmux send-keys -t "$1:0" "/remote-control $2" Enter
  echo "  ✓ $1 → /remote-control $2"
}
warren_each_agent _remote

echo "→ Waiting ${RC_WAIT}s for Remote Control..."
sleep "$RC_WAIT"

echo "→ Sending warm-up prompt..."
_warmup() {
  key="$1"; name="$2"; dir="$3"
  if [ "$dir" = "." ]; then
    files="CLAUDE.md, index.md, log.md, WIKI_PROTOCOL.md"
  else
    files="CLAUDE.md, index.md, log.md, ../WIKI_PROTOCOL.md"
  fi
  warm="Read these files: $files. Understand who you are, your domain status, recent events, and any open items. Introduce yourself in one line. Then IMMEDIATELY run the 'Proactive startup' protocol from your CLAUDE.md — process inbox, run key checks, print a final status line. Do not wait for a user command."
  # send text, pause, THEN Enter separately (Enter can race the text otherwise)
  tmux send-keys -t "$key:0" "$warm"
  sleep 1
  tmux send-keys -t "$key:0" Enter
  echo "  ✓ $key ($name) — warm-up sent"
}
warren_each_agent _warmup

echo "→ Starting bus daemon..."
tmux new-session -d -s bd -c "$WARREN_ROOT/core/bus" "bash bus-daemon.sh"
echo "  ✓ bd (bus daemon)"

echo ""
echo "✓ Network up."
tmux ls
