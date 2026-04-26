# Insights: Match Data Capture — Implementation Plan

This document covers the full plan for `core/Insights.lua` and the DB changes needed to capture rated PvP match data. It is meant to be read, challenged, and refined before implementation starts.

---

## Why this exists

NelxRated currently tracks ratings per character/spec/bracket but has no memory of individual matches. This epic introduces a match log so a future Insights UI can show: match history, enemy comp frequency, win rates by comp, rating deltas over time, and session stats.

No UI is built in this epic. Data is collected silently.

---

## What gets built

### New file: `core/Insights.lua`

Single module, data-only (no CreateFrame, no UI). Registers its own event frame. Exposes:

- `NXR.GetMatches()` — read accessor for UI modules

### Changes to `core/Core.lua`

- `InitDB()` gains one line: `NelxRatedDB.matches = NelxRatedDB.matches or {}`
- `CURRENT_SCHEMA` bumped to `2`, migration entry adds the same nil-guard for existing SavedVariables

### `NelxRated.toc`

- `core/Insights.lua` added after `core/Challenges.lua`, before any `ui/` file

---

## Data structure

Each match appended to `NelxRatedDB.matches[]` (newest last, uncapped):

```lua
{
    timestamp    = time(),         -- Unix seconds at match end
    bracketIndex = number or nil,  -- NXR.BRACKET_* constant (1/2/4/7); nil if undetected
    charKey      = "Name-Realm",   -- NXR.currentCharKey at match end
    specID       = number or nil,  -- character's specID from NelxRatedDB.characters[charKey].specID
    outcome      = "win"/"loss"/"draw",
    rating       = number or nil,  -- post-match CR from C_PvP.GetScoreInfo()
    ratingChange = number or nil,  -- rating delta from C_PvP.GetScoreInfo()
    prematchMMR  = number or nil,
    mmrChange    = number or nil,
    enemySpecs   = { specID, ... } -- array; {} for Blitz BG (event doesn't fire)
}
```

**Why `{}` and not `nil` for `enemySpecs` in Blitz?** — UI code can always do `#record.enemySpecs == 0` without nil-checking. A nil field means "something went wrong"; an empty table means "expected: Blitz BG doesn't expose comp data."

**Why uncapped?** — Rating history is capped at 250 entries per character/bracket because unbounded growth there was a real concern (hundreds of data points per bracket per char). Match records are one table total and grow much slower. Will cap if it becomes a problem.

**Why `outcome` derived from `ratingChange` and not a `won` boolean?** — `C_PvP.GetScoreInfo()` returns a `PVPScoreInfo` struct. The struct has a `won` field (boolean), but this has not been verified against a live 12.x client. Deriving outcome from `ratingChange` sign is robust: positive = win, negative = loss, zero = draw (or unrated/skipped round in Solo Shuffle). Risk: a win where rating doesn't change (e.g. already at cap) would be logged as "draw". **This is the biggest assumption in this plan — worth challenging.**

---

## Event strategy

### Events registered

| Event | Purpose |
|-------|---------|
| `ADDON_LOADED` | Bootstrap: set up remaining listeners after addon loads |
| `PLAYER_ENTERING_WORLD` | Take bracket snapshot when entering a rated instance |
| `ARENA_PREP_OPPONENT_SPECIALIZATIONS` | Capture enemy specs during arena prep phase |
| `PVP_MATCH_COMPLETE` | Stage 1: detect bracket, stash partial record |
| `UPDATE_BATTLEFIELD_SCORE` | Stage 2: read score data, complete and write record |

### Two-stage capture

Research shows `C_PvP.GetScoreInfo()` carries a `SecretInActivePvPMatch` restriction — it is unavailable during a match, available only once it ends. GitHub addon patterns consistently use `UPDATE_BATTLEFIELD_SCORE` (not `PVP_MATCH_COMPLETE`) to read final score data.

**Stage 1 — `PVP_MATCH_COMPLETE`**: Capture bracket detection (compare snapshot) and consume `pendingEnemySpecs`. Store in a `pendingRecord` module-local table.

