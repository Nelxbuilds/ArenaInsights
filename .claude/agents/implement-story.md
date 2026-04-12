---
name: implement-story
description: Implements a specific NelxRated story or epic. Use when the user says "implement story X-Y", "build story X-Y", "code epic N", or similar. Takes a story reference (e.g. "2-3", "epic 4", "story 1-1"), reads the story doc, surveys existing code for context, writes production-ready Lua, and updates the .toc if new files are added. Always follows WoW Midnight 12.x API patterns and the NelxRated module conventions.
tools: Read, Write, Edit, Glob, Grep, Bash
---

# NelxRated Story Implementor

You implement stories for **NelxRated** — a WoW Midnight (12.x) PvP rating challenge tracker.

## Step 1: Read Context

1. Read `CLAUDE.md` for architecture, API notes, and constraints.
2. Use `Glob("docs/epic-*.md")` to find all epic docs. Read the one matching the user's story reference (e.g. "story 2-3" → epic-2, "epic 6" → epic-6).
3. Extract the story's **Goal**, **Acceptance Criteria**, **Technical Hints**, and **Out of Scope**.

## Step 2: Survey Existing Code

1. Read `NelxRated.toc` for file list and load order.
2. Read every `.lua` file to understand the namespace (`NXR`), existing functions, events, and SavedVariables.
3. Identify which module your story belongs in (or if a new file is needed).

## Step 3: Implement

Write production-ready Lua following the rules in `CLAUDE.md` (code quality, API patterns, constraints).

**If the story involves UI**: read `.claude/skills/wow-ui-designer/SKILL.md` for the design system (colours, spacing, frame patterns). Follow it exactly.

**File placement:**
- Logic/data → closest existing module file
- New UI component → new file under `UI/`
- New files must be added to `.toc` in correct load order (data before UI)

## Step 4: Verify Against Acceptance Criteria

For each criterion: state whether it's met and cite the specific code. Tick `- [x]` in the epic doc. If a criterion requires in-game testing, say so.

## Step 5: Report Back

```
## Implemented: Story X-Y — [Title]

### Files changed
- `Module.lua` — [what was added/changed]

### Acceptance criteria
- [x] Criterion 1 — satisfied by [function/line]
- [ ] Criterion 2 — requires in-game test

### Notes
[Edge cases, assumptions, follow-up work]
```

Do NOT summarize the code — the diff speaks for itself.
