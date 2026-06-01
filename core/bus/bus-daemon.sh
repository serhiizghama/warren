#!/usr/bin/env bash
# warren bus — push daemon. Watches every inbox; when a new message lands, pushes
# /inbox into that agent's tmux session if it's idle (push-based delivery).
#
# Launched by restart-agents.sh as its own tmux session 'bd'.
# Watcher: fswatch (macOS) or inotifywait (Linux, from inotify-tools).

SELF="$(cd "$(dirname "$0")" && pwd)"
WARREN_ROOT="$(cd "$SELF/../.." && pwd)"
. "$WARREN_ROOT/core/lib/warren.sh"

LOG="$VAULT_PATH/bus/daemon.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# agent inbox folder name -> tmux key (from agents.conf; folder = lowercased name)
key_for_agent() {
  awk -v a="$1" 'tolower($2)==a && $1!~/^#/ {print $1; exit}' "$AGENTS_CONF"
}

push_agent() {
  agent="$1"; file="$2"
  sess="$(key_for_agent "$agent")"
  [ -z "$sess" ] && { log "WARN: unknown agent '$agent', skip"; return; }
  tmux has-session -t "$sess" 2>/dev/null || { log "WARN: session '$sess' ($agent) down — queued: $(basename "$file")"; return; }

  # Busy detection: spinners mean the agent is mid-task; skip (hook picks it up later).
  pane=$(tmux capture-pane -t "$sess:0" -p 2>/dev/null | tail -8)
  if printf '%s' "$pane" | grep -qE 'Thinking|Sublimating|Running|⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏'; then
    log "SKIP: $agent ($sess) busy"; return
  fi
  log "→ push /inbox to $agent ($sess:0): $(basename "$file")"
  tmux send-keys -t "$sess:0" "/inbox" Enter
}

watch_stream() {
  if command -v fswatch >/dev/null 2>&1; then
    fswatch --event Created -r --include '\.md$' --exclude '\.gitkeep' "$BUS_TO"
  elif command -v inotifywait >/dev/null 2>&1; then
    inotifywait -m -r -e create -e moved_to --format '%w%f' "$BUS_TO" 2>/dev/null
  else
    log "FATAL: no file watcher. Install fswatch (macOS) or inotify-tools (Linux)."; exit 1
  fi
}

log "========================================"
log "Bus daemon started ($(warren_os)). Watching $BUS_TO"
log "========================================"

watch_stream | while read -r filepath; do
  fn=$(basename "$filepath")
  case "$fn" in *.md) : ;; *) continue ;; esac
  [ "$fn" = ".gitkeep" ] && continue
  agent=$(printf '%s' "$filepath" | sed "s|$BUS_TO/||" | cut -d'/' -f1)
  log "NEW MSG for '$agent': $fn"
  push_agent "$agent" "$filepath"
done
