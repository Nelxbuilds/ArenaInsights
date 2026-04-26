# Epic — Insights: Match Data Capture

Introduce `core/Insights.lua` to record a structured match record into `NelxRatedDB.matches[]` each time the player completes a rated PvP match. This epic covers only data capture — no UI. The data collected here feeds the future Insights UI epic.

---

## Story I-1 — Insights Module Scaffold

**Goal**: Create `core/Insights.lua` as a new data-only module that initialises `NelxRatedDB.matches` in `InitDB` and exposes the public API surface. No match records are written yet.

**Acceptance Criteria**:

- [x] File `core/Insights.lua` exists and uses the `local addonName, NXR = ...` namespace declaration
- [x] `NelxRated.toc` lists `core/Insights.lua` after `core/Challenges.lua` and before any `ui/` file
- [x] `core/Insights.lua` is documented in `core/CLAUDE.md` with its public functions and events
- [x] `NelxRatedDB.matches` is initialised to `{}` inside `InitDB()` in `core/Core.lua` if nil
- [x] The module registers an `ADDON_LOADED` listener; all further event listeners are registered only after `loadedAddon == addonName`
- [x] No `CreateFrame`, no UI widgets, no `print()` chat output anywhere in this file

---

## Story I-2 — Bracket Snapshot on Arena Entry

**Goal**: When the player enters an arena instance, snapshot the current `seasonPlayed` count for all tracked brackets so that Story I-4 can detect which bracket incremented at match end.

**Acceptance Criteria**:

- [x] `core/Insights.lua` registers for `PLAYER_ENTERING_WORLD`
- [x] On `PLAYER_ENTERING_WORLD`, calls `GetInstanceInfo()` and reads `instanceType` (2nd return value); proceeds only when `instanceType == "arena"` or `instanceType == "pvp"`
- [x] Calls `C_PvP.GetRatedBracketInfo(bracketIndex)` for each of `NXR.BRACKET_2V2` (1), `NXR.BRACKET_3V3` (2), `NXR.BRACKET_BLITZ` (4), and `NXR.BRACKET_SOLO_SHUFFLE` (7)
- [x] Each call is nil-guarded: if the return is nil or `seasonPlayed` is nil, that bracket index is not written into the snapshot table
- [x] Snapshot is stored in a module-local table (not in `NelxRatedDB`) keyed by bracket index, value is the integer `seasonPlayed`
- [x] If `PLAYER_ENTERING_WORLD` fires outside an arena/pvp instance the snapshot table is not modified
- [x] If `PLAYER_ENTERING_WORLD` fires again while still inside the instance the snapshot table is overwritten with fresh values

---

## Story I-3 — Enemy Spec Capture

**Goal**: Capture the specialisation IDs of all arena opponents during the preparation phase and hold them in a module-local table for inclusion in the match record.

**Acceptance Criteria**:

- [x] `core/Insights.lua` registers for `ARENA_PREP_OPPONENT_SPECIALIZATIONS`
- [x] On `ARENA_PREP_OPPONENT_SPECIALIZATIONS`, calls `GetNumArenaOpponentSpecs()` to determine opponent count, then calls `GetArenaOpponentSpec(i)` for `i = 1` through that count
- [x] Results stored in a module-local table as a sequential array of integer specIDs in slot order, e.g. `{ 65, 256, 72 }`
- [x] If `GetArenaOpponentSpec(i)` returns `0` or `nil` for a slot, that slot is stored as `0` (unknown) — not omitted
- [x] The opponent spec table is reset to `{}` at the start of each `ARENA_PREP_OPPONENT_SPECIALIZATIONS` event before repopulating
- [x] For Blitz BG matches this event does not fire — the opponent spec table remains `{}` and that is the correct value written into the match record

---

## Story I-4 — Match Record on PVP\_MATCH\_COMPLETE

**Goal**: When a rated match ends, detect which bracket was played using the `seasonPlayed` snapshot, collect rating data from `C_PvP.GetScoreInfo()`, and append a complete record to `NelxRatedDB.matches`.

**Acceptance Criteria**:

**Two-stage capture**: `C_PvP.GetScoreInfo()` has a `SecretInActivePvPMatch` restriction — unavailable mid-match. Addon patterns confirm score data is read on `UPDATE_BATTLEFIELD_SCORE`, not `PVP_MATCH_COMPLETE`. Stage 1 fires on `PVP_MATCH_COMPLETE`; Stage 2 completes on the next `UPDATE_BATTLEFIELD_SCORE`.

