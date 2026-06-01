# Multi-Agent Knowledge Vault — Technical Architecture & Implementation Guide

> A self-hosted, local-first network of LLM agents (Claude Code) that collaboratively
> maintain a personal knowledge base ("Vault"). One orchestrator agent routes work to
> specialized domain agents. Agents run as long-lived terminal sessions, talk to each
> other over a file-based message bus, are reachable from a phone via Remote Control,
> push notifications to Telegram, and are driven on a schedule by cron.
>
> This document describes the **pattern and the mechanics** in full detail so it can be
> reproduced from scratch with Claude Code on macOS. All examples use generic placeholder
> agents (Finance, Health, Journal, …) — adapt them to your own domains.

---

## 0. TL;DR — What you are building

```
                        ┌─────────────────────────────────────────┐
                        │  YOU                                      │
                        │  • Terminal (tmux attach)                 │
                        │  • Phone / Browser (Remote Control)       │
                        │  • Telegram (push notifications)          │
                        └───────────────┬───────────────────────────┘
                                        │
                ┌───────────────────────┼───────────────────────┐
                │                       │                       │
        ┌───────▼───────┐      ┌────────▼────────┐     ┌────────▼────────┐
        │  ORCHESTRATOR │      │  DOMAIN AGENT   │ ... │  DOMAIN AGENT   │
        │  "Gamma"      │◄────►│  "Finance"      │     │  "Health"       │
        │  tmux: g      │ bus  │  tmux: f        │     │  tmux: h        │
        │  dir: /vault  │      │  dir: /Finance  │     │  dir: /Health   │
        └───────┬───────┘      └────────┬────────┘     └────────┬────────┘
                │                       │                       │
                └───────────────────────┼───────────────────────┘
                                        │
              ┌─────────────────────────▼─────────────────────────┐
              │  FILE-BASED BUS  (_System/bus/to/<agent>/*.md)     │
              │  + bus-daemon (fswatch → tmux send-keys "/inbox")  │
              └────────────────────────────────────────────────────┘
                                        ▲
                                        │ writes bus messages
              ┌─────────────────────────┴─────────────────────────┐
              │  CRON / launchd  → scripts → bus or ephemeral tmux │
              └────────────────────────────────────────────────────┘
```

Each agent is **one `claude` CLI process** running inside its own **tmux session**, with its
working directory set to a domain folder, and its personality defined by that folder's
`CLAUDE.md`. The whole Vault is **one git repository of markdown files**.

---

## 1. Core philosophy

This is an **LLM-maintained wiki**, not a RAG system. Instead of re-deriving knowledge from
raw documents on every query, the agents **incrementally build and maintain a persistent,
interlinked markdown knowledge base**. Three layers:

1. **Raw sources** (`raw/`) — immutable inputs you drop in. Agents read, never modify.
2. **The wiki** (`wiki/`) — agent-generated, agent-owned markdown pages. Cross-referenced
   with `[[wiki-links]]`. You read it; the agent writes it.
3. **The schema** (`CLAUDE.md`) — per-agent instructions: identity, domain rules, workflows.

The human curates sources, asks questions, and directs analysis. The LLM does all the
bookkeeping: summarizing, cross-referencing, filing, keeping the index current, flagging
contradictions. The wiki is a **compounding artifact** — it gets richer with every source.

**Single orchestrator + specialized domain agents.** A root agent ("Gamma") owns the global
structure and *routes* requests, but never does domain work itself — it delegates. Each
domain (finance, health, journaling, tasks, coding, …) is a separate folder with its own
agent, its own `CLAUDE.md`, and its own sub-wiki.

---

## 2. Prerequisites & tech stack

All local, all on macOS (adaptable to Linux). No servers, no databases, no network services.

| Component | Purpose | Install |
|-----------|---------|---------|
| **Claude Code CLI** (`claude`) | The agent runtime | `npm i -g @anthropic-ai/claude-code` (or official installer) |
| **tmux** | Long-lived agent sessions | `brew install tmux` |
| **fswatch** | Filesystem watcher for the bus daemon | `brew install fswatch` |
| **jq** | JSON for the inbox hook | `brew install jq` |
| **python3** | Cron scripts, Telegram calls | system python or `brew install python` |
| **git** | Version history of the Vault | preinstalled |
| **cron** (or **launchd**) | Scheduling | built into macOS |
| **curl** | Telegram Bot API calls | preinstalled |
| A **Telegram bot** | Push notifications to phone | create via `@BotFather` |
| A **Claude / Anthropic account** | With Remote Control enabled for mobile/web access | claude.ai |

> **Shell note:** the scripts below use a mix of `#!/bin/zsh` and `#!/bin/bash`. zsh is used
> where associative arrays are convenient (`declare -A`). Keep the shebangs as written.

---

## 3. Directory structure

The Vault is a single git repo. Suggested layout (replace `~/vault` with your path; the
reference implementation uses an absolute path — **keep paths absolute in all scripts**,
cron has no working directory):

