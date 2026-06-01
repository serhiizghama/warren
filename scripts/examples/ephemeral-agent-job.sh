#!/usr/bin/env bash
# Type B2 cron job — wake an LLM for on-demand work WITHOUT the metered API.
# Spins up a temporary tmux session running `claude`, sends a prompt that ends by
# touching a sentinel file, polls for it with a hard timeout, then kills the session.
# This is how warren runs scheduled agent work on a subscription. Never `claude -p`.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

WARREN_ROOT="/abs/path/to/warren"
. "$WARREN_ROOT/warren.config" 2>/dev/null
: "${MODEL:=sonnet[1m]}"
WORKDIR="$VAULT_PATH/SomeDomain"
TIMEOUT=1800

SESSION="job_cron_$(date +%s)"
DONE="/tmp/${SESSION}.done"
LOCK="$WARREN_ROOT/.${SESSION%_*}.lock"

[ -f "$LOCK" ] && exit 0          # don't overlap runs
touch "$LOCK"
trap "rm -f '$LOCK' '$DONE'; tmux kill-session -t '$SESSION' 2>/dev/null" EXIT

# (optional Phase 1: pure-python data collection here, before waking the agent)

tmux new-session -d -s "$SESSION" -c "$WORKDIR" \
  "claude --dangerously-skip-permissions --model '$MODEL' --name 'JobAgent'"
sleep 12   # let claude load

PROMPT="Read CLAUDE.md and do <the scheduled job>. Work autonomously. \
When fully done, run as the LAST command: touch ${DONE}"
tmux send-keys -t "$SESSION:0" "$PROMPT"
sleep 0.5
tmux send-keys -t "$SESSION:0" Enter

ELAPSED=0
while [ ! -f "$DONE" ] && [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  sleep 30; ELAPSED=$((ELAPSED + 30))
done

if [ ! -f "$DONE" ]; then
  CREDS="$WARREN_ROOT/config/credentials/telegram-bot.md"
  if [ -f "$CREDS" ]; then
    TOKEN=$(grep '^token:' "$CREDS" | awk '{print $2}')
    CHAT=$(grep '^chat_id:' "$CREDS" | awk '{print $2}')
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${CHAT}" \
      --data-urlencode "text=⚠️ ${SESSION} timed out after ${TIMEOUT}s" >/dev/null
  fi
fi
# EXIT trap kills the session and cleans up.
