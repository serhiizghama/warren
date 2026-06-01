# Quickstart

```bash
git clone https://github.com/serhiizghama/warren
cd warren
claude
```
Then tell the agent:
> **read BOOTSTRAP.md and set up my warren**

It interviews you (orchestrator name, domains, Telegram, schedule), checks dependencies,
scaffolds your private `vault/`, wires the inbox hooks, and launches the network.

## What gets created
- `warren.config` + `agents.conf` at the repo root (git-ignored) — your settings & roster.
- `vault/` (git-ignored) — your knowledge base:
  - orchestrator `CLAUDE.md` + `index.md` + `log.md` at the root,
  - one folder per domain agent (each with `CLAUDE.md`, `index.md`, `log.md`, `MEMORY.md`,
    `raw/`, `wiki/`),
  - `vault/bus/` — the message bus inboxes,
  - per-agent `.claude/settings.json` (inbox hook) and `/inbox` command.

## Daily use
- **Talk to an agent:** `tmux attach -t <key>` (or use Remote Control on your phone).
- **Drop a source:** put a file in a domain's `raw/` and tell the agent to ingest it.
- **Reboot everything:** `bash core/restart-agents.sh`.
- **Update the engine:** `git pull` (your `vault/` is untouched).

## Optional: version your knowledge
The `vault/` is ignored by *this* repo. If you want history of your own knowledge base:
```bash
cd vault && git init   # your private repo, separate from the engine
```