```
~/vault/
├── CLAUDE.md                     # Orchestrator identity + global directives + launch flow
├── README.md
├── .gitignore                    # MUST ignore Credentials/
│
├── .claude/
│   ├── settings.json             # Hooks (UserPromptSubmit → inbox check)
│   ├── settings.local.json       # Local permission allowlist (gitignored or not)
│   └── commands/
│       └── inbox.md              # /inbox slash command
│
├── _System/                      # Orchestrator's own domain + global infrastructure
│   ├── Index.md                  # Global catalog / map of the whole Vault
│   ├── log.md                    # Global chronological operations log
│   ├── WIKI_PROTOCOL.md          # The shared ingest/query/lint workflow (all agents read this)
│   ├── restart-agents.sh         # Boots every agent + bus daemon (the master launcher)
│   ├── digest.sh                 # Cron: daily digest (writes a bus message to orchestrator)
│   ├── pragma_check.sh           # Cron: daily task-check (writes a bus message to a domain agent)
│   └── bus/                      # Inter-agent message bus
│       ├── INBOX_PROTOCOL.md
│       ├── send.sh               # Send a message + Telegram notify
│       ├── check-inbox.sh        # UserPromptSubmit hook: inject "you have N messages"
│       ├── bus-daemon.sh         # fswatch loop: push /inbox to idle agents
│       ├── daemon.log
│       ├── to/                   # One inbox folder per agent
│       │   ├── gamma/  (.gitkeep)
│       │   ├── finance/
│       │   ├── health/
│       │   └── …
│       └── sent/                 # Archive of processed messages (done__<original-name>.md)
│
├── Credentials/                  # GITIGNORED. API tokens, service accounts. Never committed.
│   └── telegram-bot.md           # token: … / chat_id: …  (YAML-ish frontmatter)
│
├── Finance/                      # ─┐
│   ├── CLAUDE.md                 #  │  Example domain agent. Every domain folder
│   ├── index.md                  #  │  follows the SAME structure (see §5).
│   ├── log.md                    #  │
│   ├── MEMORY.md                 #  │
│   ├── raw/                      #  │  immutable sources
│   ├── wiki/                     #  │  agent-generated pages
│   └── scripts/                  # ─┘  optional per-domain automation
│
├── Health/   …                   # same structure
├── Journal/  …                   # same structure
└── …                             # one folder per domain
```

> The agent names used here (Finance, Health, Journal, …) are **examples**. Pick whatever
> domains make sense for you. The orchestrator is named "Gamma" in the reference build; you
> can rename it, but keep a single orchestrator.

---

## 4. The orchestrator (`/CLAUDE.md`)

The root `CLAUDE.md` is loaded automatically by the `claude` process started in the Vault
root. It defines the orchestrator's role. Key sections:

1. **Identity & role** — "You are the orchestrator and knowledge architect of this local
   multi-agent network. Your environment is the root repo. You manage global state, synthesize
   knowledge across domains, and maintain structural integrity."

2. **Core directives:**
   - **Global indexing & synthesis** — integrate new concepts into the global graph; link
     disparate nodes.
   - **Structural integrity** — keep `_System/Index.md` reflecting the real filesystem.
   - **Strict delegation (routing)** — *this is the heart of the orchestrator.* It does **not**
     handle domain data itself. Instead it returns a routing instruction, e.g.:
     > *"Tasks/ideas/notes → go to `/Tasks` and launch the specialized agent there."*
     > *"Financial transactions → go to `/Finance` and launch the agent there."*
     > *"Health metrics → go to `/Health` …"*

     A routing table maps **request type → target domain folder**.
   - **Auto-sync after editing the global index** — whenever the orchestrator edits
     `_System/Index.md`, it immediately `git commit && git push` without being asked.

3. **Agent Launch Flow** — embedded directly in `CLAUDE.md` so the orchestrator can boot new
   agents on request (see §7).

The routing rule is what makes the network coherent: **one front door, deterministic dispatch.**

---

## 5. Per-domain structure & the Wiki Protocol

Every domain folder is self-similar:

```
Domain/
  CLAUDE.md     ← identity + domain-specific rules (the "schema"); never hand-edited by user
  index.md      ← catalog of everything in this domain (agent updates on every ingest)
  log.md        ← append-only chronological journal
  MEMORY.md     ← long-term distilled memory of the agent
  raw/          ← immutable sources (agent reads only)
  wiki/         ← agent-authored pages (agent writes & maintains)
  scripts/      ← optional domain automation
```

### 5.1 The shared workflow — `_System/WIKI_PROTOCOL.md`

Every domain agent operates by this single shared protocol. It defines three operations:

**Ingest** (new data arrives):
1. Read `index.md` to know what already exists.
2. Process the data.
3. Create/update the relevant `wiki/` pages.
4. Update `index.md`.
5. Append to `log.md`: `## [YYYY-MM-DD] ingest | Topic` + short description.
6. If it touches another domain → send a bus message to that agent (or to the orchestrator).

**Query** (a question):
1. Read `index.md`, find relevant pages.
2. Read them.
3. Synthesize an answer with `[[page-links]]`.
4. **If the answer is valuable, file it back as a new wiki page** (explorations compound).
5. Append to `log.md`: `## [YYYY-MM-DD] query | Question`.

