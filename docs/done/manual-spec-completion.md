# Manual Spec Completion

## Problem

Some challenge goals can't be auto-tracked. Example: "reach top 50 on the leaderboard." Leaderboard rank requires async server queries, scanning all entries to find self, and isn't real-time. Manual marking fills the gap for any goal type where auto-detection is impossible.

## Leaderboard API Note

`C_PvP.GetRatedBracketInfo()` does not return leaderboard rank in 12.x. Leaderboard request APIs (`RequestPVPLeaderboard` + `PVP_LEADERBOARD_UPDATE` event) exist but are async, require scanning, and may omit player if outside top N. Not worth implementing — manual marking is the right solution.

---

## Story: Mark Spec Complete from Overlay

**As a** player running a top-50 or custom challenge,  
**I want to** manually mark a spec as complete from the overlay,  
**so that** the checkmark reflects my actual achievement even when auto-tracking is impossible.

### Acceptance Criteria

- [ ] Right-clicking a spec row in the overlay shows a context menu with "Mark Complete" (if not already marked) or "Unmark Complete" (if marked)
- [ ] When marked complete: checkmark icon shown, rating text hidden — overrides all automatic rating/color logic
- [ ] When unmarked: row reverts to normal rating display
- [ ] Completion state persists across UI reloads (SavedVariables)
- [ ] Completion state travels with challenge data in Import/Export
- [ ] Works for both spec-based and class-based challenge rows
- [ ] Context menu uses `MenuUtil.CreateContextMenu()` (no deprecated dropdown)

---

## Implementation

### Schema

Add to each challenge object in `NelxRatedDB.challenges[]`:

```lua
completedSpecs   = { [specID]  = true }   -- spec-based challenges
completedClasses = { [classID] = true }   -- class-based challenges
```

Omitted = not completed. No DB migration needed — missing field treated as `{}`.

### New Functions in Challenges.lua

```lua
NXR.SetSpecCompleted(challengeID, specID, completed)    -- true/false toggle
NXR.IsSpecCompleted(challengeID, specID)                -- boolean
NXR.SetClassCompleted(challengeID, classID, completed)
NXR.IsClassCompleted(challengeID, classID)
```

### Overlay.lua Changes

**`PopulateRow()`**: before rating color/text logic, check manual completion first:
- `IsSpecCompleted` / `IsClassCompleted` on the active challenge → show checkmark, hide rating text, skip all threshold logic

**Row right-click (`OnMouseUp`)**: add `MenuUtil.CreateContextMenu()` with:
- "Mark Complete" (when not completed) → setter + `NXR.Overlay.Refresh()`
- "Unmark Complete" (when completed) → setter + `NXR.Overlay.Refresh()`

### Files to Modify

| File | Change |
|------|--------|
| `Challenges.lua` | Schema init in `CreateChallenge()`, 4 getter/setter fns |
| `Overlay.lua` | `PopulateRow()` completion override + right-click context menu |

### Export/Import

No special handling. `completedSpecs`/`completedClasses` fields serialize as part of the challenge object automatically.

---

## Verification

1. Create challenge, right-click spec row → "Mark Complete" → checkmark appears, rating hidden
2. Right-click → "Unmark Complete" → rating display restored
3. `/reload` → completion state persists
4. Export → import on another character → completed state present
5. Class-based challenge row: same flow with classID
