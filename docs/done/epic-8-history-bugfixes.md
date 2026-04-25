# Epic 8 — History Bug Fixes & Polish

Fix visual bugs and inconsistencies on the History tab: goal label readability, dropdown styling alignment, z-order issues, and icon consistency.

**Depends on**: Epic 7 (history improvements)

---

## Story 8-1 — Add Background Behind Goal Label to Prevent Line Overlap

**Goal**: When the rating data line passes through the goal line's Y position, the goal label text becomes unreadable. Add a semi-transparent dark background behind the goal label so it stays legible.

**Bug Reference**: `bugs/open-bugs.md` — "Goal label overlaps with drawn line"
**Screenshot**: `bugs/history-goal-overlap-with-line.png`

**Acceptance Criteria**:

- [x] A dark semi-transparent texture (`goalLabelBg`) is created behind `goalLabel`, covering the text extents plus at least 2px padding on each side
- [x] Background color is near-black with sufficient alpha to occlude the data line (e.g., `0, 0, 0, 0.85`)
- [x] `goalLabelBg` draw layer is `"ARTWORK"` (below `goalLabel` at `"OVERLAY"`), so gold text renders on top
- [x] `goalLabelBg` is anchored to `goalLabel`'s four points with negative insets — auto-resizes with label text width
- [x] `goalLabelBg` is shown/hidden in sync with `goalLabel` at all three code paths: line 154 (clear), line 306 (show), line 309 (hide)
- [x] No visual change to goal line or data line rendering

**Technical Hints**:

- Create `goalLabelBg` as a `Texture` parented to `graphFrame`, anchor all four points to `goalLabel` with -2px insets
- Declare `goalLabelBg` alongside `goalLabel` at line 29 as a local

---

## Story 8-2 — Unify History Tab Dropdown Styles to Custom Crimson Design

**Goal**: Replace `MenuUtil.CreateContextMenu()` popups (Spec and Bracket dropdowns) with the same custom crimson dropdown style the Character selector uses.

**Bug Reference**: `bugs/open-bugs.md` — "Two different dropdown visualisation"
**Screenshot**: `bugs/history-two-different-dropdown.png`

**Acceptance Criteria**:

- [x] Spec and Bracket dropdowns use identical styling to the existing `charDropdown` (lines 558-567): same `BackdropTemplate`, backdrop colors, `CRIMSON_DIM` border, `DIALOG` strata, crimson hover highlight
- [x] `MenuUtil.CreateContextMenu()` is no longer called anywhere in `HistoryUI.lua` (remove calls at lines 622 and 636)
- [x] Each dropdown anchors `TOPLEFT` to button's `BOTTOMLEFT` with 2px gap, matching `charDropdown`
- [x] Clicking an entry updates the filter variable, button label, calls `RefreshGraph()` (and `UpdateSpecButtonState()` for bracket), and closes the dropdown
- [x] Only one dropdown open at a time — opening any dropdown closes the others via shared `ddClickCatcher`
- [x] Entry text uses `GameFontNormal`, left-justified with 6px horizontal padding, same `ENTRY_HEIGHT` as `charDropdown`
- [x] Spec dropdown stays disabled (`alpha 0.4`) for non-per-spec brackets

**Technical Hints**:

- Extract a reusable dropdown helper from the `charDropdown` pattern to avoid duplicating frame creation three times
- Reuse the existing `ddClickCatcher` — extend `HideCharDropdown` to close all three dropdowns

---

## Story 8-3 — Fix Character Dropdown Rendering Behind Graph Frame

**Goal**: Remove the graph container's visual backdrop so the character dropdown is never obscured by it.

**Bug Reference**: `bugs/open-bugs.md` — "History character dropdown behind frame"
**Screenshot**: `bugs/history-character-dropdown-behind-frame.png`

**Acceptance Criteria**:

