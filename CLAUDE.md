# CLAUDE.md

Research codebase before editing. Never change code you haven't read.

Before using any WoW API not already documented in this file, invoke `/wow-api-research` to verify it exists, its signature, and whether it's deprecated.

## Project

**Name**: NelxRated
**Author**: Nelx
**Description**: Personal PvP rating challenge tracker for Solo Shuffle, 2v2, 3v3, Blitz BG. Track ratings and MMR by spec/class across multiple characters and accounts.
**Tech stack**: Lua, WoW Midnight 12.x addon API
**Namespace**: `local addonName, NXR = ...` — all public API on `NXR.*`
**SavedVariables**: `NelxRatedDB`

## Architecture

Addon organized around main modules:

- **Core / Event Handling** (`core/Core.lua`): Registers PvP events, extracts rating/MMR data, persists to SavedVariables
- **Challenge System** (`core/Challenges.lua`): Multi-spec, multi-bracket challenge CRUD with active challenge logic
- **Overlay** (`ui/Overlay.lua`): Movable frame showing spec rows from active challenge with ratings and tooltips
- **Main Frame** (`ui/MainFrame.lua`): Custom standalone frame (`/nxr`) with vertical sidebar nav (Home, Challenges, Characters, Settings, Import/Export)
- **Data Layer** (`core/Currency.lua`, `ui/ImportExportUI.lua`): Character tracking, challenge management, cross-account Import/Export
- **System** (`system/`): Party sync, tooltip hooks, WoW Settings integration, minimap button

## File Manifest

Manifest file: `NelxRated.toc`
Load order top-to-bottom. New files added in dependency order.
Three subdirectories: `core/` (data/logic), `ui/` (frames/panels), `system/` (WoW integration). See per-directory CLAUDE.md for details.

**Adding a new file:**
1. Pick subdir: pure logic → `core/`, frames/panels → `ui/`, WoW subsystem hooks → `system/`
2. Add path to `NelxRated.toc` in correct dependency position
3. Add entry to that subdir's `CLAUDE.md` (fn signatures, events, public API on `NXR.*`)

## Bracket Indices

`C_PvP.GetRatedBracketInfo()` bracket indices:

| Bracket | Index | Constant |
|---------|-------|----------|
| 2v2 Arena | 0 | `NXR.BRACKET_2V2` |
| 3v3 Arena | 1 | `NXR.BRACKET_3V3` |
| Blitz Battleground | 4 | `NXR.BRACKET_BLITZ` |
| Solo Shuffle | 7 | `NXR.BRACKET_SOLO_SHUFFLE` |


## Key Design Constraints

- **Multi-account support**: SavedVariables per-account. Import/Export bridges gap — imports must merge, never replace, receiving account's data.
- **Overlay opacity**: opacity=0 → tooltips disabled entirely.
- **Best character selection**: Per spec row in overlay, show only highest-rated character across challenge's selected brackets.
- **Active challenge**: Only one active at a time. Overlay shows specs from active challenge.
- **Challenge flexibility**: Multi-spec (individual specs), class challenges (all specs of class count), multi-bracket (rating in any selected bracket counts).

## Icon Atlas Notes

- `classicon-<class>` — flat circular style (Overlay, ChallengesUI)
- `raceicon-<race>-<gender>` — 3D embossed style
- Spec icons via `GetSpecializationInfoForClassID()` — 3D painted texture IDs
- No single atlas covers all three in same style. History tab: race icon + class-colored text only (no classicon).
- FontStrings cannot parent child frames/textures. To layer texture behind FontString, parent texture to containing frame and anchor points to FontString.

## WoW API Rules

Target version: WoW Midnight 12.x

Deprecated — flag and do not use:
- `GetPersonalRatedInfo()` → use `C_PvP.GetRatedBracketInfo(bracketIndex)`
- `FauxScrollFrame` → use `ScrollBox` + `WowScrollBoxList`
- `EasyMenu` / `UIDropDownMenuTemplate` → use `MenuUtil.CreateContextMenu()`
- `ARENA_WIN` / `ARENA_LOSE` events → use `PVP_RATED_STATS_UPDATE`
- Bare `"Frame"` as ScrollUtil template → use proper templates or `SetElementExtentCalculator`
- `MinimalSliderTemplate` (fires unexpected `OnShow`/`OnHide` callbacks) → use different template

Nil-safe requirements:
- `C_PvP.GetRatedBracketInfo()` can return nil or table with nil fields — always guard
- `GetSpecializationInfo(GetSpecialization())` returns nil with no spec — always guard
- `UnitName("player")` returns nil before player loads — only use in safe event handlers

## Stories and Epics

Active epic docs in `docs/epic-*.md`. Delete when complete — source of truth is code, git history preserves the rest.
Each epic: stories with acceptance criteria checkboxes.
Completed: `- [x]`. Incomplete: `- [ ]`.
Release checklist: `docs/curseforge-release-checklist.md`

Bugs tracked in `docs/bugs.md`. One entry per bug: description, file/line, repro steps if needed. Not in epic story docs. Not in GitHub issues.

## Lint Rules

### D1: Opacity/tooltip guard — `ui/`

opacity=0 → `EnableMouse(false)` on all interactive overlay frames.
Flag any path where opacity=0 but mouse input not disabled.