**Lint** (periodic health check, on request or ~monthly):
- Find contradictions, stale claims, orphan pages (no inbound links), important concepts
  lacking a page, missing cross-references, data gaps.
- Append to `log.md`: `## [YYYY-MM-DD] lint | summary`.

### 5.2 Start-of-session ritual (in `WIKI_PROTOCOL.md`)

Before any action an agent must:
1. Read its domain `index.md`.
2. Read the last 3-5 log entries: `grep "^## \[" log.md | tail -5`.
3. Read `MEMORY.md` if present.

### 5.3 Page conventions

- Filenames: `kebab-case.md` or `YYYY-MM-DD.md` for dated entries.
- Cross-links: `[[page-name]]` (Obsidian-style; works as a free knowledge graph).
- Optional YAML frontmatter: `tags`, `updated`, etc.
- **The agent creates pages; the user only ever drops raw sources.**

### 5.4 The log convention (parseable by design)

Every log entry starts with a consistent prefix `## [YYYY-MM-DD] <type> | <description>`, so
the log is greppable with plain unix tools. Logs are **append-only**, often reverse-chronological.
A reliable "last activity date" query:

```bash
grep '^## \[' log.md | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' | sort -r | head -1
```

### 5.5 The per-agent `CLAUDE.md` ("schema") template

Each domain agent's `CLAUDE.md` typically contains:

