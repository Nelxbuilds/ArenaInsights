# core/ — Data and Logic Layer

Pure Lua: no CreateFrame, no UI widgets. Establishes AI.* data API for all other layers.
Load order: Core.lua → Currency.lua → Challenges.lua

## Core.lua
- AI namespace entry point
- Bracket constants: AI.BRACKET_2V2(1) / 3V3(2) / BLITZ(4) / SOLO_SHUFFLE(7)
- InitDB() — migrations, merges SETTINGS_DEFAULTS
- AI.UpdateCharacterInfo() — name/realm/class/spec capture
- AI.SaveBracketData() — writes rating+MMR+season (GetCurrentArenaSeason stamp), appends ratingHistory (cap 250)
- Slash: /ai season → AI.PrintSeasonInfo() — diagnostic: current season id + match counts per stamped rec.season
- AI.RaceIconMarkup(char, size) — inline |A:raceicon-<slug>-<gender>:size:size|a, nil when race/gender unknown. Five races' atlas slug is NOT the lowercased UnitRace() file name (Scourge→undead, HighmountainTauren→highmountain, LightforgedDraenei→lightforged, ZandalariTroll→zandalari, EarthenDwarf→earthen); mapped by RACE_ATLAS_SLUG, verified against the 12.1.0 atlas list (build 69404). Sole race-icon builder — ui/ must not format the escape itself
- AI.GetRating(charKey, bracketIndex, specID, seasonId), AI.GetRatingHistory() — read accessors. seasonId (nil = any season) returns the snapshot only when data.season matches; snapshots written before season stamping have season == nil and never match
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
- Season scope per challenge: c.seasonReset (set by the "Reset each season" checkbox, default on for new challenges, nil/lifetime for pre-existing ones). AI.GetChallengeSeason(c) → current season id for season-reset challenges, nil for lifetime; Overlay passes it to AI.GetRating so a rating carried over from an earlier season stops counting
- Manual completions: lifetime challenges keep c.completedSpecs / c.completedClasses; season-reset ones store them under c.seasonProgress[season].completedSpecs / .completedClasses, so a rollover starts clean without discarding last season's ticks
- All calls to AI.RefreshOverlay() are nil-guarded — no load-order coupling to ui/

