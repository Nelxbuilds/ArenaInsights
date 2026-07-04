# Test checklist v2.5.0-beta1 -> beta3

## A. At the desk (5 min, no queue)

- [ ] 1. Addon loads without errors; version shows 2.5.0-beta3; `/ai` opens
- [ ] 2. `/ai sim 10` -> session popup appears: per-bracket scores (SS as rounds), net rating/MMR, colored match blocks, streak label
- [ ] 3. Insights: simulated rows have steel-blue dates; tooltip says "Simulated match"
- [ ] 4. "Session" toggle (right of spec icons) filters list AND stats bar; toggle off restores all
- [ ] 5. Spec filter: clear it, switch tab, come back -> stays cleared (was: re-applied itself)
- [ ] 6. Expand a simulated SS match: 6 round rows, your icon + 2 DIFFERENT teammate icons vs 3 enemies, WIN/LOSS + duration per round
- [ ] 7. Hover a round row: kill feed with timestamps, "KB:" line per death, damage breakdown for your own death
- [ ] 8. SS detail has sortable MMR column; expand a simulated 2v2/3v3: no MMR column, no leftover round rows, tooltip shows "Vs this comp: W-L"
- [ ] 9. Settings > Insights tab: 3 checkboxes + recap window slider; popup toggle off -> `/ai sim` shows no popup; re-enable
- [ ] 10. `/ai sim clear` -> all simulated rows gone

## B. In queue (1 min)

- [ ] 11. Queue for anything -> queue overlay appears with queue name + counting mm:ss; draggable; position survives /reload
- [ ] 12. On queue pop it shows "Ready!"
- [ ] 13. If overlay stays empty while queued: run `/dump GetBattlefieldStatus(1)` and note the output

## C. One Solo Shuffle with `/ai debug` ON (the pipeline test)

- [ ] 14. Chat during rounds: "Round capture: ... enemyGUIDs=3" (arena unit tokens readable)
- [ ] 15. Chat on kills: "Death: <name> enemy" AND "ally" lines (CLEU + GUID attribution works)
- [ ] 16. After match: rating + MMR recorded; round rows show real comps and outcomes matching what happened
- [ ] 17. Recap tooltip shows real spell/source names -- "Unknown" everywhere means secret values, report back
- [ ] 18. Leave arena -> session popup with real data
- [ ] 19. `/ai health` -> SS round capture counts look right (full/partial)
- [ ] 20. `/dump GetCurrentArenaSeason()` -- note the value (season tagging)

## D. Regression (one game, any time)

- [ ] 21. One 2v2 or 3v3: recorded with rating/MMR/enemy specs, detail has no SS artifacts
- [ ] 22. /reload + relog: no lua errors, overlay + challenges unchanged
