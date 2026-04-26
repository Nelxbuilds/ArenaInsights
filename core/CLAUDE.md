# core/ — Data and Logic Layer

Pure Lua: no CreateFrame, no UI widgets. Establishes NXR.* data API for all other layers.
Load order: Core.lua → Currency.lua → Challenges.lua

## Core.lua
- NXR namespace entry point
- Bracket constants: NXR.BRACKET_2V2(1) / 3V3(2) / BLITZ(4) / SOLO_SHUFFLE(7)
- InitDB() — migrations, merges SETTINGS_DEFAULTS
- NXR.UpdateCharacterInfo() — name/realm/class/spec capture
- NXR.SaveBracketData() — writes rating+MMR, appends ratingHistory (cap 250)
- NXR.GetRating(), NXR.GetRatingHistory() — read accessors
- Events: ADDON_LOADED, PLAYER_ENTERING_WORLD, ACTIVE_TALENT_GROUP_CHANGED, PVP_RATED_STATS_UPDATE
- Slash: /nxr → delegates to NXR.ToggleMainFrame, NXR.Overlay, NXR.InitiateSync

## Currency.lua
- NXR.TRACKED_CURRENCIES — {id, name} for Honor/Conquest/Bloody Tokens
- NXR.TRACKED_ITEMS — {id, name} for Mark/Flask/Medal of Honor
- CaptureCurrencyData() — reads C_CurrencyInfo + GetItemCount per char
- Events: CURRENCY_DISPLAY_UPDATE, BAG_UPDATE_DELAYED, PLAYER_ENTERING_WORLD
- WARNING: NXR.TRACKED_CURRENCIES/ITEMS read at module-load time by ui/CurrencyUI.lua — must load before it (enforced by TOC order)

## Challenges.lua
- NXR.classData, NXR.specData, NXR.roleSpecs, NXR.sortedClassIDs — built by BuildSpecData()
- NXR.BuildSpecData() — called at ADDON_LOADED; enumerates via GetClassInfo/GetSpecializationInfoForClassID
- Challenge CRUD: NXR.AddChallenge, NXR.DeleteChallenge, NXR.SetChallengeActive
- NXR.GetActiveChallenge() — returns active from NelxRatedDB.challenges
- All calls to NXR.RefreshOverlay() are nil-guarded — no load-order coupling to ui/

## Insights.lua
- Data-only module: no CreateFrame, no UI widgets, no print() chat output
- NXR.GetMatches() — returns NelxRatedDB.matches or {}; does not mutate; sole read accessor (no other file reads NelxRatedDB.matches directly)
- NXR.InsightsDebug — set true via `/run NXR.InsightsDebug = true` to dump event payloads and score data to chat; defaults false
- Events: ADDON_LOADED (bootstrap), PLAYER_ENTERING_WORLD (bracket snapshot when instanceType=="arena"/"pvp"), ARENA_PREP_OPPONENT_SPECIALIZATIONS (enemy specs), PVP_MATCH_COMPLETE (Stage 1: detect bracket, stash pendingRecord), UPDATE_BATTLEFIELD_SCORE (Stage 2: read C_PvP.GetScoreInfo(), complete and append record)
- Two-stage capture: C_PvP.GetScoreInfo() has SecretInActivePvPMatch restriction; score data read on UPDATE_BATTLEFIELD_SCORE after PVP_MATCH_COMPLETE
- Match record written to NelxRatedDB.matches[]: { timestamp, bracketIndex, charKey, specID, outcome, rating, ratingChange, prematchMMR, mmrChange, enemySpecs }
- outcome derived from ratingChange sign: >0 "win", <0 "loss", ==0 "draw", nil "unknown"
- enemySpecs={} for Blitz BG (ARENA_PREP_OPPONENT_SPECIALIZATIONS does not fire)
