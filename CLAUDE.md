# CLAUDE.md

Research the codebase before editing. Never change code you haven't read.

## Project Overview

NelxRated is a World of Warcraft addon that tracks PvP ratings across characters and specs. It supports Solo Shuffle, 2v2, 3v3, and Blitz Battleground, and displays progress toward user-defined rating challenges via a movable overlay.

## Architecture

The addon is organized around these main modules:

- **Core / Event Handling**: Registers for PvP events, extracts rating/MMR data, persists to SavedVariables
- **Challenge System**: Multi-spec, multi-bracket challenge CRUD with active challenge logic
- **Overlay**: Movable frame showing spec rows from the active challenge with ratings and tooltips
- **Main Frame**: Custom standalone frame (`/nxr`) with vertical sidebar navigation (Home, Challenges, Characters, Settings, Import/Export)
- **Data Layer**: Character tracking, challenge management, and cross-account Import/Export

## Bracket Indices

These are the `C_PvP.GetRatedBracketInfo()` bracket indices:

| Bracket | Index | Constant |
|---------|-------|----------|
| 2v2 Arena | 0 | `NXR.BRACKET_2V2` |
| 3v3 Arena | 1 | `NXR.BRACKET_3V3` |
| Blitz Battleground | 4 | `NXR.BRACKET_BLITZ` |
| Solo Shuffle | 7 | `NXR.BRACKET_SOLO_SHUFFLE` |

**Important**: The Blitz BG index (4) should be verified in-game. Use `/dump C_PvP.GetRatedBracketInfo(4)` to confirm.

## Key Design Constraints

- **Multi-account support**: SavedVariables are per-account. Import/Export bridges this gap — imports must merge, never replace, the receiving account's data.
- **Overlay opacity**: When opacity is 0, tooltips must be disabled entirely.
- **Color thresholds**: 80% of goal -> orange, 90% -> yellow, 100% -> checkmark icon (not a Unicode character).
- **Best character selection**: Per spec row in the overlay, display only the highest-rated character across the challenge's selected brackets.
- **Active challenge**: Only one challenge is active at a time. The overlay shows specs from the active challenge.
- **Challenge flexibility**: Challenges support multi-spec selection (individual specs), class challenges (all specs of a class count), and multi-bracket selection (rating in any selected bracket counts).
- **PvP crimson theme**: UI uses crimson accent colors (`CRIMSON_BRIGHT`/`MID`/`DIM`) for borders and active states. Gold is used only for section title text.

## Icon Atlas Notes

- `classicon-<class>` — flat circular style (used in Overlay, ChallengesUI)
- `raceicon-<race>-<gender>` — 3D embossed style
- Spec icons via `GetSpecializationInfoForClassID()` — 3D painted texture IDs
- No single atlas covers all three in same style. History tab: race icon + class-colored text only (no classicon).
- FontStrings cannot parent child frames/textures. To layer texture behind FontString, parent texture to the containing frame and anchor its points to the FontString.

## WoW 12.x API Notes

- `EasyMenu` and `UIDropDownMenuTemplate` are **removed** in Midnight 12.x. Use `MenuUtil.CreateContextMenu()` or custom button-based selectors.
- `ARENA_WIN` / `ARENA_LOSE` events do **not exist**. Use `PVP_RATED_STATS_UPDATE`.
- `C_PvP.GetRatedBracketInfo(bracketIndex)` may be nil in some contexts — always nil-guard.
- For scroll lists, use `ScrollUtil` with proper templates or `SetElementExtentCalculator`, not bare `"Frame"` as a template name.
- Slider: `MinimalSliderTemplate` fires `OnShow`/`OnHide` callbacks — register them or use a different template.

## Bug Tracking

Bugs are tracked in epic story docs (`docs/epic-N-*.md`) as unchecked acceptance criteria. Do not maintain a separate bug file. Do not open GitHub issues for bugs found during development.

## Skills & Automation

- Project skills live in `.claude/skills/` (ship, update-readme, wow-ui-designer, wow-api-research)
- `/update-readme` — syncs README.md from epic docs; runs automatically inside `/ship`
- `/write-story` — system agent (not a local skill); interactive story writer; asks clarifying questions, produces story doc, does NOT write code
- `/caveman-commit` — ultra-compressed commit message generator; use when committing
- Don't manually update README before a release; `/ship` handles it via Step 4.5

## Working Style

- For bug fixes: read the bug, read the relevant code, fix it. Don't spawn agents or run linters unless asked.
- Only use agents (implement-story, lua-linter, etc.) when explicitly asked or for multi-file tasks.
- Don't re-read files already in context.
- Keep responses short. No summaries of what was done — the diff speaks for itself.

## SavedVariables

The addon persists all data in `NelxRatedDB` (declared in the TOC). Structure after `InitDB()`:

```lua
NelxRatedDB.settings        -- User preferences (opacity, overlay lock, account name, etc.)
NelxRatedDB.characters      -- Tracked character rating data
NelxRatedDB.challenges      -- Challenge definitions
NelxRatedDB.overlayPosition -- Saved overlay frame position
NelxRatedDB.schemaVersion   -- DB migration version (currently 1)
```