## Insights.lua
- Data-only module: no CreateFrame, no UI widgets, no print() chat output
- AI.GetMatches() — returns ArenaInsightsDB.matches or {}; does not mutate; sole read accessor (no other file reads ArenaInsightsDB.matches directly)
- Season separation: rec.season (= GetCurrentArenaSeason() stamped at write) IS the season key — no reset detection needed. AI.GetCurrentSeasonId() (live API, falls back to newest rec.season) / AI.HasMultipleSeasons() (matches span >1 season → show toggle). Aggregators take a seasonId filter (rec.season == seasonId; nil = all). AI.GetCurrentSeasonStart() = earliest current-season match timestamp, used to clamp the rating-history graph (entries carry timestamps, no season tag). Legacy matches with rec.season == nil count as "other season"
- AI.InsightsDebug — set true via `/run AI.InsightsDebug = true` to dump event payloads and score data to chat; defaults false
- Events: ADDON_LOADED (bootstrap), PVP_MATCH_ACTIVE (SS round state init), PLAYER_LEAVING_WORLD (bracket snapshot + defensive SS reset), ARENA_PREP_OPPONENT_SPECIALIZATIONS (enemy specs), PVP_MATCH_STATE_CHANGED (SS per-round tracking: state 3=Engaged/round start, state 4/5=PostRound/Complete/round end), UNIT_DIED (SS per-round death capture; registered only while a round is engaged; the combat log is protected for addons and never registered), PVP_MATCH_COMPLETE (Stage 1: finalize any still-engaged round via FinalizeRound(), set ssMatchOver so the next PVP_MATCH_ACTIVE does a full reset, stash pendingRecord), UPDATE_BATTLEFIELD_SCORE (Stage 2: read C_PvP.GetScoreInfo()), PVP_RATED_STATS_UPDATE (Stage 3: finalize, bracket detect, write record)
- SS per-round capture is live: at state 3 (Engaged), StartRoundCapture() reads comp + GUID->{name,specID} maps from unit APIs and snapshots the confirmed rounds-won count (ssPrevWins) as the round's outcome baseline. Comps re-read at round end (RefreshRoundCompAtEnd: specs resolve late; class tokens stored as allyClasses/enemyClasses fallback when a spec never resolves).
- Round outcome, PRIMARY resolver (SolveRoundOutcomes, at finalize): a constraint solve over the readable end-of-match scoreboard — needs no mid-match counter and no death events. Inputs: each round's exact 3v3 partition (your team = self + the 2 captured teammate names; enemy trio = the 5 other lobby players minus your 2 allies) and every player's TOTAL rounds won (self=wonRounds, others=enemyPlayers[].roundsWon). The per-round winners are the unique assignment where, for every player, (rounds on the winning side) == their total. Over-determined (the 6 totals sum to 18), so a misread yields no/multiple solutions and it returns nil (defers to fallback) rather than guessing. Resolves 3-3 draws too. Requires the full 6-player roster and both teammate names per round. Verified against fixtures (0_6_loss defers correctly; live + 3_3_draw resolve exactly, matching independent ground truth).
- Round outcome, FALLBACK (when the solve can't run): scoreboard rounds-won delta. After round end a 0.1-0.4s sampling burst (GetSelfRoundsWon) checks whether the count incremented vs the round-start snapshot. The delta is attributed to the round ONLY when the baseline was actually observed (ssWinsExact) — recorded trace shows the indexed scoreboard redacts even the self row mid-match (all fields secret), so reads can fail; a stale baseline must not label a later round. C_PvP.GetScoreInfoByPlayerGuid bypasses the redaction (live screenshots show per-round attribution working), but its stat column was misread once as cumulative LOSSES, inverting every round — hence strict + drift guards below. Death-derived outcome (team-wipe / death-count compare) is the next fallback; at finalize, rounds still unknown are reconciled against authoritative wonRounds (full 6-round captures only — positional assignment, totals exact). If attributed outcomes CONTRADICT wonRounds (confirmed wins exceed it, or can't reach it), all six are discarded and redistributed positionally — draws (3-3) cannot be cross-checked this way, so a wrong column stays undetectable there until the next trace's selfScore snapshots pin the column layout.
- Rounds-won stat lookup (GetRoundsWonStat): stat column order varies — resolve via C_PvP.GetCustomVictoryStatID() pvpStatID match, then column-name match, then range-checked stats[1]. Mid-match reads (GetSelfRoundsWon) accept ONLY the ID-verified column (requireVictoryID) — unlabeled/name-matched columns may be different counters. Self row via C_PvP.GetScoreInfoByPlayerGuid, fallback name scan.
- Deaths: direct UNIT_DIED event only; it passes the dead player's GUID (confirmed by trace), unit-token form kept as fallback. NEVER register COMBAT_LOG_EVENT_UNFILTERED — it is protected for addons in Midnight 12.x and raises ADDON_ACTION_FORBIDDEN even inside pcall (removed entirely, including the death-recap feature). RecordRoundDeath dedups by GUID. Enemy unit GUIDs are secret at round start, so an untracked Player- GUID with a non-empty ally map and empty enemy map is inferred as enemy. UNIT_DIED is sparse in live (3 events over 6 rounds recorded) — kill feed is partial, never an outcome source.
- Three-stage capture: score data attempted on UPDATE_BATTLEFIELD_SCORE, retried + bracket detected on PVP_RATED_STATS_UPDATE (after Core.lua writes new ratings)
- Match record written to ArenaInsightsDB.matches[]: { timestamp, bracketIndex, charKey, specID, outcome, rating, ratingChange, prematchMMR, mmrChange, wonRounds, enemySpecs, allySpecs, shuffle? }
- allySpecs={} — teammate spec IDs for 2v2/3v3 (captured via GetInspectSpecialization at ARENA_PREP; best-effort, may contain nil entries if inspect cache unpopulated)
- outcome: SS uses majority of rounds PLAYED (won > played/2 "win", < "loss", == "draw"); full match = the >3/<3/==3 rule. Rounds played derived from the six players' rounds-won summing to 3x rounds played (18 for a full match); a leaver ends the lobby early so un-played rounds are never counted. All other brackets use ratingChange sign
- wonRounds — SS only (top-level): total rounds won, via GetRoundsWonStat over the self scoreboard row
- shuffle — SS only: { wonRounds, lostRounds, totalRounds, rounds? } — totalRounds is rounds actually played (6 for a full match, fewer when a leaver ends it early); lostRounds = totalRounds - wonRounds
  - rounds[i] = { num, outcome, duration, allySpecs, enemySpecs, allyNames, allyClasses?, enemyClasses?, deaths }; stored when any rounds captured (#ssRounds > 0), so partial/DNF matches keep what was seen
  - BackfillRoundComps at finalize: ally specs resolved by teammate name from the readable end-of-match scoreboard (inspect cache is usually cold live); with both allies known and all 5 other lobby specs known, the enemy trio is derived by elimination (5 others minus 2 allies) — round comps are exact whenever the final scoreboard is readable
  - rounds[i].allySpecs = teammates ONLY (max 2) — self is rendered from rec.specID; do not include the player's own spec here
  - rounds[i].outcome from the rounds-won sampling burst (see above); death counts and finalize reconciliation as fallbacks
  - rounds[i].deaths = [{ name, specID, side ("ally"/"enemy"), t }] — ordered kill log, t = seconds into round; sparse in live (UNIT_DIED does not fire for every death)
- enemySpecs={} for Blitz BG (ARENA_PREP_OPPONENT_SPECIALIZATIONS does not fire)
- AI.GetLatestSession(charKey) — matches of the most recent play session (consecutive gaps < 1h), chronological; charKey nil = across all characters
- AI.GetSessionMMRDelta(session, bracketIndex) — session MMR movement derived from prematchMMR diff (first vs newest session match, + newest mmrChange); scoreboard post-match MMR is 0 in Midnight so summing mmrChange shows +0. Per-spec brackets compare only the newest match's spec. nil when no MMR data
- AI.GetArenaCompStats(bracketIndex, charKey, specID, seasonIndex) / AI.GetShuffleSpecStats(charKey, specID, seasonIndex) — Matchups tab aggregation, computed on demand, never stored. All params optional (nil = no filter); arena bracketIndex nil = both 2v2+3v3; seasonIndex nil = all seasons. Arena: one entry per bracket+sorted enemy comp ({key, bracketIndex, specs, w, l}); SS: round-level, one entry per enemy spec ({specID, w, l}). Live and simulated records never mix (sim used only when zero live data)
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
