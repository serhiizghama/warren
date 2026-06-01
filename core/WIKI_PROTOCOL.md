# Wiki Protocol — the shared workflow for every warren agent

Every domain agent operates by this single protocol. The wiki is the codebase; the
agent is the programmer. You curate sources and ask questions — the agent does all the
reading, summarizing, cross-referencing, filing, and bookkeeping.

> Bootstrap copies this file to your vault root so every agent reads the same protocol.

---

## Structure of any domain

```
Domain/
  CLAUDE.md     ← identity + domain rules (the "schema"); never hand-edited by the user
  index.md      ← catalog of everything in the domain (updated on every ingest)
  log.md        ← append-only chronological journal
  MEMORY.md     ← long-term distilled memory
  raw/          ← immutable sources (agent reads only, never modifies)
  wiki/         ← agent-authored pages (agent writes & maintains)
```

---

## Three operations

### 1. Ingest — new data arrives
1. Read `index.md` to see what already exists.
2. Process the data.
3. Create/update the relevant `wiki/` pages.
4. Update `index.md`.
5. Append to `log.md`: `## [YYYY-MM-DD] ingest | Topic` + a short description.
6. If it touches another domain → send a bus message to that agent (see INBOX_PROTOCOL.md).

### 2. Query — a question
1. Read `index.md`, find relevant pages.
2. Read them.
3. Synthesize an answer with `[[page-links]]`.
4. **If the answer is valuable, file it back as a new wiki page** — explorations compound.
5. Append to `log.md`: `## [YYYY-MM-DD] query | Question`.

### 3. Lint — health check (on request or ~monthly)
- Find contradictions, stale claims, orphan pages (no inbound links), important concepts
  lacking a page, missing cross-references, data gaps.
- Append to `log.md`: `## [YYYY-MM-DD] lint | summary`.

---

## Start of every session
1. Read the domain `index.md`.
2. Read the last few log entries: `grep '^## \[' log.md | tail -5`.
3. Read `MEMORY.md` if present.

---

## Page conventions
- Filenames: `kebab-case.md` or `YYYY-MM-DD.md` for dated entries.
- Cross-links: `[[page-name]]` (a free knowledge graph).
- Optional YAML frontmatter: `tags`, `updated`.
- The agent creates pages; the user only ever drops raw sources.
- Log entries always start with `## [YYYY-MM-DD] <type> | <description>` so logs stay greppable.

---

## Autonomous communication
If an agent detects a cross-domain situation (an anomaly, an insight relevant elsewhere, an
architectural question for the orchestrator), it **sends the bus message itself**, without
waiting for a user command — then gives the user a one-line report.

**Good answers don't vanish into chat history — they become wiki pages.**
