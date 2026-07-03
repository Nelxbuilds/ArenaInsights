# core/ — Data and Logic Layer

Pure Lua: no CreateFrame, no UI widgets. Establishes AI.* data API for all other layers.
Load order: Core.lua → Currency.lua → Challenges.lua

## Core.lua
- AI namespace entry point
- Bracket constants: AI.BRACKET_2V2(1) / 3V3(2) / BLITZ(4) / SOLO_SHUFFLE(7)
- InitDB() — migrations, merges SETTINGS_DEFAULTS
- AI.UpdateCharacterInfo() — name/realm/class/spec capture
- AI.SaveBracketData() — writes rating+MMR, appends ratingHistory (cap 250)
- AI.GetRating(), AI.GetRatingHistory() — read accessors
- Events: ADDON_LOADED, PLAYER_ENTERING_WORLD, ACTIVE_TALENT_GROUP_CHANGED, PVP_RATED_STATS_UPDATE
- Slash: /ai → delegates to AI.ToggleMainFrame, AI.Overlay, AI.InitiateSync

## Currency.lua
- AI.TRACKED_CURRENCIES — {id, name} for Honor/Conquest/Bloody Tokens
- AI.TRACKED_ITEMS — {id, name} for Mark/Flask/Medal of Honor
- CaptureCurrencyData() — reads C_CurrencyInfo + GetItemCount per char
- Events: CURRENCY_DISPLAY_UPDATE, BAG_UPDATE_DELAYED, PLAYER_ENTERING_WORLD
- WARNING: AI.TRACKED_CURRENCIES/ITEMS read at module-load time by ui/CurrencyUI.lua — must load before it (enforced by TOC order)

## Challenges.lua
- AI.classData, AI.specData, AI.roleSpecs, AI.sortedClassIDs — built by BuildSpecData()
- AI.BuildSpecData() — called at ADDON_LOADED; enumerates via GetClassInfo/GetSpecializationInfoForClassID
- Challenge CRUD: AI.AddChallenge, AI.DeleteChallenge, AI.SetChallengeActive
- AI.GetActiveChallenge() — returns active from ArenaInsightsDB.challenges
- All calls to AI.RefreshOverlay() are nil-guarded — no load-order coupling to ui/

## Insights.lua
- Data-only module: no CreateFrame, no UI widgets, no print() chat output
- AI.GetMatches() — returns ArenaInsightsDB.matches or {}; does not mutate; sole read accessor (no other file reads ArenaInsightsDB.matches directly)
- AI.InsightsDebug — set true via `/run AI.InsightsDebug = true` to dump event payloads and score data to chat; defaults false
- Events: ADDON_LOADED (bootstrap), PVP_MATCH_ACTIVE (SS round state init), PLAYER_LEAVING_WORLD (bracket snapshot + defensive SS reset), ARENA_PREP_OPPONENT_SPECIALIZATIONS (enemy specs), PVP_MATCH_STATE_CHANGED (SS per-round tracking: state 3=Engaged/round start, state 4/5=PostRound/Complete/round end), COMBAT_LOG_EVENT_UNFILTERED (SS per-round death capture; registered only while a round is engaged), PVP_MATCH_COMPLETE (Stage 1: stash pendingRecord), UPDATE_BATTLEFIELD_SCORE (Stage 2: read C_PvP.GetScoreInfo()), PVP_RATED_STATS_UPDATE (Stage 3: finalize, bracket detect, write record)
- SS per-round capture is live (scoreboard is empty mid-round): at state 3 (Engaged), StartRoundCapture() reads comp + GUID->{name,specID} maps from unit APIs (player spec via GetSpecialization; party1/2 via GetInspectSpecialization best-effort; enemy GUIDs read off arena1..5 unit tokens via UnitExists/UnitGUID, enemy spec via GetArenaOpponentSpec best-effort). Round outcome = full-team-wipe detection (ally side reliably mapped), falling back to raw death-count compare. COMBAT_LOG_EVENT_UNFILTERED UNIT_DIED records deaths for the 6 player GUIDs only. At round end, outcome derived from death counts (eliminated team has more deaths -> the other side wins).
- Three-stage capture: score data attempted on UPDATE_BATTLEFIELD_SCORE, retried + bracket detected on PVP_RATED_STATS_UPDATE (after Core.lua writes new ratings)
- Match record written to ArenaInsightsDB.matches[]: { timestamp, bracketIndex, charKey, specID, outcome, rating, ratingChange, prematchMMR, mmrChange, wonRounds, enemySpecs, allySpecs, shuffle? }
- allySpecs={} — teammate spec IDs for 2v2/3v3 (captured via GetInspectSpecialization at ARENA_PREP; best-effort, may contain nil entries if inspect cache unpopulated)
- outcome: SS uses wonRounds (>3 "win", <3 "loss", ==3 "draw"); all other brackets use ratingChange sign
- wonRounds — SS only (top-level): total rounds won, from C_PvP.GetScoreInfo().stats[1].pvpStatValue
- shuffle — SS only: { wonRounds, lostRounds, totalRounds=6, rounds? }
  - rounds[i] = { num, outcome, duration, allySpecs, enemySpecs, deaths }; stored when any rounds captured (#ssRounds > 0), so partial/DNF matches keep what was seen
  - rounds[i].outcome resolved at round end from live death counts (win = enemy team eliminated); no longer scoreboard-derived
  - rounds[i].deaths = [{ name, specID, side ("ally"/"enemy"), t }] — ordered kill log, t = seconds into round. Captured for all 6 players. UI not yet built (data-only for now).
- enemySpecs={} for Blitz BG (ARENA_PREP_OPPONENT_SPECIALIZATIONS does not fire)
