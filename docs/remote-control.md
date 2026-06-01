# Remote Control — drive your agents from your phone

Claude Code's **Remote Control** lets you control a running terminal session from the Claude
mobile app or claude.ai — same session, same context, same tmux pane.

## How warren uses it
`restart-agents.sh` runs `/remote-control <AgentName>` in each session right after boot. Each
agent then appears in the Remote Control list, labeled by its full name.

## Connect
1. Boot the network: `bash core/restart-agents.sh`.
2. Open the Claude mobile app (or claude.ai) with the same account.
3. The agents show up by name — tap one and chat with it exactly as in the terminal.

## Naming, and why it matters
- **tmux key** is short (`g`, `f`, `h`) — for fast local targeting in scripts.
- **Agent name** is the full PascalCase label (`Gamma`, `Finance`) — what you see in Remote
  Control and what's passed to `--name`.

Nothing is exposed to a server you run — it tunnels through your Claude account.

## Verify it's active
```bash
tmux capture-pane -t <key>:0 -p | tail
```
You should see Remote Control acknowledged in the pane.
