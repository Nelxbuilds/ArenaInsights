# Epic 12: Session Stats, Queue Overlay, Death Recap

Status: code complete on `combined/ss-round-capture` (v2.5.0-beta2), pending in-game verification.

## Story 1: Session summary

Session = consecutive matches with less than 1 hour between them, per character.

- [ ] Popup appears after leaving arena/BG when a match was recorded (not while still inside)
- [ ] Shows per-bracket score: SS as total rounds W-L, other brackets as match W-L
- [ ] Shows net rating and net MMR per bracket, green/red colored
- [ ] Per-match outcome block strip in chronological order (green/red/yellow)
- [ ] Setting "Show session summary after leaving arena" (Settings > Insights) disables it
- [ ] `/run AI.ShowSessionSummary()` shows the popup on demand
- [ ] "Session" toggle in Insights filter bar restricts match list AND stats bar to the latest session

## Story 2: Queue timer overlay

- [ ] Overlay appears when entering any PvP queue, hides when leaving/entering the match
- [ ] Shows queue name and elapsed time (mm:ss), updating live
- [ ] Shows "Ready!" when the queue pops
- [ ] Multiple simultaneous queues listed as separate rows
- [ ] Draggable; position persists across reload
- [ ] Setting "Show queue timer overlay while queued" (Settings > Insights) disables it
- [ ] VERIFY: GetBattlefieldStatus/GetBattlefieldTimeWaited return real values in Midnight (`/dump GetBattlefieldStatus(1)` while queued)

## Story 3: Death recap (Solo Shuffle v1)

Compact recap per death: damage of the last X seconds aggregated by source+spell,
plus killing blow. NOT a raw combat log (SavedVariables size). SS rounds only in v1 —
rides on the round-capture GUID maps; 2v2/3v3 is a follow-up after the pipeline is
proven live.

- [ ] Hovering a round row in Insights detail shows: outcome header, kill feed with timestamps, killing blow per death
- [ ] Player's own death additionally shows top damage lines over the recap window
- [ ] Recap window adjustable 3-15s in Settings > Insights (default 8)
- [ ] Setting "Capture death recaps during rounds" disables buffering entirely
- [ ] Recaps persist in SavedVariables and are inspectable after reload
- [ ] VERIFY: enemy damage/spell names are readable (not secret) in rated SS; if secret, recap lines show "Unknown" and this story needs rescoping

## Story 4: Match simulator (dev tooling)

- [ ] `/ai sim` adds 1 simulated match; `/ai sim 10` adds 10 spread over one session
- [ ] Simulated rows show steel-blue date + "(simulated)" tooltip line
- [ ] Session popup, Session filter, round rows, and death-recap tooltips all render from simulated data
- [ ] `/ai sim clear` removes every simulated record, live data untouched

## Story 5: Capture health + season tagging

- [ ] `/ai health` prints unknown-outcome / missing-rating / missing-MMR counts and SS round-capture completeness
- [ ] New records carry rec.season when GetCurrentArenaSeason() is available (VERIFY in-game: `/dump GetCurrentArenaSeason()`)
- [ ] Simulated matches excluded from health stats

## Story 6: Comp record + streak

- [ ] 2v2/3v3 row tooltip shows "Vs this comp: W-L lifetime" (same char, exact enemy comp)
- [ ] Session popup shows current W/L streak when >= 2
