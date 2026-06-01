# Inter-Agent Bus — Protocol

Asynchronous communication between agents through files. No queues, no daemons (for
correctness), no network. Just markdown files appearing in inbox folders.

---

## Structure
```
vault/bus/                      (personal data — git-ignored)
  to/<agent>/   ← one inbox folder per agent (lowercased name)
  sent/         ← archive of processed messages (done__<original-name>.md)

core/bus/                       (engine — tracked in the repo)
  send.sh         ← send a message (+ optional Telegram notify)
  check-inbox.sh  ← UserPromptSubmit hook (inject "you have N messages")
  bus-daemon.sh   ← push daemon (fswatch/inotify → tmux send-keys "/inbox")
```

---

## Message format
Filename: `YYYY-MM-DDTHH-MM-SS__<from>__to-<to>__<title-slug>.md`
(`<to>` is in the name so messages to different agents never collide once archived.)

```markdown
---
from: finance
to: health
created: 2026-05-08T14:30:00+0700
priority: normal        # normal | high
status: unread
---

# Title

Body. May contain [[wiki-links]], code, anything.

**What I want from you:** the concrete request.
```

---

## Send
```bash
core/bus/send.sh --to health --from finance \
  --title "spending anomaly" --body "Health-category spend up 340% this month."

# Long body → file (never inline a huge --body):
core/bus/send.sh --to health --from finance --title "X" --body-file /tmp/msg.md
```

---

## Receive — three mechanisms
1. **Hook (pull):** `check-inbox.sh` runs on every user prompt and injects a notice if the
   inbox has unread messages. Guarantees messages are seen next time you talk to the agent.
2. **Daemon (push):** `bus-daemon.sh` watches all inboxes and pushes `/inbox` into an idle
   agent's tmux session the moment a message lands.
3. **Manual:** the `/inbox` slash command, anytime.

---

## After processing a message — the discipline
Read → act → **write a `log.md` entry** → move the file to `vault/bus/sent/done__<original-name>.md`.
- The log entry is mandatory **even if no action was taken** (record why it was deferred).
- Keep the **exact original filename** when moving (don't replace `<from>` with your name).
- **Never delete** — git history is the full audit trail.

Log format: `## [YYYY-MM-DD] bus | inbox processed | <from> → <title>` + what was asked & done.

---

## When to message another agent
| Scenario | Direction |
|----------|-----------|
| Cross-domain anomaly | domain ↔ domain |
| Architectural question / needs synthesis | any → orchestrator |
| A task surfaced inside a specialized domain | domain → task agent |
| Insight relevant to the whole network | any → orchestrator |

Don't message when you can solve it yourself, when it doesn't affect the other agent, or
when it's urgent enough to need the human directly (then notify the human, not an agent).