### D2: Import/export merge safety — `ui/ImportExportUI.lua`, `system/Sync.lua`

Import must NOT replace existing character entries from other accounts.
Merge by account key, not overwrite.
Flag any `NelxRatedDB.characters = importedData` replacement.

### D3: Character key format — `core/`

Keys in `NelxRatedDB` must be `"Name-Realm"` format.
Built with `UnitName("player") .. "-" .. GetRealmName()`, not just `UnitName("player")`.

### D4: Rating color threshold logic — `ui/`

Thresholds use `>=` (not `>`): `>= 0.8` orange, `>= 0.9` yellow, `>= 1.0` checkmark icon.
100% state must show icon texture, not Unicode.

### D5: Best-character selection — `ui/Overlay.lua`, `ui/ChallengesUI.lua`

Overlay cells show only highest-rated character per class/spec slot.
Verify max-rating selection step exists before populating overlay cells.

## Design System

### Colour Palette
```lua
local BG_BASE     = { r=0.04, g=0.04, b=0.06, a=0.95 }  -- near-black iron
local BG_RAISED   = { r=0.09, g=0.08, b=0.10, a=0.92 }  -- raised panels
local BG_HOVER    = { r=0.16, g=0.08, b=0.09, a=1.00 }  -- hover
local CRIMSON_BRIGHT = { r=0.88, g=0.22, b=0.18 }       -- highlights, active states
local CRIMSON_MID    = { r=0.60, g=0.15, b=0.12 }       -- borders, labels
local CRIMSON_DIM    = { r=0.28, g=0.08, b=0.06 }       -- inactive borders
local TEXT_TITLE  = { r=0.96, g=0.92, b=0.90 }          -- bright silver
local TEXT_BODY   = { r=0.78, g=0.75, b=0.73 }          -- steel-grey
local TEXT_DIM    = { r=0.48, g=0.45, b=0.43 }          -- muted/disabled
local TEXT_VALUE  = { r=1.00, g=1.00, b=1.00 }          -- pure white for numbers
local RATING_ORANGE  = { r=0.93, g=0.55, b=0.05 }       -- >= 80% of goal
local RATING_YELLOW  = { r=0.95, g=0.80, b=0.20 }       -- >= 90% of goal
-- 100% = checkmark icon texture, not a colour
```

### Typography
- Titles: `GameFontNormalLarge`
- Headers: `GameFontNormal`
- Body: `GameFontNormalSmall`
- Numbers: `GameFontHighlightLarge`
- Tiny: `GameFontNormalTiny`

### Spacing
```lua
local PAD_OUTER  = 12
local PAD_INNER  = 8
local PAD_TINY   = 4
local ROW_HEIGHT = 22
local ICON_SIZE  = 18
local BTN_H      = 24
local BORDER_W   = 1
```

### UI Rules
- One file per UI module under `ui/`
- Every function creating UI returns root frame
- Every interactive frame needs `OnEnter`/`OnLeave` + tooltip
- Draggable frames save position to SavedVariables
- Expose `:Refresh()` on every UI module
- `opacity=0` → `EnableMouse(false)` on all interactive overlay frames
- Rating colours: `>=0.8` orange, `>=0.9` yellow, `>=1.0` checkmark icon (not Unicode)
- All frames anonymous (nil name) unless needed for slash commands

## Release

Platform: CurseForge
Manifest: `NelxRated.toc`
Version field: `## Version:`

Packaging ignore list:
  - `.claude`
  - `.github`
  - `docs`
  - `.blocked-paths`
  - `.gitignore`
  - `CLAUDE.md`

Manual steps before any release:
1. Verify interface number in-game: `/run print(select(4, GetBuildInfo()))`
2. Confirm version in TOC before tagging
3. In-game smoke test: rated arena → rating captured, overlay updates
4. Test Import/Export: merge across accounts without overwriting

## README

Managed by `/update-readme` (runs inside `/ship`). Don't edit manually.

## Skills & Automation

Agents and skills from **nelx-claude** marketplace (`Nelxbuilds/nelx-claude`).

Available plugins (agents): `implement-story`, `lua-linter`, `release-prep`, `review-addon`, `write-story`
Available plugins (skills): `ship`, `update-readme`, `wow-api-research`, `wow-ui-designer`, `bug`

Key skill notes:
- `/update-readme` — syncs README.md from epic docs; runs automatically inside `/ship`
- `/write-story` — interactive story writer; asks clarifying questions, produces story doc, does NOT write code
- `/caveman-commit` — ultra-compressed commit message generator; use when committing
- Don't manually update README before release; `/ship` handles it

## Working Style

- Bug fixes: read bug, read relevant code, fix it. No agents or linters unless asked.
- Agents (implement-story, lua-linter, etc.) only when explicitly asked.
- Don't re-read files already in context.
- Keep responses short. No summaries — diff speaks for itself. Don't narrate changes after making them.

## SavedVariables

All data in `NelxRatedDB` (declared in TOC). Structure after `InitDB()`:

```lua
NelxRatedDB.settings        -- User preferences (opacity, overlay lock, account name, etc.)
NelxRatedDB.characters      -- Tracked character rating data
NelxRatedDB.challenges      -- Challenge definitions
NelxRatedDB.overlayPosition -- Saved overlay frame position
NelxRatedDB.schemaVersion   -- DB migration version
```