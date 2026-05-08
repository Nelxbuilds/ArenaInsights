# Epic 10 — Rename & Rebrand: NelxRated → ArenaInsights

Rename the addon from "NelxRated" to "ArenaInsights". Update all identity strings in code, config, and docs. Preserve existing user data via a one-time SavedVariables migration. Maintain backward compatibility for old export files.

| Placeholder | Resolved Value |
|------------|----------------|
| Name | `ArenaInsights` |
| Uppercase | `ARENAINSIGHTS` |
| Namespace | `AI` |
| SavedVariables | `ArenaInsightsDB` |
| Slash command | `/ai` |
| CurseForge slug | `arena-insights` |
| GitHub URL | `https://github.com/Nelxbuilds/ArenaInsights` |
| CurseForge URL | `https://www.curseforge.com/wow/addons/arena-insights` |

---

## Story 10-1 — SavedVariables Migration

**Goal**: Ensure existing users' data (ratings, challenges, settings, overlay position) carries over automatically when they update to the renamed addon.

**Acceptance Criteria**:

- [x] `Core.lua` contains a migration block that runs before `InitDB()` on `ADDON_LOADED`
- [x] Migration logic: if `NelxRatedDB` exists and `ArenaInsightsDB` does not, copy reference and nil out old global
- [x] Migration runs exactly once — subsequent logins skip it (old global is nil after first run)
- [x] All existing character data, challenges, settings, and overlay position preserved after migration
- [x] No migration message shown to user (silent)
- [x] TOC `SavedVariables:` field updated to `ArenaInsightsDB`
- [x] TOC still declares `NelxRatedDB` as a legacy `SavedVariables` entry so WoW loads it into scope for migration to read

**Technical Hints**:

```lua
-- In ADDON_LOADED handler, before InitDB():
if NelxRatedDB and not ArenaInsightsDB then
    ArenaInsightsDB = NelxRatedDB
    NelxRatedDB = nil
end
```

TOC during migration window:
```
## SavedVariables: NelxRatedDB ArenaInsightsDB
```
After confirmed safe (future release): remove `NelxRatedDB` from TOC.

---

## Story 10-2 — Code Identity Rename

**Goal**: Replace all NelxRated identity strings in Lua code with new name equivalents.

**Acceptance Criteria**:

- [x] All `NelxRatedDB` references replaced with `ArenaInsightsDB` across all Lua files (~90 occurrences total)
- [x] Namespace declaration updated: `local addonName, NXR = ...` → `local addonName, AI = ...`
- [x] All `NXR.*` references replaced with `AI.*` across all Lua files
- [x] Slash command variables updated in `Core.lua`:
  - `SLASH_NELXRATED1` / `SLASH_NELXRATED2` → `SLASH_ARENAINSIGHTS1`
  - `SlashCmdList["NELXRATED"]` → `SlashCmdList["ARENAINSIGHTS"]`
  - Old `/nxr` and `/nelxrated` commands removed
  - New primary slash command is `/ai`
- [x] Global frame name updated in `MainFrame.lua` (both `CreateFrame` call and `UISpecialFrames` registration): `NelxRatedMainFrame` → `ArenaInsightsMainFrame`
- [x] All UI label `SetText()` calls updated: `"NelxRated"` → `"ArenaInsights"`
- [x] All `print()` chat output updated: `"NelxRated"` → `"ArenaInsights"`
- [x] CLAUDE.md updated with new name, DB name, namespace, and slash commands

**Files to touch**:
- `Core.lua`, `MainFrame.lua`, `Overlay.lua`, `SettingsUI.lua`
- `Challenges.lua`, `ChallengesUI.lua`, `HistoryUI.lua`, `CharactersUI.lua`, `ImportExportUI.lua`
- `HomeUI.lua`
- `CLAUDE.md`

---

## Story 10-3 — Import/Export Backward Compatibility

**Goal**: Old export strings created by NelxRated still import successfully after rename. New exports use the new header.

**Acceptance Criteria**:

- [x] `ImportExportUI.lua` defines three header constants:
  - `HEADER_V1 = "NelxRated-Export-v1"` — accepted on import, never written
  - `HEADER_V2 = "NelxRated-Export-v2"` — accepted on import, never written
  - `HEADER_V3 = "ArenaInsights-Export-v1"` — written by export, accepted on import
- [x] Import validation accepts all three headers
- [x] Export always writes `HEADER_V3`
- [x] Import with old header (`V1`/`V2`) shows no warning or error — silent compat
- [x] Existing import/export merge safety (D2 lint rule) unaffected

---

## Story 10-4 — Manifest & Packaging

**Goal**: TOC file and packaging config reflect new name.

**Acceptance Criteria**:

- [x] `NelxRated.toc` renamed to `ArenaInsights.toc`
- [x] TOC `## Title:` updated to `ArenaInsights`
- [x] TOC `## SavedVariables:` includes both `NelxRatedDB` (legacy, for migration) and `ArenaInsightsDB`
- [x] TOC `## X-Project-Repository:` updated to `https://github.com/Nelxbuilds/ArenaInsights`
- [x] TOC `## X-Issues:` updated to `https://github.com/Nelxbuilds/ArenaInsights/issues`
- [x] `.pkgmeta` `package-as:` updated to `ArenaInsights`

---

## Story 10-5 — Documentation & URLs

**Goal**: All user-facing docs and in-addon URLs updated.

**Acceptance Criteria**:

- [x] `HomeUI.lua` GitHub URL updated to `https://github.com/Nelxbuilds/ArenaInsights`
- [x] `HomeUI.lua` CurseForge URL updated to `https://www.curseforge.com/wow/addons/arena-insights`
- [x] `README.md` title, intro, and installation folder name updated
- [x] `README.md` download link updated to `https://www.curseforge.com/wow/addons/arena-insights`
- [x] `README.md` installation step "extract to `NelxRated/`" updated to `ArenaInsights/`
- [x] All `docs/epic-*.md` files: `NelxRated`, `NelxRatedDB`, `NXR`, `/nxr` replaced
- [x] `docs/roadmap.md` placeholders filled with final name
- [x] `docs/rename-plan.md` can be deleted or archived (purpose fulfilled)

---

## Human TODOs (cannot be automated)

- [ ] **GitHub**: Rename repo `Nelxbuilds/NelxRated` → `Nelxbuilds/ArenaInsights` via GitHub Settings → General → Repository name
- [ ] **CurseForge**: Rename or re-create project with slug `arena-insights` in CurseForge project admin
- [ ] **WoW macros**: Update any in-game macros using `/nxr` or `/nelxrated` to `/ai`
- [ ] **Local AddOns folder**: Rename `WoW/_retail_/Interface/AddOns/NelxRated/` → `ArenaInsights/`
- [ ] **Release notes**: Document DB auto-migration, old slash commands removed, NelxRatedCurrency being merged (Phase 1 ships these together)

---

## Verification

1. Fresh WoW install: load addon → all UI shows `ArenaInsights`, slash `/ai` works
2. Existing save: copy `NelxRated.lua` SavedVariables → load addon → all data present, no errors
3. Old export string: paste `NelxRated-Export-v2` string into import → import succeeds
4. New export: export → string starts with `ArenaInsights-Export-v1` → re-import succeeds
5. ESC key closes main frame (UISpecialFrames registration correct)
