# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Research the codebase before editing. Never change code you haven't read.

## Project Overview

NelxRated is a World of Warcraft addon that tracks PvP ratings across characters and specs. It supports Solo Shuffle, 2v2, 3v3, and Blitz Battleground, and displays progress toward user-defined rating challenges via a movable overlay.

## WoW Addon Development

WoW addons are written in **Lua** and use the WoW client API. Key concepts:

- **TOC file** (`NelxRated.toc`): Declares addon metadata and file load order
- **SavedVariables**: WoW's persistence mechanism for addon data, declared in the TOC file and accessed as globals
- **Events**: Addons react to WoW game events (e.g., `PVP_RATED_STATS_UPDATE`, `PLAYER_ENTERING_WORLD`)
- **Frames**: UI elements created via `CreateFrame()` and positioned/styled with the WoW UI API

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

## WoW 12.x API Notes

- `EasyMenu` and `UIDropDownMenuTemplate` are **removed** in Midnight 12.x. Use `MenuUtil.CreateContextMenu()` or custom button-based selectors.
- `ARENA_WIN` / `ARENA_LOSE` events do **not exist**. Use `PVP_RATED_STATS_UPDATE`.
- `C_PvP.GetRatedBracketInfo(bracketIndex)` may be nil in some contexts — always nil-guard.
- For scroll lists, use `ScrollUtil` with proper templates or `SetElementExtentCalculator`, not bare `"Frame"` as a template name.
- Slider: `MinimalSliderTemplate` fires `OnShow`/`OnHide` callbacks — register them or use a different template.

## Bug Tracking

Bugs are tracked locally in `docs/bugs/bugs.md`. When you find a bug (via verify-story, lua-linter, or in-game testing), add an entry there using the template in that file. Do not open GitHub issues for bugs found during development.

## Working Style

- For bug fixes: read the bug, read the relevant code, fix it. Don't spawn agents or run linters unless asked.
- Keep responses short. No summaries of what was done — the diff speaks for itself.

## Token Efficiency

- Simple bug fixes (1-3 lines) should NOT spawn agents. Use direct Read + Edit.
- Only use agents (implement-story, lua-linter, etc.) when explicitly asked or for multi-file tasks.
- Don't re-read files already in context.

## SavedVariables

The addon persists all data in `NelxRatedDB` (declared in the TOC). Structure after `InitDB()`:

```lua
NelxRatedDB.settings        -- User preferences (opacity, overlay lock, account name, etc.)
NelxRatedDB.characters      -- Tracked character rating data
NelxRatedDB.challenges      -- Challenge definitions
NelxRatedDB.overlayPosition -- Saved overlay frame position
NelxRatedDB.schemaVersion   -- DB migration version (currently 1)
```

## Addon Namespace

The shared addon table is `NXR` (changed from `NXA`). All modules receive it via `local addonName, NXR = ...`.
