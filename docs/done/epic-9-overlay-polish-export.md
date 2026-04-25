# Epic 9 — Overlay Polish & Export Overhaul

Overlay UX improvements (checkmark behavior, rating width, logged-in indicator, multi-column layout, role grouping) and full data export/import covering characters, challenges, and settings.

**Depends on**: Epic 4 (overlay), Epic 2 (challenge system), Epic 3 (settings)

---

## Story 9-1 — Checkmark Replaces Rating Text

**Goal**: When a spec reaches 100% of the goal rating, the checkmark icon should replace the rating number entirely — not appear beside it.

**Acceptance Criteria**:

- [ ] When `rating >= goalRating` (100%), `row.rating:SetText("")` hides the number
- [ ] Checkmark texture is shown centered in the rating text area (anchored RIGHT of icon with horizontal centering)
- [ ] Checkmark size remains 14x14
- [ ] When rating drops below 100% or goal changes, checkmark hides and rating text restores
- [ ] Overlay width calculation in `RefreshOverlay()` accounts for checkmark width (14px) as minimum when any row shows a checkmark
- [ ] No visual change to rows below 100% — orange/yellow color coding unaffected

**Technical Hints**:

- In `PopulateRow()`: when `showCheck=true`, clear rating text and reanchor checkmark to `RIGHT` of `row.icon` with centering
- When `showCheck=false`, restore checkmark to hidden and set rating text normally

---

## Story 9-2 — Wider Rating Text Area

**Goal**: Prevent rating numbers from truncating at various overlay scales by adding breathing room to the rating text width.

**Acceptance Criteria**:

- [ ] Rating text RIGHT anchor changed from `-4` to `-8` (or similar) for more padding
- [ ] `RefreshOverlay()` width calculation adds at least 8px extra to `maxRatingWidth`
- [ ] 4-digit ratings (e.g., 2400) display fully at all scale settings (0.5x–2.0x)
- [ ] Overlay minimum width (`MIN_WIDTH`) increased if needed to accommodate wider padding

**Technical Hints**:

- `Overlay.lua` line 205: change RIGHT anchor offset
- `Overlay.lua` line 595: add padding to `totalWidth` calculation

---

## Story 9-3 — Logged-In Character Indicator

**Goal**: If the currently logged-in character's spec/class appears in the active challenge overlay, highlight that row with a gold/yellow visual indicator.

**Acceptance Criteria**:

- [ ] During overlay refresh, compare each row's best-match character key and specID against `NXR.currentCharKey` and current spec
- [ ] Matching row gets a gold/yellow border around the spec icon (2px border texture) or a subtle gold background tint
- [ ] Gold color uses `NXR.COLORS.GOLD` (`{1.0, 0.82, 0.0}`) or similar warm yellow
- [ ] Non-matching rows have no indicator (indicator reset on each refresh)
- [ ] Indicator updates on `ACTIVE_TALENT_GROUP_CHANGED` (spec swap) and `PLAYER_ENTERING_WORLD` (login/reload)
- [ ] For class challenges: highlight if logged-in character's class matches the row's class, regardless of spec
- [ ] Indicator respects opacity settings — hidden when overlay opacity is 0

**Technical Hints**:

- Create a border texture (or background texture) per row in `CreateRow()`, hidden by default
- In `PopulateRow()` or refresh loop, show/hide based on match against `NXR.currentCharKey`
- Current spec available from `NelxRatedDB.characters[NXR.currentCharKey]`

---

## Story 9-4 — Multi-Column Overlay Layout

**Goal**: Add a column count setting (1–10) that distributes overlay rows across multiple columns.

**Acceptance Criteria**:

- [ ] New setting `overlayColumns` added to `SETTINGS_DEFAULTS` in `Core.lua` with default `1`
- [ ] New slider in Settings tab: "Overlay Columns", min=1, max=10, step=1, default=1
- [ ] Slider onChange calls `NXR.RefreshOverlay()`
- [ ] `RefreshOverlay()` reads `NelxRatedDB.settings.overlayColumns` and distributes rows across columns
- [ ] Rows fill columns top-to-bottom, left-to-right (first column fills first, overflow goes to next)
- [ ] Rows per column = `ceil(totalRows / numColumns)` (balanced distribution)
- [ ] Each column width = `icon + gap + maxRatingWidth + padding` (consistent per-column)
- [ ] Overlay frame width = `numColumns * columnWidth`
- [ ] Overlay frame height = `rowsPerColumn * ROW_HEIGHT + padding`
- [ ] With 1 column, layout is identical to current behavior (no regression)
- [ ] If `numColumns > totalRows`, empty columns are not rendered (effective columns clamped to row count)
- [ ] Overlay position saving/restoring still works with any column count