- [x] Remove `SetBackdrop()`, `SetBackdropColor()`, `SetBackdropBorderColor()` calls from `graphFrame` (lines 690-696)
- [x] Remove `"BackdropTemplate"` mixin from `graphFrame`'s `CreateFrame` call (line 687)
- [x] Existing axis border lines (`axisL`, `axisB`) remain unchanged — they provide the graph area's visual boundary
- [x] All dropdowns render above `graphFrame` content when open
- [x] Graph elements (axis lines, grid lines, data lines, dots, labels, goal line, placeholder) render unchanged

**Technical Hints**:

- Child elements use explicit draw layers (`ARTWORK`, `BACKGROUND`, `OVERLAY`) so removing backdrop has no effect on them

---

## Story 8-4 — Align Character Dropdown Button and Entry Icon Display

**Goal**: Fix two related issues: (1) the selected character button shows only `[class-icon] Name - Realm` while dropdown entries show `[race-icon][class-icon] Name - Realm`, and (2) `classicon-*` (flat) and `raceicon-*` (3D) have mismatched visual styles. Solve both by using only race icon + class-colored text everywhere.

**Bug Reference**: `bugs/open-bugs.md` — "History character entry" and "Two different styles of icons"
**Screenshot**: `bugs/history-character-dropdown-behind-frame.png`

**Acceptance Criteria**:

- [x] `FormatCharDisplay()` (line 349) no longer includes `classicon-*` atlas markup — remove the class icon line (lines 357-359)
- [x] `FormatCharDisplay()` output format: `[race-icon] ColoredName - Realm` when race data available, `ColoredName - Realm` when missing
- [x] `FormatCharButtonLabel()` (line 369) no longer includes `classicon-*` atlas markup — remove class icon line (lines 372-374)
- [x] `FormatCharButtonLabel()` adds race icon atlas (`raceicon-<raceFileName>-<gender>`, lowercased, 14x14) when `char.raceFileName` and `char.gender` are available, using same gender mapping as `FormatCharDisplay()` (2=male, 3=female; nil/1 omits icon)
- [x] `FormatCharButtonLabel()` output format: `[race-icon] ColoredName - Realm` when race data available, `ColoredName - Realm` when missing, `"Select"` when `char` is nil
- [x] Class-colored text (`RAID_CLASS_COLORS` colorStr wrapping) remains in both functions
- [x] Both dropdown entries and selected button now display identically

**Out of Scope**:

- Changing icons outside History tab (overlay, challenges use `classicon-*` in different context)
- Adding spec icons to character dropdown

---

## Story 8-5 — Fix Goal Label Strikethrough (Lines Render Through Background)

**Goal**: The `goalLabelBg` background texture does not block lines from passing through the goal label because the bg is at `"ARTWORK"` draw layer while lines render above it. Fix the draw order so the background actually occludes both the goal line and data lines.

**Root Cause**:

Two separate problems stack:

1. `goalLine` is created with `graphFrame:CreateLine()` — defaults to `"OVERLAY"` layer. `goalLabelBg` is `"ARTWORK"` on the same frame. OVERLAY renders above ARTWORK → goal line passes through bg.
2. Data lines live on `canvas` (a child Frame of `graphFrame`). Child frames always render above parent frame content regardless of draw layer → canvas content (data lines, dots) always passes through any texture on `graphFrame`.

**Desired Layer Order (back to front)**:

1. `graphFrame` background / axis lines
2. `canvas` content — grid lines, data lines, dots
3. `goalLine` — renders above data
4. `goalLabelBg` — occludes goal line at label position
5. `goalLabel` text — on top of bg

**Acceptance Criteria**:

