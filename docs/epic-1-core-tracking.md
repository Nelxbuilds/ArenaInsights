# Epic 1 — Core & Data Layer

Initialize the addon, set up SavedVariables with a safe default structure, capture character info on login/spec change, and record rating + MMR from all PvP brackets after each game.

---

## Story 1-1 — Addon Bootstrap & SavedVariables

**Goal**: Create the addon entry point, namespace table (`NXR`), and initialize `NelxRatedDB` with a safe default structure on first load.

**Acceptance Criteria**:

- [x] `NelxRated.toc` declares `SavedVariables: NelxRatedDB` and lists all Lua files in load order
- [x] `Core.lua` receives the addon namespace via `local addonName, NXR = ...`
- [x] On `ADDON_LOADED`, `NelxRatedDB` is initialized with: `settings = {}`, `characters = {}`, `challenges = {}`, `overlayPosition = {}`, `schemaVersion = 1`
- [x] Bracket constants are defined: `NXR.BRACKET_2V2 = 0`, `NXR.BRACKET_3V3 = 1`, `NXR.BRACKET_BLITZ = 4`, `NXR.BRACKET_SOLO_SHUFFLE = 7`
- [x] `NXR.BRACKET_NAMES` maps each index to a display name: `"2v2"`, `"3v3"`, `"Blitz BG"`, `"Solo Shuffle"`
- [x] `NXR.PER_SPEC_BRACKETS = { [4] = true, [7] = true }` — Blitz and Solo Shuffle ratings are per-spec, not per-character
- [x] `NelxRatedDB` is not read at file-load time — only inside or after `ADDON_LOADED`
- [x] Settings defaults: `accountName = ""`, `opacityInArena = 1.0`, `opacityOutOfArena = 1.0`, `showOverlayBackground = true`

**Technical Hints**:

- Guard with `NelxRatedDB = NelxRatedDB or {}`; then init sub-tables
- The Blitz BG bracket index (4) should be verified in-game via `/dump C_PvP.GetRatedBracketInfo(4)`

---

## Story 1-2 — Character Information Capture

**Goal**: On login and spec change, capture the current character's identifying info and upsert it into `NelxRatedDB.characters`.

**Acceptance Criteria**:

- [x] On `PLAYER_ENTERING_WORLD`, the current character's name, realm, class, spec, and account are captured
- [x] On `ACTIVE_TALENT_GROUP_CHANGED`, the spec fields are updated
- [x] Character key is `"Name-Realm"` (original casing)
- [x] Name/realm via `UnitName("player")` + `GetRealmName()` fallback
- [x] Class via `UnitClass("player")` — store both `classFileName` (e.g. `"WARRIOR"`) and `classDisplayName` (e.g. `"Warrior"`)
- [x] Spec via `GetSpecialization()` + `GetSpecializationInfo()` — store `specID`, `specName`
- [x] Account name read from `NelxRatedDB.settings.accountName`
- [x] If a character record already exists, mutable fields are updated in-place; bracket data is preserved
- [x] New characters get empty `brackets = {}` and `specBrackets = {}` tables
- [x] `NXR.UpdateCharacterInfo()` is exposed for other modules to call

---

## Story 1-3 — Rating & MMR Capture

**Goal**: After each rated PvP game, capture rating and MMR for all tracked brackets and persist them.

**Acceptance Criteria**:

- [x] The addon registers for `PVP_RATED_STATS_UPDATE` (the only reliable event in 12.x)
- [x] On event, `C_PvP.GetRatedBracketInfo(bracketIndex)` is called for all four brackets (2v2, 3v3, Blitz BG, Solo Shuffle)
- [x] Nil-guard: if `C_PvP` or `C_PvP.GetRatedBracketInfo` is nil, the capture is skipped silently
- [x] Only brackets with `seasonPlayed > 0` are saved (skip unplayed brackets)
- [x] Per-character brackets (2v2, 3v3) are stored in `characters[key].brackets[bracketIndex] = { rating, mmr, updatedAt }`
- [x] Per-spec brackets (Solo Shuffle, Blitz) are stored in `characters[key].specBrackets[specID][bracketIndex] = { rating, mmr, updatedAt }`
- [x] `NXR.GetRating(charKey, bracketIndex, specID)` returns the correct bracket data regardless of bracket type
- [x] A 0.5s debounce prevents duplicate captures from rapid event firing
- [x] After capture, `NXR.RefreshOverlay()` is called if it exists
- [x] `NXR.SaveBracketData(bracketIndex, rating, mmr)` is exposed as a public API

**Technical Hints**:

- Use `C_Timer.After(0.5, fn)` for the debounce
- Call `NXR.UpdateCharacterInfo()` before capturing to ensure spec is current