- **Identity** — who the agent is, what folder it works in, what its domain covers.
- **Character/voice** — optional but powerful; gives the agent a consistent persona.
- **Domain table** — what kinds of inputs belong here (with examples).
- **KPIs** — measurable health goals for the domain + how to check each (e.g. "0 overdue
  tasks", "backlog < 20 lines"), checked during lint.
- **Domain structure** — the file/folder map of `wiki/`.
- **Bus protocol** — how to handle incoming bus messages (see §8).
- **Proactive startup protocol** — what to do *immediately on launch* without waiting for a
  user command (see §7.4). Example:
  ```
  ## Proactive startup
  Run automatically after reading context — do not wait for the user:
  1. Inbox — ls _System/bus/to/<me>/ → process every message
  2. <domain check #1> — e.g. find overdue items, print them
  3. <domain check #2> — e.g. stale quests > 14 days
  4. Final status line: "<AGENT> online. N overdue | N stuck | backlog N"
  ```
- **Ingest / Query protocols** — domain-specialized versions of the shared protocol.

---

## 6. Persistent memory (two layers)

There are **two distinct memory mechanisms**:

1. **`MEMORY.md` (in-Vault, per-agent)** — a human-readable distilled long-term memory for
   each domain agent, committed to git. Patterns, strategy, key context. Read at session start.

2. **Claude Code's file-based memory (out-of-Vault, per-project)** — Claude Code maintains a
   persistent memory directory keyed to the project path, e.g.
   `~/.claude/projects/<project-slug>/memory/`. Convention used here:
   - One fact per file, with frontmatter (`name`, `description`, `type: user|feedback|project|reference`).
   - A `MEMORY.md` **index** in that directory: one bullet per memory (`- [Title](file.md) — hook`),
     loaded into context each session.
   - Body links related memories with `[[name]]`.
   - Types: `user` (who the user is), `feedback` (how the agent should work — corrections/preferences),
     `project` (ongoing work/state), `reference` (pointers to external resources, dashboards, IDs).
   - Before saving, check for an existing file covering the same fact and update it rather than
     duplicating. Convert relative dates to absolute. Don't store what the repo already records.

   This is the agent's "muscle memory" across sessions — preferences, gotchas, project state —
   while `MEMORY.md` inside the Vault is the *domain's* knowledge.

---

## 7. Agent launch flow

This is the standardized way to bring an agent online. Used at every boot.

### 7.1 Naming conventions

- **tmux session name** = first letter(s) of the agent name, lowercase.
  `Finance → f`, `Health → h`, `TelegramVault → tv`.
- **Agent name** (passed to `--name` and to Remote Control) = the full PascalCase name
  (`Finance`, `Health`, `TelegramVault`).

### 7.2 One-line launch command

```bash
tmux new-session -d -s <letter> -c ~/vault/<DomainFolder> \
  "claude --dangerously-skip-permissions --model 'sonnet[1m]' --name '<FullName>'" \
  && sleep 8 \
  && tmux send-keys -t <letter>:0 '/remote-control <FullName>' Enter
```

Three steps: (1) start a detached tmux session running `claude` in the domain folder;
(2) wait ~8s for Claude to boot; (3) activate Remote Control.

> **Critical tmux gotcha:** always target `<letter>:0` (session:window), **never** bare
> `<letter>`. When sending keys *from inside another tmux session*, a bare target resolves to
> the *current* client, not the intended session — the command goes to the wrong place. Always
> use `session:window`.

Flags explained:
- `--dangerously-skip-permissions` — the agents run unattended/headless; they must not block
  on permission prompts. (Only do this in a trusted, sandboxed environment you control.)
- `--model 'sonnet[1m]'` — model selection; `[1m]` requests the 1M-token context variant.
- `--name '<FullName>'` — the label shown in Remote Control / the session list.

### 7.3 The master launcher — `restart-agents.sh`

A single script that (re)boots the entire network. Run it after a reboot or when sessions die:

```zsh
#!/bin/zsh
# Boots every agent + the bus daemon. Usage: zsh ~/vault/_System/restart-agents.sh
VAULT="$HOME/vault"
MODEL="sonnet[1m]"
SLEEP=10

# Permanent agents — always started. Map: tmux-key → "AgentName:working-dir"
declare -A AGENTS=(
  [g]="Gamma:$VAULT"
  [f]="Finance:$VAULT/Finance"
  [h]="Health:$VAULT/Health"
  [j]="Journal:$VAULT/Journal"
  # … add one line per domain agent
)

echo "→ Stopping bus-daemon and agents..."
tmux kill-session -t bd 2>/dev/null
for key in "${(@k)AGENTS}"; do tmux kill-session -t "$key" 2>/dev/null; done

echo "→ Launching agents..."
for key in "${(@k)AGENTS}"; do
  val="${AGENTS[$key]}"; name="${val%%:*}"; dir="${val#*:}"
  tmux new-session -d -s "$key" -c "$dir" \
    "claude --dangerously-skip-permissions --model '$MODEL' --name '$name'"
done

echo "→ Waiting ${SLEEP}s for Claude to boot..."
sleep $SLEEP

echo "→ Activating Remote Control..."
for key in "${(@k)AGENTS}"; do
  val="${AGENTS[$key]}"; name="${val%%:*}"
  # NOTE: "$key:0" — never bare "$key" (see §7.2 gotcha)
  tmux send-keys -t "$key:0" "/remote-control $name" Enter
done

echo "→ Waiting 10s for Remote Control..."
sleep 10

echo "→ Sending warm-up prompt..."
for key in "${(@k)AGENTS}"; do
  val="${AGENTS[$key]}"; name="${val%%:*}"
  # Per-agent file list (orchestrator reads global files; domains read their own)
  if [[ "$key" == "g" ]]; then
    FILES="CLAUDE.md, _System/Index.md, _System/log.md, _System/WIKI_PROTOCOL.md"
  else
    FILES="CLAUDE.md, index.md, log.md, ../_System/WIKI_PROTOCOL.md"
  fi
  WARMUP="Read these files: $FILES. Understand: who you are, your domain status, recent \
events, open items. Introduce yourself in one line. Then IMMEDIATELY run the 'Proactive \
startup' protocol from your CLAUDE.md — inbox, key checks, final status line. Do not wait \
for a user command."
  tmux send-keys -t "$key:0" "$WARMUP"
  sleep 1                          # send text, pause, THEN Enter (see §7.5)
  tmux send-keys -t "$key:0" Enter
done

echo "→ Starting bus-daemon..."
tmux new-session -d -s bd -c "$VAULT/_System/bus" "zsh bus-daemon.sh"

tmux ls
```

### 7.4 Warm-up prompt (the "cold agent" fix)

After `/remote-control` activates, a freshly booted agent sits **cold** — it hasn't read its
own files and doesn't know who it is. The launcher sends a **warm-up prompt** that tells it
to read its context files, introduce itself, and run its proactive startup protocol. The agent
comes online "warm": context loaded, role understood, inbox already processed.

Whenever you change an agent's set of startup files, update the warm-up file list in
`restart-agents.sh`.

### 7.5 tmux send-keys timing gotcha

When sending a prompt to a tmux pane manually, **send the text, sleep ~1s, then send `Enter`
separately**. Never concatenate text + `Enter` in one `send-keys` call — the Enter can race
ahead of the text and submit an empty or truncated prompt.

### 7.6 Verify & attach

```bash
tmux ls                                   # all sessions alive?
tmux capture-pane -t <letter>:0 -p | tail -3   # check Remote Control is active
tmux attach -t <letter>                   # attach in terminal
```

---

## 8. Inter-agent communication — the file-based bus

Agents talk **asynchronously through files**. No queues, no network, no daemon required for
correctness (the daemon only makes delivery *push* instead of *pull*).

### 8.1 Structure

```
_System/bus/
  send.sh            # wrapper to send a message
  check-inbox.sh     # UserPromptSubmit hook script
  bus-daemon.sh      # optional push daemon (fswatch)
  to/<agent>/        # one inbox folder per agent
  sent/              # archive of processed messages
```

### 8.2 Message format

Markdown with frontmatter. Filename:
`YYYY-MM-DDTHH-MM-SS__<from>__to-<to>__<title-slug>.md`

> `<to>` is included in the filename so two messages from the same sender at the same second
> to *different* agents never collide once archived into the shared `sent/` folder.

```markdown
---
from: finance
to: health
created: 2026-05-08T14:30:00+0700
priority: normal        # normal | high
status: unread          # unread | read | done
---

# Title

Body. May contain [[wiki-links]], code, anything.

**What I want from you:** the concrete request.
```

### 8.3 Sending — `send.sh`

```bash
~/vault/_System/bus/send.sh \
  --to health --from finance \
  --title "spending anomaly" \
  --body "Health-category spend up 340% this month."

# Long body from a file (REQUIRED for multi-line bodies — never inline a huge --body):
echo "long body…" > /tmp/msg.md
~/vault/_System/bus/send.sh --to health --from finance --title "X" --body-file /tmp/msg.md
```

What `send.sh` does:
1. Parses `--to/--from/--title/--body|--body-file/--priority`.
2. Validates the target inbox folder exists.
3. Builds the timestamped filename + slug.
4. Writes the frontmatter + body file into `to/<agent>/`.
5. **Fires a Telegram notification** (`🚌 Bus: from → to / title / body-preview`) so you see
   every inter-agent message on your phone in real time. The Telegram call reads the bot token
   from `Credentials/telegram-bot.md` and runs in the background (`&`), failures swallowed.

Reference `send.sh` (genericized — Telegram block reads credentials from a gitignored file):

```bash
#!/bin/bash
set -e
BUS_DIR="$HOME/vault/_System/bus"
TO=""; FROM=""; TITLE=""; BODY=""; BODY_FILE=""; PRIORITY="normal"
while [[ $# -gt 0 ]]; do case "$1" in
  --to) TO="$2"; shift 2;; --from) FROM="$2"; shift 2;;
  --title) TITLE="$2"; shift 2;; --body) BODY="$2"; shift 2;;
  --body-file) BODY_FILE="$2"; shift 2;; --priority) PRIORITY="$2"; shift 2;;
  *) echo "Unknown arg: $1" >&2; exit 1;; esac; done
[ -z "$TO" ] && { echo "Missing --to" >&2; exit 1; }
[ -z "$FROM" ] && { echo "Missing --from" >&2; exit 1; }
[ -z "$TITLE" ] && { echo "Missing --title" >&2; exit 1; }
INBOX="$BUS_DIR/to/$TO"
[ ! -d "$INBOX" ] && { echo "Inbox not found: $INBOX" >&2; exit 1; }
[ -n "$BODY_FILE" ] && BODY=$(cat "$BODY_FILE")
TS=$(date +%Y-%m-%dT%H-%M-%S)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-\|-$//g' | cut -c1-50)
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
# Optional: Telegram notification (reads token from gitignored Credentials file).
# Runs in background, errors ignored. See §9.
```

### 8.4 Receiving — three delivery mechanisms

**(a) Pull via `UserPromptSubmit` hook (`check-inbox.sh`).** Configured in `.claude/settings.json`,
this runs on *every* user prompt. It counts unread `.md` files in the agent's inbox and, if any,
injects `additionalContext` telling the agent: "You have N unread messages — first answer the
user, then process each message yourself without asking, then move them to `sent/done__…`, then
report 1-2 lines." This guarantees messages are seen the next time you talk to the agent.

```bash
#!/bin/bash
# check-inbox.sh <agent-name> — UserPromptSubmit hook. Reads stdin JSON (ignored).
AGENT="$1"; [ -z "$AGENT" ] && exit 0
INBOX="$HOME/vault/_System/bus/to/$AGENT"
[ ! -d "$INBOX" ] && exit 0
COUNT=$(find "$INBOX" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -eq 0 ] && exit 0
LIST=$(find "$INBOX" -maxdepth 1 -type f -name "*.md" | xargs -n1 basename | sort)
CONTEXT="📬 You have ${COUNT} unread messages in _System/bus/to/${AGENT}/:
${LIST}

ORDER OF OPERATIONS:
1. First answer the user's request as usual.
2. Then read and process each inbox message yourself — no confirmation needed.
   Messages from other agents = actions they expect you to take.
3. After processing, move the file to _System/bus/sent/ with a 'done__' prefix.
4. End with a 1-2 line summary of what was processed.
Exceptions (ask first): destructive actions, conflicts with the user's current request,
ambiguous messages."
jq -n --arg ctx "$CONTEXT" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
exit 0
```

`.claude/settings.json` wires it up (note: the hook is hardcoded to the agent that owns this
settings file — here `gamma`; each agent's folder gets its own settings with its own name):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command",
        "command": "/Users/you/vault/_System/bus/check-inbox.sh gamma",
        "timeout": 5 } ] }
    ]
  }
}
```

> Because the hook command bakes in the agent name, each domain folder needs its own
> `.claude/settings.json` (or a shared one parameterized per folder). The simplest reproducible
> approach: put a `.claude/settings.json` in each domain folder pointing `check-inbox.sh` at
> that domain's name.

**(b) Push via `bus-daemon.sh` (optional but recommended).** A background process (its own tmux
session `bd`) that uses `fswatch` to watch every inbox folder. When a new `.md` appears, it maps
the inbox folder → tmux session and **pushes `/inbox` into that session** if the agent is idle —
so messages get processed *immediately* rather than waiting for the next user prompt.

It detects "busy" by capturing the pane and looking for spinner/working markers
(`Thinking|Sublimating|Running|⠋⠙⠹…`). If busy, it skips (the message will be picked up on the
next user prompt via the hook). If idle, it sends `/inbox`.

```zsh
#!/bin/zsh
# bus-daemon.sh — fswatch → push /inbox to idle agents.
# Launch: tmux new-session -d -s bd -c ~/vault/_System/bus "zsh bus-daemon.sh"
BUS_DIR="$HOME/vault/_System/bus"; LOG="$BUS_DIR/daemon.log"
declare -A SESSION=( [gamma]="g" [finance]="f" [health]="h" [journal]="j" )  # inbox→tmux
log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
push_agent(){
  local agent="$1" file="$2" sess="${SESSION[$1]}"
  [ -z "$sess" ] && { log "WARN unknown agent $agent"; return; }
  tmux has-session -t "$sess" 2>/dev/null || { log "WARN $sess not running — queued"; return; }
  local pane; pane=$(tmux capture-pane -t "$sess:0" -p 2>/dev/null | tail -8)
  if echo "$pane" | grep -qE 'Thinking|Sublimating|Running|⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏'; then
    log "SKIP $agent busy"; return; fi
  log "→ push /inbox to $sess:0"; tmux send-keys -t "$sess:0" "/inbox" Enter
}
log "Bus daemon started."
/opt/homebrew/bin/fswatch --event Created --recursive --include '\.md$' --exclude '\.gitkeep' \
  "$BUS_DIR/to/" | while read -r filepath; do
    agent=$(echo "$filepath" | sed "s|$BUS_DIR/to/||" | cut -d'/' -f1)
    fn=$(basename "$filepath")
    [[ "$fn" != *.md || "$fn" == ".gitkeep" ]] && continue
    log "NEW MSG for $agent: $fn"; push_agent "$agent" "$filepath"
  done
