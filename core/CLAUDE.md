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
- Events: ADDON_LOADED (bootstrap), PVP_MATCH_ACTIVE (SS round state init), PLAYER_LEAVING_WORLD (bracket snapshot + defensive SS reset), ARENA_PREP_OPPONENT_SPECIALIZATIONS (enemy specs), PVP_MATCH_STATE_CHANGED (SS per-round tracking: state 3=Engaged/round start, state 4/5=PostRound/Complete/round end), UNIT_DIED (SS per-round death capture; registered only while a round is engaged; the combat log is protected for addons and never registered), PVP_MATCH_COMPLETE (Stage 1: finalize any still-engaged round via FinalizeRound(), set ssMatchOver so the next PVP_MATCH_ACTIVE does a full reset, stash pendingRecord), UPDATE_BATTLEFIELD_SCORE (Stage 2: read C_PvP.GetScoreInfo()), PVP_RATED_STATS_UPDATE (Stage 3: finalize, bracket detect, write record)
- SS per-round capture is live: at state 3 (Engaged), StartRoundCapture() reads comp + GUID->{name,specID} maps from unit APIs and snapshots the confirmed rounds-won count (ssPrevWins) as the round's outcome baseline. Comps re-read at round end (RefreshRoundCompAtEnd: specs resolve late; class tokens stored as allyClasses/enemyClasses fallback when a spec never resolves).
- Round outcome, primary source: scoreboard rounds-won delta. After round end a 0.1-0.4s sampling burst (GetSelfRoundsWon) checks whether the count incremented vs the round-start snapshot. The delta is attributed to the round ONLY when the baseline was actually observed (ssWinsExact) — recorded trace shows the indexed scoreboard redacts even the self row mid-match (all fields secret), so reads can fail; a stale baseline must not label a later round. C_PvP.GetScoreInfoByPlayerGuid may bypass the redaction (unverified; Tracer now snapshots it as api.selfScore). Death-derived outcome (team-wipe / death-count compare) is the fallback; at finalize, rounds still unknown are reconciled against authoritative wonRounds (full 6-round captures only — positional assignment, totals exact).
- Rounds-won stat lookup (GetRoundsWonStat): stat column order varies — resolve via C_PvP.GetCustomVictoryStatID() pvpStatID match, then column-name match, then range-checked stats[1]. Self row via C_PvP.GetScoreInfoByPlayerGuid, fallback name scan.
- Deaths: direct UNIT_DIED event only; it passes the dead player's GUID (confirmed by trace), unit-token form kept as fallback. NEVER register COMBAT_LOG_EVENT_UNFILTERED — it is protected for addons in Midnight 12.x and raises ADDON_ACTION_FORBIDDEN even inside pcall (removed entirely, including the death-recap feature). RecordRoundDeath dedups by GUID. Enemy unit GUIDs are secret at round start, so an untracked Player- GUID with a non-empty ally map and empty enemy map is inferred as enemy. UNIT_DIED is sparse in live (3 events over 6 rounds recorded) — kill feed is partial, never an outcome source.
- Three-stage capture: score data attempted on UPDATE_BATTLEFIELD_SCORE, retried + bracket detected on PVP_RATED_STATS_UPDATE (after Core.lua writes new ratings)
- Match record written to ArenaInsightsDB.matches[]: { timestamp, bracketIndex, charKey, specID, outcome, rating, ratingChange, prematchMMR, mmrChange, wonRounds, enemySpecs, allySpecs, shuffle? }
- allySpecs={} — teammate spec IDs for 2v2/3v3 (captured via GetInspectSpecialization at ARENA_PREP; best-effort, may contain nil entries if inspect cache unpopulated)
- outcome: SS uses wonRounds (>3 "win", <3 "loss", ==3 "draw"); all other brackets use ratingChange sign
- wonRounds — SS only (top-level): total rounds won, via GetRoundsWonStat over the self scoreboard row
- shuffle — SS only: { wonRounds, lostRounds, totalRounds=6, rounds? }
  - rounds[i] = { num, outcome, duration, allySpecs, enemySpecs, deaths }; stored when any rounds captured (#ssRounds > 0), so partial/DNF matches keep what was seen
  - rounds[i].allySpecs = teammates ONLY (max 2) — self is rendered from rec.specID; do not include the player's own spec here
  - rounds[i].outcome from the rounds-won sampling burst (see above); death counts and finalize reconciliation as fallbacks
  - rounds[i].deaths = [{ name, specID, side ("ally"/"enemy"), t }] — ordered kill log, t = seconds into round; sparse in live (UNIT_DIED does not fire for every death)
- enemySpecs={} for Blitz BG (ARENA_PREP_OPPONENT_SPECIALIZATIONS does not fire)
- AI.GetLatestSession(charKey) — matches of the most recent play session (consecutive gaps < 1h), chronological; charKey nil = across all characters
- AI.GetSessionMMRDelta(session, bracketIndex) — session MMR movement derived from prematchMMR diff (first vs newest session match, + newest mmrChange); scoreboard post-match MMR is 0 in Midnight so summing mmrChange shows +0. Per-spec brackets compare only the newest match's spec. nil when no MMR data
- AI.GetArenaCompStats() / AI.GetShuffleSpecStats() — Matchups tab aggregation over the full dataset (all characters), computed on demand, never stored. Arena: one entry per bracket+sorted enemy comp ({key, bracketIndex, specs, w, l}); SS: round-level, one entry per enemy spec ({specID, w, l}). Live and simulated records never mix (sim used only when zero live data)
- After match write, nil-guarded UI hooks fire: AI.OnMatchRecorded(rec) (SessionUI popup), AI.RefreshInsights()
- rec.season tagged at write via GetCurrentArenaSeason() (guarded; nil if API unavailable) — reserved for future archiving/pruning
- AI.PrintCaptureHealth() — /ai health; per-field capture-quality summary over non-simulated matches

## Tracer.lua
- Dev tooling: /ai trace toggles recording of the event stream + API snapshots Insights consumes, into ArenaInsightsDB.trace (stub-api shape, replayable via tests/replay.lua); /ai trace clear deletes
- Secret values recorded as "<<SECRET>>" strings; 4000-event cap
- Also records UNIT_DIED (resolved unit + between-rounds scoreboard), full per-row stats arrays (pvpStatID/name/value), and C_PvP.GetCustomVictoryStatID() per event — verifies the rounds-won sampling pipeline from a real match
- AI.TraceToggle(), AI.TraceClear()

## Simulator.lua
- Dev tooling: /ai sim [n] fabricates complete match records (rounds, deaths) tagged simulated=true, through the same write path + UI hooks as live capture; /ai sim clear removes them all
- Tests ALL UI surfaces without queueing; does NOT exercise live event capture (handlers read live APIs)
- AI.SimulateMatches(n) (capped 50), AI.ClearSimulatedMatches()
- Simulated and live records never mix in aggregations (checks rec.simulated)
