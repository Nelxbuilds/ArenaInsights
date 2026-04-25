# Epic 3 — Main Frame & Navigation

A custom standalone frame opened via `/nxr`, with a vertical sidebar navigation. All addon functionality lives inside this frame: Challenges, Characters, Settings, and Import/Export. The Challenges tab content already exists from Epic 2 and is embedded here.

**Depends on**: Epic 2 (Challenges panel)

---

## Story 3-1 — Main Frame & Vertical Sidebar Navigation

**Goal**: Create the main NelxRated frame with a vertical sidebar for tab navigation. Tabs switch content panels; only one is visible at a time.

**Acceptance Criteria**:

- [x] `/nelxrated` and `/nxr` open the main frame
- [x] `/nxr help` prints available commands
- [x] Pressing Escape closes the frame (`tinsert(UISpecialFrames, ...)`)
- [x] The frame is draggable, sized ~700x520, centered on first open
- [x] A vertical sidebar on the left (~140px wide) lists navigation items: Challenges, Characters, Settings, Import/Export
- [x] Each nav item highlights on hover and shows an active state (crimson accent) for the selected tab
- [x] Clicking a nav item shows only that tab's content panel; all others are hidden
- [x] The frame uses the PvP crimson design system (crimson borders, dark background, gold title)
- [x] The addon title "NelxRated" appears at the top of the sidebar
- [x] Default selected tab on open: Challenges
- [x] The existing `NXR.CreateChallengesPanel()` is embedded as the Challenges tab content

**Technical Hints**:

- Refactor the current `NXR.ToggleMainFrame()` to use the new layout
- Sidebar background should be slightly lighter than the main content area (`BG_RAISED`)
- Nav items are buttons with left-aligned text, full sidebar width
- Active nav item: crimson left border accent or crimson background tint
- Content area fills the space to the right of the sidebar
- Build reusable widget helpers: `CreateNXRButton`, `CreateNXRInput` for use across tabs
- Extract a shared `NXR_BACKDROP` table to avoid duplicating the backdrop definition

---

## Story 3-2 — Characters Tab

**Goal**: Show all tracked characters with their ratings, and allow removal.

**Acceptance Criteria**:

- [x] Lists every character in `NelxRatedDB.characters`
- [x] Each row shows: name-realm, account, class/spec, and rating per bracket (2v2, 3v3, Blitz BG, Solo Shuffle)
- [x] Each row has a Remove button that deletes the character from `NelxRatedDB`
- [x] Removing a character does not affect challenges
- [x] Empty state: "No characters tracked yet. Play a rated game to start tracking automatically."
- [x] The list refreshes immediately after removal (no panel reload needed)

**Technical Hints**:

- Use `ScrollUtil.InitScrollBoxListWithScrollBar` with a proper template or `SetElementExtentCalculator`
- Iterate `NelxRatedDB.characters` with `pairs()` since keys are `"Name-Realm"` strings

---

## Story 3-3 — Settings Tab

**Goal**: Let the user configure: account name, overlay opacity (in-arena, out-of-arena), and overlay background toggle.

**Acceptance Criteria**:

- [x] Account name text input, saved to `NelxRatedDB.settings.accountName` with a Save button
- [x] Opacity slider for inside arena (0-1, step 0.05), saved to `NelxRatedDB.settings.opacityInArena`
- [x] Opacity slider for outside arena (0-1, step 0.05), saved to `NelxRatedDB.settings.opacityOutOfArena`
- [x] Checkbox: "Show overlay background & border", saved to `NelxRatedDB.settings.showOverlayBackground`
- [x] All settings apply immediately (opacity updates live, background toggle updates live)
- [x] Settings persist across UI reloads

**Technical Hints**:

- Opacity sliders notify `NXR.Overlay.OnOpacityChanged()` if the overlay module is loaded
- Background checkbox notifies `NXR.Overlay.OnBackgroundChanged()`
- Check slider template compatibility — `MinimalSliderTemplate` may fire unregistered callbacks in 12.x; test alternatives if needed

---

## Story 3-4 — Import/Export Tab

**Goal**: Let users export character data as a copyable string, and import/merge character data from another account.

**Acceptance Criteria**:

- [x] **Export section**: clicking Export serializes all characters into a human-readable text format and displays it in a read-only EditBox
- [x] The export format includes: name, realm, account, class, spec, and per-bracket rating/MMR
- [x] The export EditBox supports select-all + copy; typing does not modify the content
- [x] **Import section**: an editable EditBox for pasting, plus an Import button
- [x] Import deserializes the string and merges characters into `NelxRatedDB.characters`
- [x] Merge rule: if a character with the same name+realm already exists, it is **skipped** (not overwritten)
- [x] New characters are added as new records
- [x] Invalid/corrupt input shows an error message (not a Lua error)
- [x] After import, the Characters tab and overlay refresh
- [x] Status feedback: "Imported X character(s), skipped Y duplicate(s)."
- [x] The format includes a header line (e.g. `NelxRated-Export-v1`) for validation
- [x] Bracket data uses Lua patterns correctly — no regex-style alternation (`|`)

**Technical Hints**:

- Use `[BEGIN_CHAR]`/`[END_CHAR]` delimiters with `key=value` lines per field
- Bracket data: `bracket_0_rating=1800`, `bracket_0_mmr=1850`, etc.
- Parse bracket keys with: `key:match("^bracket_(%d+)_(%a+)$")`
- Export EditBox: set `OnTextChanged` to restore saved text when `userInput` is true