```

**(c) Manual `/inbox` slash command.** A fallback the user (or the daemon) can trigger anytime.
`.claude/commands/inbox.md`:

```markdown
---
description: Read and process inter-agent inbox messages
---
Open inbox: `_System/bus/to/<me>/`
For each .md file: read it, summarize (from / topic / what they want),
then process it. After processing, move to `_System/bus/sent/done__<original-name>`.
If empty — say "inbox empty" and stop.
```

### 8.5 After processing a message — the discipline

Read → act → **write a `log.md` entry** → move the file to `sent/done__<original-name>.md`.
- The log entry is **mandatory even if no action was taken** (record why it was deferred).
- When moving, keep the **exact original filename** (don't replace `<from>` with your own name).
- **Never delete** — git history is the full audit trail of inter-agent communication.

Log format: `## [YYYY-MM-DD] bus | inbox processed | <from> → <title>` + what was requested
and what was done/deferred.

### 8.6 When to message another agent

| Scenario | Direction |
|----------|-----------|
| Cross-domain anomaly (spend ↔ health) | domain ↔ domain |
| Architectural question / needs synthesis | any → orchestrator |
| A task surfaced inside a specialized domain | domain → task-agent |
| Insight relevant to the whole network | any → orchestrator |

Don't message when: you can solve it yourself; it doesn't affect the other agent's work; or
it's urgent enough to need the human directly (then notify the human, not an agent).

