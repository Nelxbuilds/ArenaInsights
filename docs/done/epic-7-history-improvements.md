# Epic 7 — History Tab Improvements

Polish the History tab's character selector dropdown and fix the goal label rendering bug. Improvements include class-colored entries with icons, class-based ordering, filtering out characters with no history, auto-selecting the first available bracket on character change, and making the dropdown scrollable.

**Depends on**: Epic 6 (rating history & graph)

---

## Story 7-1 — Capture Race & Gender on Character Info Update

**Goal**: Store race and gender alongside existing character data so race icons can be displayed in dropdowns.

**Acceptance Criteria**:

- [x] `UpdateCharacterInfo()` calls `UnitRace("player")` and stores `char.raceFileName` (the English token, e.g. `"Human"`, `"Orc"`)
- [x] `UpdateCharacterInfo()` calls `UnitSex("player")` and stores `char.gender` (2 = male, 3 = female)
- [x] Fields are lazily added — no schema migration needed; characters without these fields simply won't show a race icon until they log in
- [x] Existing character data (brackets, specBrackets, ratingHistory) is not affected

**Technical Hints**:

- Same lazy pattern as other char fields — just assign in `UpdateCharacterInfo()`
- `UnitSex()` returns 1 (unknown), 2 (male), or 3 (female)

---

## Story 7-2 — Class-Colored Dropdown Entries with Icons

**Goal**: Each entry in the History tab's character selector dropdown shows a class icon and class-colored character name.

**Acceptance Criteria**:

- [x] Each dropdown entry displays: `[class-icon] CharacterName - RealmName`
- [x] If `char.raceFileName` and `char.gender` are available, prepend a race icon before the class icon: `[race-icon][class-icon] CharacterName - RealmName`
- [x] The character name label uses the WoW class color from `RAID_CLASS_COLORS[char.classFileName]`
- [x] Class icons use the standard atlas `classicon-<classFileName>` (lowercased)
- [x] Race icons use the standard atlas `raceicon-<raceFileName>-<male|female>` (lowercased) — only shown if data is available
- [x] If race data is missing, gracefully fall back to class icon only (no error, no placeholder)

**Technical Hints**:

- Atlas names are lowercase, e.g. `"classicon-warrior"`, `"raceicon-human-male"`
- Gender mapping: 2 -> `"male"`, 3 -> `"female"`; if gender is nil or 1, skip race icon

---

## Story 7-3 — Class-Based Dropdown Ordering

**Goal**: Order the character dropdown entries by WoW class order, matching the sort used in the overlay and challenge UI.

**Acceptance Criteria**:

- [x] Dropdown entries are sorted using the same class order as `NXR.sortedClassIDs` (populated by `GetNumClasses()` iteration order)
- [x] Within the same class, characters are sorted alphabetically by name
- [x] Sort is applied every time the dropdown is populated/refreshed

**Technical Hints**:

- Build a classID -> sortIndex lookup from `NXR.sortedClassIDs` for O(1) comparison
- Characters store `classFileName`; map to classID via `NXR.classData` or build a reverse lookup

---

## Story 7-4 — Filter Dropdown to Characters with History

**Goal**: Only show characters in the dropdown that have at least one history entry to display.

**Acceptance Criteria**:

- [x] Characters without any `ratingHistory` entries are excluded from the dropdown
- [x] A character counts as having history if `char.ratingHistory` is non-nil and contains at least one non-empty array
- [x] If the previously selected character no longer has history (edge case), fall back to the first available entry or show the placeholder
- [x] If no characters have history at all, the dropdown shows a disabled entry or the graph area shows the existing "Play rated games to build history" placeholder

**Technical Hints**:

- Simple check: iterate `char.ratingHistory` keys; if any key has `#array > 0`, include the character

---

## Story 7-5 — Auto-Select First Available Bracket on Character Change

**Goal**: When the user selects a different character in the dropdown, automatically switch to the first bracket that has history data, using a priority order.

**Acceptance Criteria**:

- [x] On character selection change, determine the first bracket with available history using priority: Solo Shuffle > 3v3 > 2v2 > Blitz BG
- [x] For per-spec brackets (Solo Shuffle, Blitz), also auto-select the first spec that has history for that bracket
- [x] The bracket and spec selectors update to reflect the auto-selection
- [x] The graph refreshes immediately with the new selection
- [x] If no bracket has history (shouldn't happen given Story 7-4 filtering), show the placeholder

**Technical Hints**:

- Priority order as bracket indices: `{ NXR.BRACKET_SOLO_SHUFFLE, NXR.BRACKET_3V3, NXR.BRACKET_2V2, NXR.BRACKET_BLITZ }`
- For per-spec brackets, iterate `char.ratingHistory` keys matching the pattern `specID..":"..bracketIndex`

---

## Story 7-6 — Scrollable Character Dropdown

**Goal**: Make the character selector dropdown scrollable so it handles large numbers of tracked characters gracefully.

**Acceptance Criteria**:

- [x] The dropdown displays up to `MAX_VISIBLE_ENTRIES` (12) entries before showing a scrollbar
- [x] When the list exceeds 12 entries, a vertical scrollbar appears
- [x] Scrolling is smooth and supports mouse wheel
- [x] The dropdown remains functional and styled consistently with fewer than 12 entries (no unnecessary scrollbar)
- [x] `MAX_VISIBLE_ENTRIES` is defined as a local constant for easy adjustment
- [x] Uses the PvP crimson design system for scrollbar styling

**Technical Hints**:

- Use `ScrollUtil` with a proper template (not bare `"Frame"`) per the 12.x API constraints
- Set the dropdown height dynamically: `min(#entries, MAX_VISIBLE_ENTRIES) * entryHeight`

---

## Story 7-7 — Fix Goal Label Out-of-Bounds Rendering

**Goal**: Fix the bug where the goal line label renders outside the graph container's bounds.

**Bug Reference**: `bugs/open-bugs.md` — "Goal label is out of bounds"
**Screenshot**: `bugs/history-goal-label.png`

**Acceptance Criteria**:

- [x] The goal line rating label is fully contained within the graph frame's boundaries
- [x] If the goal line is near the top edge, the label is positioned below the line (or inset) rather than above/outside
- [x] If the goal line is near the bottom edge, the label is positioned above the line rather than below/outside
- [x] The label remains readable and does not overlap with axis labels
- [x] The goal line itself is clipped to the graph area (does not extend beyond axis borders)

**Technical Hints**:

- Clamp the label's Y anchor so it stays within `[0, graphHeight]`
- Consider setting the graph container's clipping: `graphFrame:SetClipsChildren(true)` as a simple fix for the line itself
