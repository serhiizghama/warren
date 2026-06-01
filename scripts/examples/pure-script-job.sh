#!/usr/bin/env bash
# Type A cron job — pure script, NO LLM. Does deterministic work and notifies Telegram
# directly. Use this whenever an agent isn't needed (scrape an API, check a status,
# compute a metric). Cheapest, simplest, most reliable. Cron example: 0 12 * * *
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

WARREN_ROOT="/abs/path/to/warren"
CREDS="$WARREN_ROOT/config/credentials/telegram-bot.md"

# --- do your deterministic work here ---
RESULT="example: 3 items need attention"

# --- notify Telegram directly ---
if [ -f "$CREDS" ]; then
  TOKEN=$(grep '^token:'   "$CREDS" | awk '{print $2}')
  CHAT=$(grep  '^chat_id:' "$CREDS" | awk '{print $2}')
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=${RESULT}" >/dev/null
fi
