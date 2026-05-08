# Plan: Insights Extended, Default Tab, How-To Rename

## Context

Three UX improvements:
1. Insights rows expand in-place to reveal damage/healing stats and SS per-round data
2. Insights opens as the default tab every time the main frame is shown
3. "Home" renamed to "How-To", moved last in nav, content expanded to section overviews

---

## Feature 1: Extended Insights (Capture + Expand-in-Place)

### Part A — Capture damage/healing stats (`core/Insights.lua`)

In `CaptureFromScoreboard(rec)` (line 226), after reading rating/MMR/specs, also iterate `C_PvP.GetScoreInfo().stats[]` for the player's own row to capture:
- `damageDone`
- `healingDone`
- `killingBlows`

Store on the match record: `rec.damageDone`, `rec.healingDone`, `rec.killingBlows`.

**Before implementing:** Run `/wow-api-research` to verify:
- pvpStatID values for damage done, healing done, killing blows
- Whether they're consistent across brackets (Shuffle/2v2/3v3/Blitz)
- Which player index in `GetScoreInfo()` is the local player

Fields will be `nil` on old records — UI must guard with `rec.damageDone and ...`.

### Part B — Expand-in-place UI (`ui/InsightsUI.lua`)

**Row header changes:**
- Add a narrow expand-indicator FontString on the right side of each row (`"+"` / `"-"`)
- Make the row frame clickable: `row:EnableMouse(true)`, `row:SetScript("OnMouseDown", ...)`

**Detail sub-frame per row:**
- In `CreateRow(parent)`, create `row.detail` as a child Frame, hidden initially
- `row.detail` shows:
  - `Damage Done: X  Healing Done: X  Killing Blows: X` (omit line if fields are nil)
  - SS per-round grid `R1 WIN 42s  R2 LOSS 38s ...` (omit if not SS or rounds not captured)
  - Height: ~40px stats only, ~60px with SS rounds

**Variable-height row layout:**
- Change `RefreshRows` to accumulate Y offset instead of uniform `ROW_HEIGHT * index`
- After each row: `yOffset = yOffset + (isExpanded and ROW_HEIGHT + detailHeight or ROW_HEIGHT)`
- Update scroll content frame total height accordingly
- One global `expandedIndex` (nil = none); clicking same row collapses it

**OnClick handler:**
```lua
if expandedIndex == rowIndex then
    expandedIndex = nil
else
    expandedIndex = rowIndex
end
RefreshRows()
```

**Tooltip:** Keep existing hover tooltip (quick glance); expanded detail for full stats.

---

## Feature 2: Insights as Default Tab on Every Open (`ui/MainFrame.lua`)

`SelectTab("Home")` is called once in `CreateMainFrame()` (line 244). Re-opening the frame preserves the last active tab.

**Change 1** — Line 244: `SelectTab("Home")` → `SelectTab("Insights")`

**Change 2** — `ToggleMainFrame()` (~line 259): In the branch where frame is hidden and being shown, add `NXR.SelectTab("Insights")`:

```lua
function NXR.ToggleMainFrame()
    if not mainFrame then
        CreateMainFrame()  -- SelectTab("Insights") already called inside
    elseif mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        NXR.SelectTab("Insights")  -- <-- ADD
    end
end
```

---

## Feature 3: Rename Home → How-To, Move Last, Expand Content

### `ui/MainFrame.lua`

**Line 81** — Reorder and rename `TAB_ORDER`:
```lua
-- Before:
local TAB_ORDER = { "Home", "Insights", "History", "Challenges", "Characters", "Currency", "Settings" }
-- After:
local TAB_ORDER = { "Insights", "History", "Challenges", "Characters", "Currency", "Settings", "How-To" }
```

**Line 221** — Update panel registration:
```lua
-- Before: NXR.CreateHomePanel(tabPanels["Home"])
-- After:  NXR.CreateHowToPanel(tabPanels["How-To"])
```

### `ui/HomeUI.lua`

Rename `NXR.CreateHomePanel` → `NXR.CreateHowToPanel`.

Replace existing content with:

1. Title: "How to Use ArenaInsights" + version line
2. Section overviews (gold sub-heading + 2–3 sentence paragraph each):
   - **Overlay** — movable frame showing spec rows from your active challenge; displays per-spec best rating across characters; opacity slider in Settings; lock with `/ai lock`
   - **Challenges** — create rating goals per spec or class, select which brackets count; one active at a time; overlay reflects the active challenge
   - **Insights & History** — auto-captured after every rated match; Insights shows match history with stats, History shows rating progression; no setup needed
   - **Characters** — lists all tracked characters with ratings per bracket; auto-populated from matches played
   - **Import / Export** — share data across accounts; export produces a string, import merges without overwriting existing data
   - **Party Sync** — syncs challenge/rating data with party members running ArenaInsights; use `/ai sync`
3. **Slash Commands** — list all commands
4. **Links** — keep existing CurseForge + GitHub copyable links

---

## Bug Fix: Solo Shuffle Only Showing 4 of 6 Players (`core/Insights.lua`)

### Root cause

`CaptureFromScoreboard` partitions all scoreboard entries by faction (0 vs 1). For 2v2/3v3 this maps to arena team. For SS, `faction` reflects **last-round team assignment** — so your 2 last-round teammates always land in `allies` and your 3 last-round opponents always land in `enemies`. `InsightsUI` only reads `rec.enemySpecs` for SS display, so the 2 allies are silently dropped every time — consistently producing 4 icons (self + 3 last-round enemies) instead of 6.

### Fix (lines ~311–322 in `CaptureFromScoreboard`)

Check `rec.bracketHint == NXR.BRACKET_SOLO_SHUFFLE` **or** `C_PvP.IsSoloShuffle()` before partitioning:

```lua
-- Before partitioning, detect SS:
local isSS = (rec.bracketHint == NXR.BRACKET_SOLO_SHUFFLE)
    or (C_PvP and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle())

local myFac = selfRow.faction
local allies, enemies = {}, {}
for _, row in ipairs(entries) do
    if not row.isSelf then
        if isSS then
            -- SS has no stable teams — all 5 other players are participants
            enemies[#enemies + 1] = row
        elseif myFac ~= -1 and row.faction == myFac then
            allies[#allies + 1] = row
        elseif myFac ~= -1 and row.faction ~= -1 then
            enemies[#enemies + 1] = row
        end
    end
end
```

`rec.bracketHint` is set on `pendingRecord` before both `CaptureFromScoreboard` calls (UPDATE_BATTLEFIELD_SCORE and the 1.5s timer), so it's available. The `IsSoloShuffle()` guard catches the first call (still inside the match); `bracketHint` catches the delayed final call (by 1.5s the API may return false).

**Note:** `rec.bracketHint` holds `NXR.BRACKET_SOLO_SHUFFLE` (value 7). Verify constant in `core/Core.lua` before touching.

---

## Critical Files

| File | Changes |
|------|---------|
| `core/Insights.lua` | `CaptureFromScoreboard()`: SS faction partition fix + add damage/healing/killingBlows |
| `ui/InsightsUI.lua` | `CreateRow()`, `RefreshRows()`: expand-in-place rows |
| `ui/MainFrame.lua` | `TAB_ORDER`, panel registration, `ToggleMainFrame()` default tab |
| `ui/HomeUI.lua` | Rename to HowToPanel, replace content with section overviews |

---

## Verification

1. Play a rated match → `ArenaInsightsDB.matches` last entry has `damageDone`/`healingDone`/`killingBlows`
2. SS match → Insights row shows all 6 spec icons (self + 5 others)
3. Mixed-faction SS match → still shows all 6 (faction no longer gates participants)
4. 2v2/3v3 match → partition unchanged; ally/enemy split still correct
5. Open Insights → click a row → detail expands with stats + SS round grid
6. Click expanded row again → collapses
7. Click a different row → previous collapses, new one expands
8. Old records (no damage data) → detail renders without stats line, no nil errors
9. Non-SS rows → no round grid in detail
10. Close main frame → reopen → Insights tab is active
11. Nav sidebar: "How-To" appears last; all other tabs still work
12. How-To panel renders with section overviews, no white frames, no Unicode glyphs