The same autonomy rule lives in `WIKI_PROTOCOL.md`: **if an agent detects a cross-agent
situation, it sends the bus message itself, without waiting for a user command** — then gives
the user a one-line report.

---

## 9. Telegram integration

A single Telegram bot (created via `@BotFather`) is the network's push channel to your phone.
Credentials live in `Credentials/telegram-bot.md` (a **gitignored** file):

```
token: <bot-token>
chat_id: <your-chat-id>
```

Two usage patterns:

**(a) `curl` from any script.** Read the token/chat_id from the credentials file and POST:

```bash
TOKEN=$(grep '^token:'   ~/vault/Credentials/telegram-bot.md | awk '{print $2}')
CHAT=$(grep  '^chat_id:' ~/vault/Credentials/telegram-bot.md | awk '{print $2}')
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -H 'Content-Type: application/json' \
  -d "{\"chat_id\": ${CHAT}, \"text\": \"your message\", \"parse_mode\": \"HTML\"}" >/dev/null
```

**(b) Automatic bus notification.** `send.sh` posts a preview of every bus message to Telegram
(§8.3), so you watch the agents talk to each other live.

Use Telegram for: daily digests, cron-job alerts, overdue-task nudges, agent-timeout warnings,
and bus traffic. **Never commit the token** — keep `Credentials/` in `.gitignore`.

---

## 10. Remote Control (phone & browser access)

Claude Code's **Remote Control** lets you drive a running terminal session from the Claude
mobile app or `claude.ai`. The flow:

1. Each agent activates it on boot with `/remote-control <FullName>` (see §7).
2. The session then appears in the Remote Control list in the app / browser, labeled with the
   agent's full name.
3. From your phone you select an agent and chat with it exactly as in the terminal — same
   session, same context, same tmux pane.

This is why naming matters: **tmux key is short (for local targeting), the `--name` is the full
human-readable label (for Remote Control).** You get full mobile control of the entire agent
network without exposing anything to a server — it tunnels through your Claude account.

---

## 11. Scheduling — cron / launchd

Two scheduling backends are used; pick either (cron is simpler, launchd survives sleep better).

### 11.1 Two cron job *types*