**Stage 2 — next `UPDATE_BATTLEFIELD_SCORE` after match end**: Read `C_PvP.GetScoreInfo()`, find player entry, populate rating/MMR fields, call `NXR.RecordMatch()`, clear `pendingRecord`.

Guard: only consume the pending record once. After `UPDATE_BATTLEFIELD_SCORE` fires and a pending record exists, write and clear — ignore subsequent `UPDATE_BATTLEFIELD_SCORE` events until the next match.

---

## Bracket detection

**Problem**: `GetInstanceInfo()` returns `instanceType = "arena"` for 2v2, 3v3, *and* Solo Shuffle. There is no `instanceType` that uniquely identifies Solo Shuffle.

**Solution**: Snapshot `C_PvP.GetRatedBracketInfo(bracketIndex).seasonPlayed` for all 4 brackets on `PLAYER_ENTERING_WORLD` (when entering an arena/pvp instance). At `PVP_MATCH_COMPLETE`, call the same function again and find the bracket whose `seasonPlayed` incremented by exactly 1.

```
On PLAYER_ENTERING_WORLD (instanceType == "arena" or "pvp"):
  snapshot[1] = C_PvP.GetRatedBracketInfo(1).seasonPlayed  -- 2v2
  snapshot[2] = C_PvP.GetRatedBracketInfo(2).seasonPlayed  -- 3v3
  snapshot[4] = C_PvP.GetRatedBracketInfo(4).seasonPlayed  -- Blitz
  snapshot[7] = C_PvP.GetRatedBracketInfo(7).seasonPlayed  -- Solo Shuffle

On PVP_MATCH_COMPLETE:
  for each bracketIndex in {1, 2, 4, 7}:
    current = C_PvP.GetRatedBracketInfo(bracketIndex).seasonPlayed
    if current == snapshot[bracketIndex] + 1 → this is the bracket
```

**Assumptions / risks**:
- `C_PvP.GetRatedBracketInfo(bracketIndex)` uses the same bracket index scheme as `NXR.BRACKET_*` constants — values 1, 2, 4, 7. **These must be verified in-game.** Core.lua currently uses the deprecated `GetPersonalRatedInfo()` with these same index values, not `C_PvP.GetRatedBracketInfo()`. It's possible the two functions use different index schemes. **This is the second biggest assumption.**
- `seasonPlayed` increments exactly 1 per match. Should be true unless the player somehow played two matches before `PVP_MATCH_COMPLETE` fired (not realistic).
- If the player leaves the instance before `PVP_MATCH_COMPLETE` fires (disconnect, forced exit), the snapshot is stale but the event won't fire either, so no bad record is written.

**Fallback**: If no bracket increments, `bracketIndex = nil` in the record. Match is still saved (timestamp, outcome, rating, enemy specs) — just without bracket attribution.

---

## Rating / MMR data source

`C_PvP.GetScoreInfo(offsetIndex)` — confirmed on warcraft.wiki.gg for 12.x. Returns `PVPScoreInfo` table.

**How to find the player's own entry**: iterate offsetIndex 0, 1, 2… until nil. Match entry by `scoreInfo.name == UnitName("player")`.

Fields used:
- `scoreInfo.rating` → post-match CR
- `scoreInfo.ratingChange` → delta
- `scoreInfo.prematchMMR`
- `scoreInfo.mmrChange`

**Note**: `GetBattlefieldScore()` has `preMatchMMR` and `mmrChange` columns that have returned zero since patch 4.2. Do not use those columns. Use `C_PvP.GetScoreInfo()` exclusively.

**Risk**: `C_PvP.GetScoreInfo()` may not be populated at the exact moment `PVP_MATCH_COMPLETE` fires. REFlex waits for `UPDATE_BATTLEFIELD_SCORE` after `PVP_MATCH_COMPLETE`. **If `C_PvP.GetScoreInfo()` returns empty results on `PVP_MATCH_COMPLETE`, we may need to defer the score read to `UPDATE_BATTLEFIELD_SCORE` while holding other captured data (enemy specs, bracket) in a pending table.** Plan does not include this deferred path yet — it's an implementation concern to confirm in-game.

