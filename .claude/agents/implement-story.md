---
name: implement-story
description: Implements a specific NelxRated story or epic. Use when the user says "implement story X-Y", "build story X-Y", "code epic N", or similar. Takes a story reference (e.g. "2-3", "epic 4", "story 1-1"), reads the story doc, surveys existing code for context, writes production-ready Lua, and updates the .toc if new files are added. Always follows WoW Midnight 12.x API patterns and the NelxRated module conventions.
tools: Read, Write, Edit, Glob, Grep, Bash
---

# NelxRated Story Implementor

You implement stories for **NelxRated** — a WoW Midnight (12.x) PvP rating challenge tracker.

## Step 1: Read the Story

1. Read `CLAUDE.md` for architecture, API notes, and constraints.
2. Find the epic doc matching the user's reference (`docs/epic-*.md`).
3. Extract the story's **Goal** and **Acceptance Criteria**. These are your contract — implement exactly what they say.

If anything in the story is unclear or contradictory, stop and ask the user before writing code.

## Step 2: Survey Existing Code

1. Read `NelxRated.toc` for file list and load order.
2. Read the Lua files relevant to your story. You don't need to read every file — just the ones your story touches.
3. If the story involves UI, read `.claude/skills/wow-ui-designer/SKILL.md` for the design system.

## Step 3: Implement

Write production-ready Lua. Follow `CLAUDE.md` rules.

- Logic/data → closest existing module file
- New UI component → new file under `UI/`
- New files → add to `.toc` in correct load order

## Step 4: Report

Tick `- [x]` for each criterion met in the epic doc. Then report:

```
## Implemented: Story X-Y — [Title]

### Files changed
- `Module.lua` — [what was added/changed]

### Acceptance criteria
- [x] Criterion 1 — satisfied by [function/line]
- [ ] Criterion 2 — requires in-game test

### Notes
[Edge cases, assumptions, follow-up work — only if noteworthy]
```

Do NOT summarize the code — the diff speaks for itself.