**Type A — pure script, no LLM.** A Python/shell script does deterministic work (scrape an API,
check PR statuses, compute a metric) and posts results to Telegram directly. No agent involved.

**Type B — wake an LLM agent.** The cron script does **not** run `claude -p` (one-shot mode is
deliberately avoided). Instead it uses one of two sub-patterns:

- **B1 — via the bus (for permanent agents).** The script writes a bus message to a running
  agent's inbox. The bus-daemon's `fswatch` sees the new file and pushes `/inbox`, waking the
  already-running agent to do the work. Example: the daily digest.

- **B2 — ephemeral tmux + sentinel (for on-demand work).** The script spins up a *temporary*
  tmux session running `claude`, sends a prompt that ends with `touch /tmp/<session>.done`, then
  polls for that sentinel file (or times out), and kills the session. Example: a nightly
  scanner/analysis job.

> **Rule: never use `claude -p` in cron.** Always ephemeral tmux + sentinel (B2) or the bus (B1).
> One-shot mode lacks the session warm-up, Remote Control, and tmux observability the network relies on.

### 11.2 Example crontab

```cron
# Daily digest 07:00 — Type B1 (bus → orchestrator → reads logs → Telegram)
0 7 * * * /bin/zsh   /Users/you/vault/_System/digest.sh        >> /Users/you/vault/_System/digest.log 2>&1
# Daily task check 10:00 — Type B1 (bus → task agent)
0 10 * * * /bin/zsh  /Users/you/vault/_System/pragma_check.sh  >> /Users/you/vault/_System/pragma_check.log 2>&1
# Nightly analysis 03:00 — Type B2 (ephemeral tmux + sentinel)
0 3 * * * /bin/zsh   /Users/you/vault/SomeDomain/scripts/run.sh
# Status checker 12:00 — Type A (pure python, no LLM)
0 12 * * * /usr/bin/python3 /Users/you/vault/SomeDomain/scripts/check.py >> /Users/you/vault/SomeDomain/scripts/check.log 2>&1
```

> launchd equivalents (`~/Library/LaunchAgents/com.you.agent.*.plist`) can run the same scripts
> on a `StartCalendarInterval`; useful for jobs that must fire even after the Mac was asleep.

### 11.3 Cron gotchas (learned the hard way)

- **PATH:** cron has a minimal PATH. Every script must start with:
  `export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"` (so it finds `tmux`,
  `fswatch`, `claude`, `python3`).
- **Absolute paths everywhere** — cron has no working directory.
- **Long bus bodies → `--body-file`,** never a giant inline `--body`.
- **Lock file** to prevent overlapping runs of long jobs:
  `[ -f "$LOCK" ] && exit 0; touch "$LOCK"; trap 'rm -f "$LOCK"' EXIT`.
- **Timeout + Telegram alert** for B2 jobs (see §11.5).

### 11.4 Example — Type B1, daily digest (`digest.sh`)

Writes a single bus message instructing the orchestrator to read every agent's `log.md` and the
newest file in each `wiki/`, build a one-line-per-agent brief, send it to Telegram, and — if any
agent has been silent > 10 days — autonomously send that agent a "digest-alert" bus message.

```zsh
#!/bin/zsh
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
BODY_FILE="/tmp/digest_body_$(date +%s).md"
cat > "$BODY_FILE" << 'BODY'
Produce the daily Vault digest. Read files NOW (don't trust cached session state).
For each agent do TWO steps:
  1. grep '^## \[' <path>/log.md | tail -3       (recent ops)
  2. find <path>/wiki/ -name "*.md" | sort | tail -1   (newest content file)
Use the LATER of the two dates as "last activity".
Domains: Finance/ Health/ Journal/ …
Build a one-line-per-agent brief: "Name: what happened / last file YYYY-MM-DD".
Append "Attention: …" for anything overdue/stuck.
Send the final text to Telegram (bot creds in Credentials/telegram-bot.md, via curl).
Then: if an agent has no log entry AND no new wiki file in > 10 days, send it a bus message:
  _System/bus/send.sh --to <agent> --from gamma --title "digest-alert" --body "<what's wrong>"
Do all of this without asking questions.
BODY
~/vault/_System/bus/send.sh --to gamma --from cron --title "daily-digest" --body-file "$BODY_FILE"
rm -f "$BODY_FILE"
```

### 11.5 Example — Type B2, ephemeral tmux + sentinel

