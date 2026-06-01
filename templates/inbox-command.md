---
description: Read and process inter-agent inbox messages
---
Open your inbox: `vault/bus/to/{{AGENT_LC}}/`

For each `.md` file:
1. Read it.
2. Process what it asks (a message from another agent = an action expected of you).
3. Append a `log.md` entry: `## [YYYY-MM-DD] bus | inbox processed | <from> → <title>`.
4. Move the file to `vault/bus/sent/done__<original-name>` (keep the exact original name).

If the inbox is empty — say "inbox empty" and stop.
Ask first only if a message is destructive, conflicting, or genuinely ambiguous.