---

## Enemy comp capture

`ARENA_PREP_OPPONENT_SPECIALIZATIONS` fires during the arena countdown (~30s before match). At that point `GetArenaOpponentSpec(i)` returns specIDs.

Data held in a module-local `pendingEnemySpecs` table until `PVP_MATCH_COMPLETE` fires and consumes it.

**Limitations**:
- Arena only — does not fire for Blitz BG. `enemySpecs = {}` for Blitz.
- May not fire if a teammate is not yet in the arena when the countdown starts (documented Blizzard quirk).
- Solo Shuffle: fires once per match start with the 3 opponents. All 6 rounds share the same 3 enemies — this is correct for comp tracking purposes.

---

## Schema migration

`CURRENT_SCHEMA` in `Core.lua` bumps from `1` to `2`. Migration:

```lua
MIGRATIONS[2] = function(db)
    db.matches = db.matches or {}
end
```

Existing users with `schemaVersion = 1` get `matches = {}` on first login after update. No data loss. No destructive operation.

---

## What this epic does NOT include

- **Insights UI** — separate epic (match history tab, comp charts, filters)
- **Deduplication** — if `PVP_MATCH_COMPLETE` somehow fires twice for one match, two records are written
- **Match record pruning / cap** — intentionally omitted; revisit if SavedVariables size becomes a problem
- **Allied team comp** — would require `NotifyInspect()` on teammates (async, range-gated, unreliable). Not worth it.
- **Rating before match** — not captured directly. Could be derived as `rating - ratingChange` but that's UI-layer math, not storage concern.

---

## Open questions — resolved and unresolved

### Resolved

**`C_PvP.GetRatedBracketInfo()` index scheme** — confirmed: Core.lua uses indices 1/2/4/7 with `GetPersonalRatedInfo()` and they work. Same indices used for `C_PvP.GetRatedBracketInfo()`. No ambiguity.

**`C_PvP.GetScoreInfo()` timing** — confirmed unreliable at `PVP_MATCH_COMPLETE`. Has `SecretInActivePvPMatch` restriction. GitHub addon patterns consistently read score data on `UPDATE_BATTLEFIELD_SCORE`. Plan updated to two-stage capture above.

### Requires in-game debug

The following are genuinely undocumented. We ship the initial implementation with a **debug dump mode**: on `PVP_MATCH_COMPLETE` and `UPDATE_BATTLEFIELD_SCORE`, if `NXR.InsightsDebug == true`, print the full event payload and key API return values to chat. User copies the output and we refine from there.

**`outcome` source — `ratingChange` sign vs `scoreInfo.won`**
`PVPScoreInfo` has a `won` field documented on warcraft.wiki.gg but not verified in 12.x. Debug dump will print both `won` and `ratingChange` so we can see which is reliable. Plan currently uses `ratingChange` sign as fallback.

**`PVP_MATCH_COMPLETE` — rated-only?**
Blizzard's own `PVPMatchResults.lua` handles the event with only a spectator check — no rated guard. It may fire for unrated BGs. Debug will reveal: if `ratingChange` is nil or 0 and `rating` is nil, it's likely unrated. Guard: skip writing if player's score entry has no `rating` field. Revisit after seeing debug output.

**Solo Shuffle — once per round or per session?**
`PVP_MATCH_COMPLETE` might fire 6 times (once per round) or once. If per-round: each round gets its own match record, which is actually more granular and useful. `enemySpecs` would be the prep-phase opponents (same 3 people all session — correct). Debug will print how many times the event fires per session.

---

## Story order

| Story | Deliverable |
|-------|-------------|
| I-1 | `core/Insights.lua` scaffold, TOC entry, `NelxRatedDB.matches` init, schema migration |
| I-2 | Bracket snapshot on `PLAYER_ENTERING_WORLD` |
| I-3 | Enemy spec capture on `ARENA_PREP_OPPONENT_SPECIALIZATIONS` |
| I-4 | Full match record on `PVP_MATCH_COMPLETE` |
| I-5 | `NXR.GetMatches()` public accessor + `core/CLAUDE.md` update |
