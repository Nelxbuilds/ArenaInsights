---
name: update-readme
description: >
  Sync README.md with current NelxRated features by reading epic docs and CLAUDE.md.
  Use when the user says "update readme", "sync readme", "readme is out of date",
  "/update-readme", or before shipping a release. Also use proactively after a new
  epic is completed or when multiple stories have been implemented since the last
  README update.
user_invocable: true
---

# Update README Skill

Keep README.md accurate by reading the source of truth (epics + CLAUDE.md) and
rewriting only the sections that describe functionality.

## What to update

Read these sources in order:

1. `CLAUDE.md` — architecture, bracket list, design constraints, overlay logic
2. `docs/epic-*.md` — all epic files (glob `docs/epic-*.md`). For each, check
   which stories are **checked off** (`[x]`). Only completed stories count as
   shipped features.
3. `README.md` — the current state, to avoid rewriting things that are already correct

## Sections to rewrite

Update these sections based on what you find:

- **Intro paragraph** (tagline under the title) — mention key capability pillars
- **Features** — bullet list of what the addon does. One bullet per distinct
  capability. Keep bullets short and scannable. Use the completed-story pattern
  to decide what belongs here — if a story is unchecked, it's not shipped.
- **Main Frame Tabs** table — list every tab that exists in the sidebar with a
  one-line description. Derive from epic docs and `MainFrame.lua` / `HistoryUI.lua`
  if needed.
- **Usage** table — slash commands. Derive from `Core.lua` or any `/nxr` command
  registration you find.

## Sections to leave alone

Never touch:

- Installation (CurseForge / Manual steps)
- Requirements
- Built With
- License

## How to write the Features list

Good feature bullets are:
- User-visible, not implementation details
- Short (one clause, no sub-bullets needed)
- Ordered roughly by user importance: tracking → challenges → overlay → history → multi-char → multi-account → customization

Bad: "Lazily initializes ratingHistory arrays with deduplication"
Good: "**Rating History** — Graph visualization of rating progression per character/spec/bracket"

## Output

Rewrite README.md in place. Do not add a summary comment or explanation after
writing — the diff speaks for itself.

If README is already accurate and nothing needs changing, say so and skip the write.