- [x] `core/Insights.lua` registers for both `PVP_MATCH_COMPLETE` and `UPDATE_BATTLEFIELD_SCORE`

**Stage 1 — `PVP_MATCH_COMPLETE`**:

- [x] Bracket identified by comparing `C_PvP.GetRatedBracketInfo(bracketIndex).seasonPlayed` for indices 1, 2, 4, and 7 against the snapshot; the bracket whose `seasonPlayed` is exactly 1 greater is the active bracket
- [x] Each `C_PvP.GetRatedBracketInfo()` call is nil-guarded; if it returns nil or `seasonPlayed` is nil, that index is skipped
- [x] If no bracket incremented, `bracketIndex` in the pending record is `nil`
- [x] A `pendingRecord` module-local table is populated with: `timestamp`, `bracketIndex`, `charKey`, `specID`, `enemySpecs`
- [x] `pendingEnemySpecs` and snapshot table are cleared after being consumed into `pendingRecord`
- [x] If `NXR.currentCharKey` is nil, no `pendingRecord` is created and `NXR.Debug("Insights: no currentCharKey, skipping")` is called

**Stage 2 — next `UPDATE_BATTLEFIELD_SCORE` while `pendingRecord` exists**:

- [x] If `pendingRecord` is nil, handler returns immediately (ignores mid-match scoreboard updates)
- [x] Calls `C_PvP.GetScoreInfo(offsetIndex)` from 0 upward until nil; finds entry where `scoreInfo.name == UnitName("player")`
- [x] Populates `pendingRecord` with: `rating`, `ratingChange`, `prematchMMR`, `mmrChange` from score entry (nil if entry not found)
- [x] `outcome` derived from `ratingChange`: `> 0` → `"win"`, `< 0` → `"loss"`, `== 0` → `"draw"` (nil ratingChange → `"unknown"`)
- [x] Record appended: `NelxRatedDB.matches[#NelxRatedDB.matches + 1] = pendingRecord`
- [x] `pendingRecord` set to `nil` after write (prevents double-write on subsequent `UPDATE_BATTLEFIELD_SCORE` fires)

**Match record structure**:

```lua
{
    timestamp    = time(),         -- Unix timestamp, set at PVP_MATCH_COMPLETE
    bracketIndex = number or nil,  -- NXR.BRACKET_* constant; nil if undetected
    charKey      = "Name-Realm",
    specID       = number or nil,
    outcome      = "win"/"loss"/"draw"/"unknown",
    rating       = number or nil,  -- from C_PvP.GetScoreInfo()
    ratingChange = number or nil,
    prematchMMR  = number or nil,
    mmrChange    = number or nil,
    enemySpecs   = { specID, ... }, -- {} for Blitz BG
}
```

**Debug mode** (unresolved questions — needs in-game verification):

- [x] When `NXR.InsightsDebug == true`, `PVP_MATCH_COMPLETE` handler prints: event payload (winner, duration), all `C_PvP.GetRatedBracketInfo()` snapshot vs current values, `GetInstanceInfo()` return
- [x] When `NXR.InsightsDebug == true`, `UPDATE_BATTLEFIELD_SCORE` handler prints: full `C_PvP.GetScoreInfo()` results for the player entry including `won` field, `ratingChange`, all MMR fields
- [x] `NXR.InsightsDebug` defaults to `false`; set to `true` in-game via `/run NXR.InsightsDebug = true`

---

## Story I-5 — Public Read Accessor

**Goal**: Expose `NXR.GetMatches()` so future UI modules can retrieve match records without coupling directly to `NelxRatedDB`.

**Acceptance Criteria**:

- [x] `core/Insights.lua` defines `NXR.GetMatches()` which returns `NelxRatedDB.matches` or `{}` if nil
- [x] `NXR.GetMatches()` does not mutate the returned table
- [x] `NXR.GetMatches` is documented in `core/CLAUDE.md` under the `Insights.lua` section
- [x] No other file reads `NelxRatedDB.matches` directly — all reads go through `NXR.GetMatches()`

**Out of Scope**:

- Filtering, sorting, or paginating match records (Insights UI epic)
- Any UI rendering of match data (Insights UI epic)
