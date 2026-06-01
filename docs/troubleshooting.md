# Troubleshooting

## tmux send-keys goes to the wrong session
Always target `<key>:0` (session:window), **never** bare `<key>`. From inside a tmux session,
a bare target resolves to the *current* client, not the intended session. The engine already
uses `:0` everywhere — follow the same rule in your own scripts.

## A prompt submits empty or truncated
When sending a prompt with `send-keys`, send the **text**, `sleep 1`, then send `Enter`
**separately**. Concatenating text + Enter in one call lets Enter race ahead of the text.

## Agent boots "cold" (doesn't know who it is)
That's what the warm-up prompt in `restart-agents.sh` fixes — it tells the freshly booted
agent to read its files and run its proactive startup. If you add startup files, update the
warm-up file list in `restart-agents.sh`.

## Bus messages aren't delivered automatically
- Is the bus daemon running? `tmux has-session -t bd`. If not: it starts at the end of
  `restart-agents.sh`.
- No file watcher installed? Install `fswatch` (macOS) or `inotify-tools` (Linux).
- The agent was busy when the message arrived — that's fine, the `UserPromptSubmit` hook will
  surface it on the next prompt.

## The inbox hook does nothing
- `jq` installed? The hook emits JSON via `jq`.
- Is `<agent-dir>/.claude/settings.json` pointing `check-inbox.sh` at the **correct lowercased
  agent name**, with an **absolute** path to the script?

## Cron job silently does nothing
- PATH: add the `export PATH=...` line (see [cron.md](cron.md)).
- Absolute paths only — cron has no working directory.
- Check the job's log file (the `>> ... 2>&1` redirect in your crontab line).

## Telegram notifications don't arrive
- `TELEGRAM_ENABLED="1"` in `warren.config`?
- `config/credentials/telegram-bot.md` exists with real `token:` and `chat_id:`?
- Test by hand:
  `curl "https://api.telegram.org/bot<TOKEN>/getMe"` should return your bot's info.

## Sessions died after a reboot
Just re-run `bash core/restart-agents.sh`. It kills any stale sessions and rebuilds the whole
network plus the bus daemon.