```zsh
#!/bin/zsh
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
MODEL="sonnet[1m]"; TIMEOUT=1800
SESSION="job_cron_$(date +%s)"; DONE="/tmp/${SESSION}.done"
LOCK="$HOME/vault/SomeDomain/scripts/.running.lock"
[ -f "$LOCK" ] && exit 0
touch "$LOCK"
trap "rm -f '$LOCK' '$DONE'; tmux kill-session -t '$SESSION' 2>/dev/null" EXIT

# (optional Phase 1: pure-python data collection here)

tmux new-session -d -s "$SESSION" -c "$HOME/vault/SomeDomain" \
  "claude --dangerously-skip-permissions --model '$MODEL' --name 'JobAgent'"
sleep 12
PROMPT="Read CLAUDE.md and do <the job>. Work autonomously. \
When fully done, run as the LAST command: touch ${DONE}"
tmux send-keys -t "$SESSION:0" "$PROMPT"; sleep 0.5; tmux send-keys -t "$SESSION:0" Enter

ELAPSED=0
while [ ! -f "$DONE" ] && [ "$ELAPSED" -lt "$TIMEOUT" ]; do sleep 30; ELAPSED=$((ELAPSED+30)); done
if [ ! -f "$DONE" ]; then
  TOKEN=$(grep '^token:' ~/vault/Credentials/telegram-bot.md | awk '{print $2}')
  CHAT=$(grep '^chat_id:' ~/vault/Credentials/telegram-bot.md | awk '{print $2}')
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=${CHAT}" -d "text=⚠️ ${SESSION} timed out after ${TIMEOUT}s" >/dev/null
fi
# EXIT trap kills the session and cleans the sentinel.
```

The sentinel pattern is the key trick for headless LLM work: the agent signals completion by
`touch`-ing a file, and the wrapper waits on it with a hard timeout + Telegram alert.

---

## 12. Global indexing & logging

- **`_System/Index.md`** — the global map of the Vault: a section table (domain → keeper →
  purpose), a per-folder file catalog, a "state of the Vault" summary, and navigation notes.
  The orchestrator keeps it in sync with the filesystem and **auto-commits/pushes** after every
  edit to it.
- **`_System/log.md`** — the global chronological operations log, same `## [date] type | desc`
  convention as domain logs.
- Each domain has its own `index.md` + `log.md`. The global index links out to them.

---

## 13. End-to-end: standing the network up from scratch

A checklist your friend can follow with a fresh Claude Code install on a Mac:

1. **Install prerequisites** (§2): `claude`, `tmux`, `fswatch`, `jq`, `python3`. Create a
   Telegram bot via `@BotFather`, get the bot token and your chat_id.
2. **`git init` the Vault** at e.g. `~/vault`. Create the directory skeleton (§3).
3. **Write the orchestrator `CLAUDE.md`** (§4): identity, the routing table for your domains,
   the auto-sync-on-index-edit directive, and paste in the Agent Launch Flow.
4. **Write `_System/WIKI_PROTOCOL.md`** (§5.1): the shared ingest/query/lint workflow + the
   start-of-session ritual + page conventions.
5. **Create domain folders.** For each domain: `CLAUDE.md` (identity, character, KPIs, domain
   structure, bus protocol, proactive startup), empty `index.md`, `log.md`, `MEMORY.md`,
   `raw/`, `wiki/`.
6. **Set up the bus** (§8): create `_System/bus/to/<agent>/` (one per agent, each with a
   `.gitkeep`), `sent/`, and the three scripts (`send.sh`, `check-inbox.sh`, `bus-daemon.sh`).
   `chmod +x` them. Add `INBOX_PROTOCOL.md`.
7. **Wire the hook**: put a `.claude/settings.json` in each agent folder pointing
   `check-inbox.sh` at that agent's inbox name. Add `.claude/commands/inbox.md`.
8. **Credentials**: create `Credentials/telegram-bot.md` with `token:` and `chat_id:`. Add
   `Credentials/` to `.gitignore`. **Verify it's ignored before the first commit.**
9. **Write `restart-agents.sh`** (§7.3) with your agent map and warm-up file lists. `chmod +x`.
10. **Boot the network**: `zsh ~/vault/_System/restart-agents.sh`. Verify with `tmux ls` and
    `tmux capture-pane -t g:0 -p | tail`.
11. **Connect Remote Control**: confirm each agent shows up in the Claude mobile app / claude.ai.
12. **Add cron jobs** (§11) for digests, checks, and any scheduled agent work. Remember PATH +
    absolute paths + no `claude -p`.
13. **First commit & push.** From then on, the wiki is just a git repo of markdown — you get
    full version history of every thought the network records.

---

## 14. Design principles (why it's built this way)

- **Local-first, file-first.** Everything is markdown + shell + tmux. No DB, no server, no
  cloud dependency except the Claude account itself. The whole state is a git repo.
- **One front door.** A single orchestrator routes; domain agents specialize. No ambiguity
  about where something goes.
- **The wiki compounds.** Answers and analyses are filed back as pages, not lost to chat.
- **Agents are autonomous but observable.** They act without asking (bus messages, proactive
  startup, cross-domain alerts) — but everything lands in `log.md` and git history, and you
  watch the traffic flow through Telegram.
- **The bookkeeping is the point.** Humans abandon wikis because maintenance outpaces value.
  LLMs don't get bored — they update every cross-reference, every index line, every log entry.
  Maintenance cost → ~0, so the knowledge base stays alive.
- **Headless without `-p`.** Scheduled work uses real warm sessions (ephemeral tmux + sentinel,
  or the bus) so cron-driven agents behave exactly like interactive ones.

---

*This document describes the pattern and mechanics only. Adapt the agent roster, domains,
voices, KPIs, and schedules to your needs. Hand this file to Claude Code and have it scaffold
your own instance.*