**Technical Hints**:

- Column index: `floor((rowIndex - 1) / rowsPerCol)`
- Row within column: `(rowIndex - 1) % rowsPerCol`
- Anchor each row: `TOPLEFT` offset by `colIndex * colWidth` horizontally, `rowInCol * ROW_HEIGHT` vertically

---

## Story 9-5 — Group Overlay by Role

**Goal**: Add a "Group by Role" toggle that organizes overlay specs into Healer / DPS / Tank sections with optional header labels.

**Acceptance Criteria**:

- [ ] New setting `overlayGroupByRole` added to `SETTINGS_DEFAULTS` in `Core.lua` with default `false`
- [ ] New checkbox in Settings tab: "Group by Role"
- [ ] Checkbox onChange calls `NXR.RefreshOverlay()`
- [ ] When enabled, overlay rows are sorted into groups: Healers, DPS, Tanks — using existing `NXR.roleSpecs` data from `Challenges.lua:BuildSpecData()`
- [ ] Each group has a small header label (e.g., "Healers", "DPS", "Tanks") styled with `GameFontNormalTiny`, `TEXT_DIM` color
- [ ] Header labels occupy their own row space (same height as `ROW_HEIGHT` or smaller)
- [ ] Empty groups (no specs in challenge matching that role) are not shown
- [ ] Within each group, specs are sorted alphabetically by class then spec name (existing sort order)
- [ ] For class challenges: classes are placed in the group of their primary role (most specs in that role), or duplicated if needed
- [ ] Combined with multi-column (Story 9-4): when grouped + multi-column, each role group becomes a column (up to 3 natural groups). If column setting > number of groups, groups wrap internally
- [ ] With grouping disabled, layout reverts to current flat list behavior
- [ ] Role grouping data reuses `NXR.roleSpecs` — no hardcoded melee/ranged tables

**Technical Hints**:

- `NXR.roleSpecs` already has `HEALER`, `DAMAGER`, `TANK` arrays built in `Challenges.lua`
- Role display order: `{ "HEALER", "DAMAGER", "TANK" }` — matches `ChallengesUI.lua` pattern (lines 545-583)
- Header rows are non-interactive (no tooltip, no mouse)

---

## Story 9-6 — Full Data Export/Import

**Goal**: Export and import everything — characters, challenges, and settings — not just character data.

**Acceptance Criteria**:

- [ ] Each challenge gets a unique ID string on creation (`challenge.id`), generated as `time() .. "-" .. math.random(100000, 999999)` or similar
- [ ] Existing challenges without IDs get IDs backfilled on addon load (DB migration in `InitDB()` or post-load)
- [ ] Export format version bumped to `"NelxRated-Export-v2"`
- [ ] Export includes three sections delimited by markers: `[BEGIN_CHARS]`/`[END_CHARS]`, `[BEGIN_CHALLENGES]`/`[END_CHALLENGES]`, `[BEGIN_SETTINGS]`/`[END_SETTINGS]`
- [ ] Challenge serialization includes: `id`, `name`, `specs` (comma-separated specIDs), `classes` (comma-separated classIDs), `brackets` (comma-separated indices), `goalRating`, `active`
- [ ] Settings serialization includes all keys from `NelxRatedDB.settings` as `key=value` pairs
- [ ] Import detects version header: `v2` parses all sections, `v1` parses characters only (backward compatibility)
- [ ] Character merge logic unchanged: skip existing keys
- [ ] Challenge merge: match by `challenge.id` — skip if same ID already exists, add if new ID
- [ ] Imported challenges are added as inactive (only one active at a time rule preserved)
- [ ] Settings import: user gets confirmation prompt ("Import settings? This will overwrite current settings.") before applying
- [ ] Import summary shows counts: "Added X characters, Y challenges. Settings imported/skipped."
- [ ] v1 export string imported into v2 code still works correctly

**Technical Hints**:

- Challenge ID generation in `Challenges.lua:CreateChallenge()`
- Backfill migration: iterate `NelxRatedDB.challenges`, assign ID to any entry where `challenge.id == nil`
- Serialization helpers can live in `ImportExportUI.lua` alongside existing `SerializeCharacters`/`DeserializeCharacters`
- For specs/classes/brackets arrays, serialize as comma-separated values within a single line (e.g., `specs=62,63,64`)
