# Roadmap — ArenaInsights

Evolving from a challenge tracker into a full PvP companion: ratings, currencies, comp insights, and gearing guidance.

---

## Rename & Rebrand

**Status**: Complete

Renamed from NelxRated to ArenaInsights. DB migration, export compatibility, and code identity updated.

**Epic**: [Epic 10 — Rename & Rebrand](epic-10-rename-rebrand.md)

---

## Insights: Comp Tracking & MMR

**Status**: Research complete, epic not written

Track what you played against and with. Visualize patterns over time.

- Data capture: record enemy comps, own spec, bracket, outcome, rating delta per match
- Insights tab in main frame
- Visualizations: class/spec frequency charts, win rates by comp
- Filterable by bracket, date range, character

**API availability:**

| Data | Source | Notes |
|------|--------|-------|
| Match end trigger | `PVP_MATCH_COMPLETE` | Reliable |
| Scoreboard data trigger | `UPDATE_BATTLEFIELD_SCORE` | Fires when server transmits final scores |
| Enemy specs (arenas) | `GetArenaOpponentSpec(1..N)` at `ARENA_PREP_OPPONENT_SPECIALIZATIONS` | Arena only — not Blitz BG |
| Rating + MMR | `C_PvP.GetScoreInfo(offsetIndex)` | Returns `PVPScoreInfo`: `rating`, `ratingChange`, `prematchMMR`, `mmrChange`, `postmatchMMR` |
| Rating delta (team) | `GetBattlefieldTeamInfo(faction)` | faction=0 own, faction=1 enemy |
| Bracket detection | `GetInstanceInfo()` + `GetNumArenaOpponentSpecs()` count | No dedicated API |
| Blitz BG enemy comp | No arena prep APIs fire | Record result + rating + MMR only; omit enemy comp |

Note: `GetBattlefieldScore()` MMR columns always zero since patch 4.2 — use `C_PvP.GetScoreInfo()` instead.

**Epics**: Epic 12 — Match Data Capture (`core/Insights.lua`, `ArenaInsightsDB.matches[]`), Epic 13 — Insights UI

---

## Gearing Helper

**Status**: Not started

Guide players from fresh 80 to fully gemmed/enchanted BiS PvP gear.

- Track current gear: item level, slot by slot
- Show conquest/honor needed to complete gear set
- Gem + enchant checklist per slot
- Upgrade path: track upgrade levels, show cheapest next step
- Seasonal updates: conquest caps, costs, item tables

**Epics**: Epic 14 — Gear State Tracking, Epic 15 — Gearing UI & Advisor

---

## Extended Stats & Polish

**Status**: Not started

Deeper historical stats and quality-of-life improvements.

- Session stats (games today, win/loss streak)
- Cross-character aggregate stats
- Rating trends over time (charts)
- Performance improvements for large datasets

**Epics**: TBD

---

## Improvements & Polish

Ongoing. No dedicated epic — tracked as individual stories or bugs.

- UI consistency passes
- Accessibility / tooltip improvements
- Bug fixes
- Performance

### TODO: Fix spec icon style in ChallengesUI

Spec icons in Insights (team column) and ChallengesUI come from the same source: `GetSpecializationInfoByID(specID)` → `icon` texture ID. The difference is that Insights applies `SetTexCoord(0.07, 0.93, 0.07, 0.93)` which crops the built-in circular border/shadow, making them look flat and consistent with the flat `classicon-<class>` atlas icons. ChallengesUI does not apply this crop → icons render with their border → look embossed/3D → inconsistent with class icons.

Fix: replace bare `SetTexture(icon)` with `AI.SetSpecIcon(tex, icon)` (defined in `ui/MainFrame.lua`) at both usages in ChallengesUI:
- `ui/ChallengesUI.lua` line ~199: list row icons (`row.icons[idx]:SetTexture(sd.icon)`)
- `ui/ChallengesUI.lua` line ~613: form spec picker (`ic:SetTexture(s.icon)`)

Note: line ~154 uses `\226\137\165` (≥) — verified working in WoW fonts, leave as-is.

---

## Notes

- Each section ships as a versioned release
- Gearing helper costs are season-dependent — needs maintenance each season
- Insights data capture (Epic 12) should start before UI exists — collect now, visualize later
- MMR tracking not feasible via addon API; omit from scope unless Blizzard exposes it