- [x] `goalLine` remains on `graphFrame` at `"OVERLAY"` draw layer — renders above canvas content (child frame) because goal line is on a dedicated sub-frame above canvas; OR `goalLine` is moved to a sub-frame with frame level between canvas and the label frame so it renders above data lines
- [x] `goalLabel` and `goalLabelBg` live in a dedicated `goalLabelFrame = CreateFrame("Frame", nil, graphFrame)` with frame level higher than both `canvas` and the goal line's frame — guarantees label+bg sit on top of everything
- [x] Within `goalLabelFrame`: bg texture at `"BACKGROUND"`, label fontstring at `"OVERLAY"` — label text renders on top of bg
- [x] `goalLabelFrame` sized to fill `graphFrame` (simplest: `SetAllPoints(graphFrame)`) — zero visual impact, positions of label/bg still driven by anchor points to `graphFrame`
- [x] `goalLabel` anchored to `graphFrame` (via `goalLabelFrame` which fills graphFrame — same anchor math as current)
- [x] `goalLabelBg` anchored to `goalLabel` as before (TOPLEFT/BOTTOMRIGHT with ±2px insets)
- [x] Show/hide sync of bg, label, and label frame unchanged — hide all three when no goal
- [x] Goal line still visually appears above data lines and dots

**Technical Hints**:

- Create `goalLabelFrame` after `canvas` is created (so `canvas:GetFrameLevel()` is known)
- Frame level: `goalLabelFrame:SetFrameLevel(canvas:GetFrameLevel() + 20)`
- If `goalLine` still renders behind canvas content, move it to a separate `goalLineFrame` at `canvas:GetFrameLevel() + 10` and draw the line there
- `goalLabel = goalLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")`
- `goalLabelBg = goalLabelFrame:CreateTexture(nil, "BACKGROUND")`

---

## Story 8-6 — Fix Dropdown Z-Order (Renders Behind Graph Dots)

**Goal**: All three history dropdowns (Character, Spec, Bracket) occasionally render behind the graph dot frames because both use `DIALOG` strata and dot frames can have higher frame level than the dropdown frame. Fix by elevating dropdown strata above `DIALOG`.

**Root Cause**:

- Dot frames: `CreateFrame("Frame", nil, canvas)` + `SetFrameStrata("DIALOG")` — inherits canvas frame level + offset
- Dropdowns: `SetFrameStrata("DIALOG")` — parented to filter row or button parent, lower base frame level
- Within same strata, highest frame level wins → dots win → dropdown hidden behind dots

**Acceptance Criteria**:

- [x] All three dropdown frames (`charDropdown`, `specDropdown`, `bracketDropdown`) use `SetFrameStrata("TOOLTIP")` instead of `"DIALOG"`
- [x] `CreateOrGetSimpleDropdown()` sets strata to `"TOOLTIP"` (line 564)
- [x] `charDropdown` creation block sets strata to `"TOOLTIP"` (line 654)
- [x] `ddClickCatcher` strata updated to match dropdown strata (`"TOOLTIP"`) and level set to `dropdown:GetFrameLevel() - 1` — existing logic at lines 619-620 and 671-672 already handles this dynamically, no change needed there
- [x] Dropdowns render visibly above graph area (dots, lines) when open
- [x] No other behavioral changes (click-to-close, entry selection, scroll) affected

---

## Story 8-7 — Align Left Padding Between Selected Button Label and Dropdown Entries

**Deferred** — minor visual polish, low risk of regression on other button usages. Revisit after 8-5 and 8-6 ship.

**Goal**: The selected character button label uses 4px left padding while dropdown list entries use 6px. Unify so text doesn't jump horizontally when opening the dropdown.

**Root Cause**:

- `charButton.label` overrides to `LEFT, 4, 0` (line 777)
- Dropdown entries use `LEFT, 6, 0` (lines 466, 582)
- Spec/bracket buttons use `NXR.CreateNXRButton` — internal padding needs audit before changing

**Acceptance Criteria**:

- [ ] Audit `NXR.CreateNXRButton` label anchor before any change — confirm spec/bracket button labels are not shared with other UI elements
- [ ] `charButton.label:SetPoint("LEFT", 4, 0)` → `6` (line 777)
- [ ] Spec and bracket button label left offset also aligned to 6px if safe
- [ ] Dropdown entries unchanged (lines 466, 582)
- [ ] No regression on other buttons using `NXR.CreateNXRButton`
