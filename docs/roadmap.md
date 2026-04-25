# Roadmap — PvP Companion Addon (name TBD)

Evolving from NelxRated (challenge tracker) into a full PvP companion: ratings, currencies, comp insights, and gearing guidance — all in one addon.

---

## Phase 1 — Foundation: Rename + Currency Merge
**Goal**: Clean slate with new identity. Absorb NelxRatedCurrency. One addon, one sidebar.

- Rename addon (new name TBD) — all identity strings, DB migration, export compat
- Merge NelxRatedCurrency into main addon as a Currency tab
- Retire NelxRatedCurrency as standalone addon
- Minimap button (from NelxRatedCurrency)

**Epics**: [Epic 10 — Rename & Rebrand](epic-10-rename-rebrand.md), [Epic 11 — Currency Tab](epic-11-currency-tab.md)

---

## Phase 2 — Insights: Comp Tracking & Visualization
**Goal**: Track what you played against and with. Visualize patterns over time.

- Data capture: record enemy comps, allied comps, bracket, outcome per game
- Insights tab in main frame
- Visualizations: class/spec frequency charts, win rates by comp, trends over time
- Filterable by bracket, date range, character

**Epics**: Epic 12 — Comp Data Capture, Epic 13 — Insights UI

---

## Phase 3 — Gearing Helper
**Goal**: Guide players from fresh 80 to fully gemmed/enchanted BiS PvP gear.

- Track current gear: item level, slot by slot
- Show conquest/honor needed to complete gear set
- Gem + enchant checklist per slot
- Upgrade path: track upgrade levels, show cheapest next step
- Seasonal updates: conquest caps, costs, item tables

**Epics**: Epic 14 — Gear State Tracking, Epic 15 — Gearing UI & Advisor

---

## Phase 4 — Extended Stats & Polish
**Goal**: Deeper historical stats, quality-of-life improvements.

- MMR trends over time (charts)
- Session stats (games today, win/loss streak)
- Cross-character aggregate stats
- Performance improvements for large datasets

**Epics**: TBD

---

## Notes

- Each phase ships as a versioned release
- Gearing helper (Phase 3) costs are season-dependent — needs maintenance each season
- Phase 2 data capture must start before UI exists (collect now, visualize later)
- NelxRatedCurrency users: Phase 1 includes in-game migration notice
