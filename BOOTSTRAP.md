# BOOTSTRAP — set up a warren

> **You are the setup agent.** A user just started `claude` in the warren repo and asked you
> to set up their warren. Follow these steps **in order**. Interview the user, then scaffold
> their network. Be concise. Confirm at the marked checkpoints. Never commit credentials or
> the `vault/` folder. Everything you generate from answers (config + vault) stays local.

Throughout: `<repo>` = this repository's absolute path (run `pwd`). The engine is in `core/`,
the templates in `templates/`. The user's data will live in `vault/` (git-ignored).

---

## Step 0 — Dependency check

Check each command and report a table of ✓/✗. Do **not** auto-install (needs the user's
package manager) — print the exact install hint for anything missing, then continue.

| Tool | Needed for | macOS | Linux (Debian/Ubuntu) |
|------|-----------|-------|----------------------|
| `claude` | the agents | — (already running) | — |
| `tmux` | agent sessions | `brew install tmux` | `apt install tmux` |
| `git` | version history | preinstalled | `apt install git` |
| `jq` | inbox hook JSON | `brew install jq` | `apt install jq` |
| `curl` | Telegram | preinstalled | `apt install curl` |
| file watcher | bus daemon | `brew install fswatch` | `apt install inotify-tools` |

Detect OS with `uname -s` (Darwin = macOS, Linux = Linux). The watcher differs: macOS uses
`fswatch`, Linux uses `inotifywait`. The engine auto-detects whichever is present.

---

## Step 1 — Interview

Ask these, one topic at a time. Offer the defaults so the user can just accept.

1. **Orchestrator name.** The router agent. (Examples: Gamma, Atlas, Nexus, Jarvis.) The user
   picks anything. Default tmux key = first letter, lowercase.
2. **Domains.** Ask which domains they want. For each domain collect:
   - **Name** (PascalCase, e.g. `Finance`) → its folder and `--name`.
   - **One-line description** of the domain.
   - **Scope** — a few bullet examples of what belongs there.
   - **Proactive checks** — 1-2 things the agent should check on startup (e.g. "overdue
     tasks", "spend vs budget"). If unsure, use a sensible default.
   - Auto-assign a unique **tmux key** (first free letter of the name; resolve collisions).
   Suggest a starter set if they're unsure: Tasks, Journal, Finance, Health.
3. **Telegram notifications?** (yes/no) — if yes, you'll guide credential setup in Step 4.
4. **Vault path.** Default `<repo>/vault`. (Keeping it inside the repo is fine — it's
   git-ignored. A custom absolute path also works.)
5. **Model.** Default `sonnet[1m]`.

Echo back a summary of the roster and **confirm before generating** (checkpoint ✅).

---

## Step 2 — Generate config (repo root, git-ignored)

Write **`<repo>/warren.config`** from `config/warren.config.example`, filling the answers:
```
VAULT_PATH="<chosen path>"
MODEL="<chosen model>"
TELEGRAM_ENABLED="<1 or 0>"
```

Write **`<repo>/agents.conf`** from `config/agents.conf.example` — one line per agent,
orchestrator first with dir `.`:
```
# key  name        dir
<k>    <Orch>      .
<k>    <Domain1>   <Domain1>
<k>    <Domain2>   <Domain2>
```

Both files are git-ignored (see `.gitignore`) — never commit them.

---

## Step 3 — Scaffold the vault

Create the vault and copy the shared protocol:
```
mkdir -p <VAULT>/bus/sent
cp core/WIKI_PROTOCOL.md <VAULT>/WIKI_PROTOCOL.md
```

**Orchestrator (vault root):** render `templates/orchestrator.CLAUDE.md.tmpl` → `<VAULT>/CLAUDE.md`.
Replace placeholders:
- `{{ORCH_NAME}}`, `{{ORCH_LC}}` (lowercase), `{{DOMAIN_COUNT}}`.
- `{{ROUTING_TABLE}}` → build a markdown list, one row per domain:
  `- **<scope summary>** → "Switch to the \`<Domain>/\` folder and launch the <Domain> agent."`

Also at vault root, render: `index.md` and `log.md` and `MEMORY.md` from their templates
(use `{{AGENT_NAME}}` = orchestrator name, `{{DATE}}` = today).

**Per-domain folders:** for each domain create
`<VAULT>/<Domain>/{raw,wiki}` and render:
- `templates/domain.CLAUDE.md.tmpl` → `<Domain>/CLAUDE.md`, replacing `{{AGENT_NAME}}`,
  `{{AGENT_LC}}`, `{{AGENT_TAGLINE}}` (a short role line), `{{DOMAIN_DESC}}`, `{{DOMAIN_SCOPE}}`
  (the bullet examples), `{{DOMAIN_CHECKS}}` (the proactive checks), `{{ORCH_NAME}}`.
- `index.md`, `log.md`, `MEMORY.md` from templates.

**Bus inboxes:** for **every** agent (orchestrator + domains) create
`<VAULT>/bus/to/<agent-lc>/.gitkeep`. Create `<VAULT>/bus/sent/.gitkeep`.

**Hooks + /inbox command:** for **every** agent folder (orchestrator = vault root,
domains = their folder) create:
- `<dir>/.claude/settings.json` from `templates/settings.json.tmpl`, replacing
  `{{WARREN_ROOT}}` = `<repo>` (absolute) and `{{AGENT_LC}}` = the agent's lowercased name.
- `<dir>/.claude/commands/inbox.md` from `templates/inbox-command.md`, replacing `{{AGENT_LC}}`.

---

## Step 4 — Credentials (only if Telegram = yes)

```
cp config/credentials/telegram-bot.example.md config/credentials/telegram-bot.md
```
Tell the user to create a bot via **@BotFather**, then edit `telegram-bot.md` and paste their
`token:` and `chat_id:`. (Get chat_id from `https://api.telegram.org/bot<TOKEN>/getUpdates`
after messaging the bot.) This file is git-ignored — **never commit it, never print the token
back in chat.**

---

## Step 5 — Optional: scheduled jobs

Ask if they want any scheduled agents (e.g. a daily digest). If yes, point them at
`scripts/` (templates for: a daily digest via the bus, a pure-script job, and an
ephemeral-tmux agent job). Help them add crontab lines. Remind them:
- Every cron script must `export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"`
  (Linux: `/usr/local/bin` instead of `/opt/homebrew/bin`).
- Use absolute paths. Never use `claude -p` (that's the metered API) — use the bus or an
  ephemeral tmux session with a sentinel file (see `scripts/examples/`).

---

## Step 6 — Launch & verify

```
bash core/restart-agents.sh
```
Then verify:
```
tmux ls                                   # all sessions + 'bd' (bus daemon) alive
tmux capture-pane -t <orch-key>:0 -p | tail   # orchestrator warmed up?
```
Tell the user to attach with `tmux attach -t <key>`, and to connect Remote Control in the
Claude mobile app / claude.ai (each agent shows up by its full name).

---

## Step 7 — Final report
Print: orchestrator name, the domain roster, where the vault lives, Telegram on/off, and the
one command to reboot everything later (`bash core/restart-agents.sh`). Suggest the user
`cd <VAULT> && git init` if they want version history of their knowledge base (separate from
this engine repo).

Done. The warren is alive.
