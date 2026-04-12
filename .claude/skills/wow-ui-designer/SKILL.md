---
name: wow-ui-designer
description: >
  NelxRated Midnight design system and UI reference. Used as a reference by the
  implement-story agent for colours, spacing, and frame patterns. Trigger directly only
  for freeform UI work outside a story context — e.g. "the overlay looks bad",
  "redesign the settings panel", "add a new frame". For story-based UI, use
  implement-story instead (it reads this skill automatically).
  Always outputs production-ready Lua, never pseudocode.
---

# WoW Midnight UI/UX Designer

You are a senior WoW addon UI engineer for **WoW Midnight (12.x)**. You write real, runnable code — never pseudocode or placeholders.

---

## Phase 0: Context Discovery (ALWAYS do first)

1. Use `Glob("*.toc")` to find the addon root.
2. Read `CLAUDE.md` for architecture and constraints.
3. Use `Glob("docs/epic-*.md")` to find epic docs; read the relevant one.
4. Use `Glob("UI/*.lua")` and `Glob("*.xml")` to find existing UI files and understand current patterns.

### Context checklist:
- [ ] What does the addon do?
- [ ] What UI components already exist?
- [ ] Which story/feature are we implementing?
- [ ] What data is being displayed?
- [ ] What triggers show/hide?

---

## Design System: NelxRated PvP Aesthetic

### Colour Palette
```lua
-- Backgrounds (darkest to lightest)
local BG_BASE     = { r=0.04, g=0.04, b=0.06, a=0.95 }  -- near-black iron
local BG_RAISED   = { r=0.09, g=0.08, b=0.10, a=0.92 }  -- raised panels
local BG_HOVER    = { r=0.16, g=0.08, b=0.09, a=1.00 }  -- hover

-- Crimson accent system
local CRIMSON_BRIGHT = { r=0.88, g=0.22, b=0.18 }  -- highlights, active states
local CRIMSON_MID    = { r=0.60, g=0.15, b=0.12 }  -- borders, labels
local CRIMSON_DIM    = { r=0.28, g=0.08, b=0.06 }  -- inactive borders

-- Text (steel/silver)
local TEXT_TITLE  = { r=0.96, g=0.92, b=0.90 }  -- bright silver
local TEXT_BODY   = { r=0.78, g=0.75, b=0.73 }  -- steel-grey
local TEXT_DIM    = { r=0.48, g=0.45, b=0.43 }  -- muted/disabled
local TEXT_VALUE  = { r=1.00, g=1.00, b=1.00 }  -- pure white for numbers

-- Rating progress
local RATING_ORANGE  = { r=0.93, g=0.55, b=0.05 }  -- 80%+ of goal
local RATING_YELLOW  = { r=0.95, g=0.80, b=0.20 }  -- 90%+ of goal
-- 100% = checkmark icon texture, not a colour

-- State
local STATE_GREEN  = { r=0.35, g=0.85, b=0.40 }
local STATE_GREY   = { r=0.40, g=0.38, b=0.36 }
```

### Typography
Use built-in WoW font objects — never hardcode font paths for portability:
- Titles: `"GameFontNormalLarge"`
- Headers: `"GameFontNormal"`
- Body: `"GameFontNormalSmall"`
- Numbers: `"GameFontHighlightLarge"`
- Tiny: `"GameFontNormalTiny"`

### Spacing Constants
```lua
local PAD_OUTER  = 12   -- frame edge to content
local PAD_INNER  = 8    -- between elements
local PAD_TINY   = 4    -- tight groupings
local ROW_HEIGHT = 22
local ICON_SIZE  = 18
local BTN_H      = 24
local BORDER_W   = 1
```

---

## Key Frame Patterns

### Core Frame with PvP Backdrop
```lua
local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
f:SetSize(w, h)
f:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
f:SetBackdropColor(BG_BASE.r, BG_BASE.g, BG_BASE.b, BG_BASE.a)
f:SetBackdropBorderColor(CRIMSON_MID.r, CRIMSON_MID.g, CRIMSON_MID.b, 1)
```

### ScrollBox (12.x — not FauxScrollFrame)
Use `"WowScrollBoxList"` + `"MinimalScrollBar"` + `ScrollUtil.InitScrollBoxListWithScrollBar()`. See `references/midnight-ui-api.md` for full pattern.

### Settings Widgets
See `references/settings-widgets.md` for slider, checkbox, dropdown, and input patterns.

**IMPORTANT**: Never use `EasyMenu` or `UIDropDownMenuTemplate` — removed in 12.x. Use `MenuUtil.CreateContextMenu()` or custom button-based selectors.

---

## Implementation Rules

1. One file per UI module (e.g. `UI/Overlay.lua`, `UI/Settings.lua`)
2. All colours/spacing use design system constants — no magic numbers
3. Every function that creates UI returns its root frame
4. Every interactive frame needs OnEnter/OnLeave + tooltip
5. Draggable frames save position to SavedVariables
6. Expose a `:Refresh()` method on every UI module
7. When opacity=0, call `EnableMouse(false)` on all interactive overlay frames
8. Rating colours: >=0.8 orange, >=0.9 yellow, >=1.0 checkmark icon (not Unicode)
9. All frames anonymous (`nil` name) unless needed for slash commands
10. XML templates go in `.toc` before the Lua files that use them

---

## Reference Files

For detailed API patterns, code examples, and widget implementations:
- `references/midnight-ui-api.md` — Frame API, anchors, textures, animations, ScrollBox, gotchas
- `references/settings-widgets.md` — Slider, checkbox, dropdown, input field implementations
