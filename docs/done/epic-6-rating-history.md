# Epic 6 — Rating History & Graph Visualization

Track rating changes over time per character/spec/bracket and visualize progression as a line graph. History is stored lazily per character — no schema migration required. The graph is accessible via a new "History" tab in the main frame.

**Depends on**: Epic 1 (core tracking), Epic 3 (main frame & sidebar navigation)

**Reference**: `docs/reference/Graph.lua` (line chart implementation from NelxGather)

**Note on Import/Export**: History is not included in exports. Only current rating snapshots are exported. History is built locally per account as games are played. This keeps the export payload small and avoids merge complexity. A future epic could add history export if needed.

---

## Story 6-1 — Record Rating History

**Goal**: Append a history entry each time a rating changes, without modifying the existing snapshot behavior.

**Acceptance Criteria**:

- [x] When `SaveBracketData()` fires, after updating the existing snapshot, append to a history array on the character
- [x] History is stored at `char.ratingHistory[bracketIndex][entryIndex]` for shared brackets (2v2, 3v3)
- [x] History is stored at `char.ratingHistory[specID..":"..bracketIndex][entryIndex]` for per-spec brackets (Solo Shuffle, Blitz)
- [x] Each history entry is `{ rating = number, timestamp = number }` (no MMR — keep it lean)
- [x] Only append when the rating actually differs from the last entry in the array (deduplication)
- [x] If `ratingHistory` does not exist on the character, create it and seed with the current snapshot as the first entry
- [x] Cap each history array at 250 entries; when exceeded, remove the oldest entries
- [x] Existing snapshot behavior (`brackets[bracketIndex]` / `specBrackets[specID][bracketIndex]`) remains unchanged

**Technical Hints**:

- `ratingHistory` is lazily created — no migration needed, no `schemaVersion` bump
- Use a composite string key (`specID..":"..bracketIndex`) for per-spec brackets to keep the table flat
- Table removal from the front: `table.remove(history, 1)` while `#history > 250`

---

## Story 6-2 — History Data Access API

**Goal**: Provide a clean API for retrieving history data, used by the graph UI.

**Acceptance Criteria**:

- [x] `NXR.GetRatingHistory(charKey, bracketIndex, specID)` returns the history array or nil
- [x] For per-spec brackets, it looks up using the composite key (`specID..":"..bracketIndex`)
- [x] For shared brackets, it looks up using just `bracketIndex`
- [x] Returns a reference to the actual array (no copy needed — graph is read-only)
- [x] Returns nil gracefully if the character, history table, or specific key doesn't exist

**Technical Hints**:

- Simple lookup function in Core.lua next to `GetRating()`

---

## Story 6-3 — History Tab in Main Frame

**Goal**: Add a "History" tab to the sidebar navigation that hosts the graph and filter controls.

**Acceptance Criteria**:

- [x] "History" appears in the sidebar between "Home" and "Challenges"
- [x] Tab order becomes: Home, History, Challenges, Characters, Settings, Import/Export
- [x] The History tab has a content area consistent with other tabs (same padding, backdrop)
- [x] The top of the tab contains filter controls (dropdowns/buttons for character, spec, bracket)
- [x] Below the filters is the graph area, taking up the remaining vertical space
- [x] When no history data exists for the current selection, show a placeholder: "Play rated games to build history"
- [x] Uses the PvP crimson design system

**Technical Hints**:

- New file: `HistoryTab.lua` added to the TOC
- Filter controls can use simple button-based selectors (no EasyMenu — removed in 12.x)
- The graph area should be a child frame that `HistoryGraph` (Story 6-4) draws into

---

## Story 6-4 — Rating Graph Rendering

**Goal**: Render a line chart showing rating progression over the last N data points.

**Acceptance Criteria**:

- [x] Graph draws a line chart using `CreateLine()` segments between data points
- [x] X-axis represents data point sequence (1, 2, 3, ..., N) — not timestamps
- [x] Y-axis represents rating values
- [x] Y-axis has 4-5 evenly spaced tick labels showing rating values
- [x] X-axis has tick labels showing point indices (e.g., every 50th point)
- [x] Axis border lines on the left and bottom edges of the graph area
- [x] Line color uses crimson accent (`CRIMSON_BRIGHT`) to match the addon theme
- [x] Minimum 3 data points required to render; otherwise show placeholder text
- [x] Line objects and label FontStrings are pooled and reused across refreshes
- [x] Graph redraws when filters change or new data arrives

**Technical Hints**:

- Reference `docs/reference/Graph.lua` for the line drawing pattern (CreateLine, SetStartPoint/SetEndPoint relative to BOTTOMLEFT)
- Map data points to canvas coordinates: `x = (index / totalPoints) * width`, `y = ((rating - minRating) / range) * height`
- Guard against flat lines (all same rating) by padding the range

---

## Story 6-5 — Challenge Goal Line

**Goal**: If the active challenge includes the selected bracket, draw a horizontal goal line on the graph.

**Acceptance Criteria**:

- [x] When the active challenge's brackets include the currently selected bracket, draw a horizontal dashed or solid line at the goal rating
- [x] Goal line uses gold color (`COLORS.GOLD` or similar) to distinguish from the rating line
- [x] Goal line only appears if the goal rating falls within or near the Y-axis range
- [x] If the goal is above all data points, extend the Y-axis range to include it
- [x] A small label on the right end of the goal line shows the rating value (e.g., "2400")
- [x] Goal line hides when no active challenge exists or the challenge doesn't include the selected bracket

**Technical Hints**:

- Single `CreateLine()` spanning the full canvas width at the goal's Y position
- Adjust `maxRating` calculation to include goal rating before computing axis range

---

## Story 6-6 — Filter Controls

**Goal**: Let the user select which character, spec, and bracket to view in the graph.

**Acceptance Criteria**:

- [x] Character selector shows all tracked characters (from `NelxRatedDB.characters`), displaying "Name - Realm"
- [x] Spec selector shows specs available for the selected character (from `specBrackets` keys + class spec list)
- [x] Bracket selector shows tracked brackets: Solo Shuffle, Blitz, 2v2, 3v3
- [x] For per-spec brackets (Solo Shuffle, Blitz), the spec selector is enabled; for shared brackets (2v2, 3v3), the spec selector is disabled/hidden
- [x] Changing any filter immediately refreshes the graph
- [x] Default selection: current character, current spec, Solo Shuffle
- [x] Filters remember their selection while the tab is open (reset on frame close is fine)

**Technical Hints**:

- Use `MenuUtil.CreateContextMenu()` or custom button+dropdown pattern (no EasyMenu)
- Current character key is available via `NXR.currentCharKey`
- Current spec via `NelxRatedDB.characters[key].specID`

---

## Story 6-7 — Y-Axis Rating Milestones & Graph Padding

**Goal**: Add subtle horizontal grid lines at regular rating intervals and add vertical padding so the graph doesn't feel overly zoomed in.

**Improvement**: IMP-7

**Acceptance Criteria**:

- [x] Draw subtle horizontal grid lines at regular rating intervals (every 100, 200, or 400 rating depending on the Y-axis range)
- [x] Grid lines use a muted color (e.g., `{0.3, 0.3, 0.3, 0.4}`) and sit behind the data line
- [x] Each grid line has a small label on the left showing the rating value
- [x] Interval selection is automatic: use 100 for ranges < 400, 200 for ranges < 800, 400 for larger ranges
- [x] Add vertical padding to the Y-axis: `minRating` and `maxRating` are expanded by ~5-10% of the range (or a minimum of 25 rating) so the line doesn't touch the top/bottom edges
- [x] The padding is applied before grid line and tick label calculations
- [x] Grid line objects are pooled and reused like existing line/label pools
- [x] Existing axis border lines and tick labels continue to work correctly with the new padding

**Technical Hints**:

- Calculate the milestone interval based on the padded range, then iterate from the first milestone >= `minRating` to the last <= `maxRating`
- Grid lines are full-width `CreateLine()` calls at each milestone's Y position, drawn at a low frame level or strata so the data line renders on top
- Reuse the same pooling pattern as the data line segments

---

## Story 6-8 — Chart Line Color Setting

**Goal**: Add a setting to choose the history chart line color — crimson (default) or class color.

**Improvement**: IMP-6

**Acceptance Criteria**:

- [x] New setting `NelxRatedDB.settings.chartColor` with values `"default"` (default) and `"class"`
- [x] Setting appears in the Settings tab under a "History" or "Graph" section
- [x] When set to `"default"`, the chart line uses `CRIMSON_BRIGHT` (current behavior)
- [x] When set to `"class"`, the chart line uses the WoW class color of the currently selected character
- [x] Class colors are sourced from `RAID_CLASS_COLORS[englishClass]`
- [x] Changing the setting immediately refreshes the graph if the History tab is visible
- [x] The goal line always remains gold regardless of this setting

**Technical Hints**:

- Add the setting to `DEFAULT_SETTINGS` in Core.lua and `InitDB()` defaults
- In the graph render function, resolve the line color once before the draw loop based on the setting and selected character's class
- The character's `englishClass` is available from `NelxRatedDB.characters[charKey].class`
