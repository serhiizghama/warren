# Scheduling — cron without the metered API

warren never uses `claude -p` (that's the API → pay per token). Scheduled work uses one of
three patterns, all of which run on your **subscription**.

## Three job types
- **Type A — pure script (no LLM).** Deterministic work + Telegram notify. Cheapest.
  See `scripts/examples/pure-script-job.sh`.
- **Type B1 — wake a running agent via the bus.** The cron script writes one bus message; the
  bus daemon pushes `/inbox` to the already-running agent. See `scripts/digest.sh.tmpl`.
- **Type B2 — ephemeral tmux + sentinel.** Spin up a temporary `claude` session, send a prompt
  ending in `touch <sentinel>`, poll for it with a timeout, kill the session. For on-demand
  work that doesn't need a permanent agent. See `scripts/examples/ephemeral-agent-job.sh`.

## Example crontab
```cron
# Daily digest 07:00 — Type B1
0 7  * * * /usr/bin/env bash /abs/warren/scripts/digest.sh        >> /abs/warren/vault/bus/digest.log 2>&1
# Status check 12:00 — Type A
0 12 * * * /usr/bin/env bash /abs/warren/scripts/examples/pure-script-job.sh
# Nightly job 03:00 — Type B2
0 3  * * * /usr/bin/env bash /abs/warren/scripts/examples/ephemeral-agent-job.sh
```

## Gotchas (these will bite you)
- **PATH:** cron has a minimal PATH. Start every script with
  `export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"`
  (macOS uses `/opt/homebrew/bin`; Linux uses `/usr/local/bin`).
- **Absolute paths everywhere** — cron has no working directory.
- **Long bus bodies → `--body-file`,** never a giant inline `--body`.
- **Lock file** for long jobs so runs don't overlap (see the B2 example).
- **Never `claude -p`.** Always the bus (B1) or ephemeral tmux + sentinel (B2).

## Linux: systemd timers (alternative to cron)
On a VPS you can use systemd timers instead of cron — same scripts, a `.service` + `.timer`
unit per job. Cron works fine too; pick whichever you prefer.
