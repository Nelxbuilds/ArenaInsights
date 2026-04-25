# Epic 10 — Rename & Rebrand

Rename the addon from "NelxRated" to the new name (TBD). Update all identity strings in code, config, and docs. Preserve existing user data via a one-time SavedVariables migration. Maintain backward compatibility for old export files.

**Prerequisite**: Final name decided. Fill all placeholders before implementing.

| Placeholder | Value |
|------------|-------|
| `<NEWNAME>` | PascalCase addon title — e.g. `ArenaCodex` |
| `<NEWNAME_UPPER>` | Uppercase — e.g. `ARENACODEX` |
| `<NEWNAME_NS>` | Namespace prefix (2–4 chars) — e.g. `AC` |
| `<NEWNAME_DB>` | SavedVariables name — e.g. `ArenaCodexDB` |
| `<NEWNAME_SLASH>` | Primary slash command — e.g. `/ac` |
| `<NEWNAME_SLUG>` | CurseForge slug — e.g. `arena-codex` |
| `<NEWNAME_GITHUB>` | GitHub repo URL after rename |
| `<NEWNAME_CF_URL>` | CurseForge project URL after rename |

---

## Story 10-1 — SavedVariables Migration

**Goal**: Ensure existing users' data (ratings, challenges, settings, overlay position) carries over automatically when they update to the renamed addon.

**Acceptance Criteria**:

- [ ] `Core.lua` contains a migration block that runs before `InitDB()` on `PLAYER_LOGIN`
- [ ] Migration logic: if `NelxRatedDB` exists and `<NEWNAME_DB>` does not, copy reference and nil out old global
- [ ] Migration runs exactly once — subsequent logins skip it (old global is nil after first run)
- [ ] All existing character data, challenges, settings, and overlay position preserved after migration
- [ ] No migration message shown to user (silent)
- [ ] TOC `SavedVariables:` field updated to `<NEWNAME_DB>`
- [ ] TOC still declares `NelxRatedDB` as a legacy `SavedVariables` entry so WoW loads it into scope for migration to read

**Technical Hints**:

```lua
-- In PLAYER_LOGIN handler, before InitDB():
if NelxRatedDB and not <NEWNAME_DB> then
    <NEWNAME_DB> = NelxRatedDB
    NelxRatedDB = nil
end
```

TOC during migration window:
```
## SavedVariables: NelxRatedDB <NEWNAME_DB>
```
After confirmed safe (future release): remove `NelxRatedDB` from TOC.

---

## Story 10-2 — Code Identity Rename

**Goal**: Replace all NelxRated identity strings in Lua code with new name equivalents.

**Acceptance Criteria**:

- [ ] All `NelxRatedDB` references replaced with `<NEWNAME_DB>` across all Lua files (~90 occurrences total)
- [ ] Namespace declaration updated: `local addonName, NXR = ...` → `local addonName, <NEWNAME_NS> = ...`
- [ ] All `NXR.*` references replaced with `<NEWNAME_NS>.*` across all Lua files
- [ ] Slash command variables updated in `Core.lua`:
  - `SLASH_NELXRATED1` / `SLASH_NELXRATED2` → `SLASH_<NEWNAME_UPPER>1`
  - `SlashCmdList["NELXRATED"]` → `SlashCmdList["<NEWNAME_UPPER>"]`
  - Old `/nxr` and `/nelxrated` commands removed
  - New primary slash command is `<NEWNAME_SLASH>`
- [ ] Global frame name updated in `MainFrame.lua` (both `CreateFrame` call and `UISpecialFrames` registration): `NelxRatedMainFrame` → `<NEWNAME>MainFrame`
- [ ] All UI label `SetText()` calls updated: `"NelxRated"` → `"<NEWNAME>"`
- [ ] All `print()` chat output updated: `"NelxRated"` → `"<NEWNAME>"`
- [ ] CLAUDE.md updated with new name, DB name, namespace, and slash commands

**Files to touch**:
- `Core.lua`, `MainFrame.lua`, `Overlay.lua`, `SettingsUI.lua`
- `Challenges.lua`, `ChallengesUI.lua`, `HistoryUI.lua`, `CharactersUI.lua`, `ImportExportUI.lua`
- `HomeUI.lua`
- `CLAUDE.md`

---

## Story 10-3 — Import/Export Backward Compatibility

**Goal**: Old export strings created by NelxRated still import successfully after rename. New exports use the new header.

**Acceptance Criteria**:

- [ ] `ImportExportUI.lua` defines three header constants:
  - `HEADER_V1 = "NelxRated-Export-v1"` — accepted on import, never written
  - `HEADER_V2 = "NelxRated-Export-v2"` — accepted on import, never written
  - `HEADER_V3 = "<NEWNAME>-Export-v1"` — written by export, accepted on import
- [ ] Import validation accepts all three headers
- [ ] Export always writes `HEADER_V3`
- [ ] Import with old header (`V1`/`V2`) shows no warning or error — silent compat
- [ ] Existing import/export merge safety (D2 lint rule) unaffected

---

## Story 10-4 — Manifest & Packaging

**Goal**: TOC file and packaging config reflect new name.

**Acceptance Criteria**:

- [ ] `NelxRated.toc` renamed to `<NEWNAME>.toc`
- [ ] TOC `## Title:` updated to `<NEWNAME>`
- [ ] TOC `## SavedVariables:` includes both `NelxRatedDB` (legacy, for migration) and `<NEWNAME_DB>`
- [ ] TOC `## X-Project-Repository:` updated to `<NEWNAME_GITHUB>`
- [ ] TOC `## X-Issues:` updated to `<NEWNAME_GITHUB>/issues`
- [ ] `.pkgmeta` `package-as:` updated to `<NEWNAME>`

---

## Story 10-5 — Documentation & URLs

**Goal**: All user-facing docs and in-addon URLs updated.

**Acceptance Criteria**:

- [ ] `HomeUI.lua` GitHub URL updated to `<NEWNAME_GITHUB>`
- [ ] `HomeUI.lua` CurseForge URL updated to `<NEWNAME_CF_URL>`
- [ ] `README.md` title, intro, and installation folder name updated
- [ ] `README.md` download link updated to `<NEWNAME_CF_URL>`
- [ ] `README.md` installation step "extract to `NelxRated/`" updated to `<NEWNAME>/`
- [ ] All `docs/epic-*.md` files: `NelxRated`, `NelxRatedDB`, `NXR`, `/nxr` replaced
- [ ] `docs/roadmap.md` placeholders filled with final name
- [ ] `docs/rename-plan.md` can be deleted or archived (purpose fulfilled)

---

## Human TODOs (cannot be automated)

- [ ] **GitHub**: Rename repo `Nelxbuilds/NelxRated` → `Nelxbuilds/<NEWNAME>` via GitHub Settings → General → Repository name
- [ ] **CurseForge**: Rename or re-create project with slug `<NEWNAME_SLUG>` in CurseForge project admin
- [ ] **WoW macros**: Update any in-game macros using `/nxr` or `/nelxrated` to `<NEWNAME_SLASH>`
- [ ] **Local AddOns folder**: Rename `WoW/_retail_/Interface/AddOns/NelxRated/` → `<NEWNAME>/`
- [ ] **Release notes**: Document DB auto-migration, old slash commands removed, NelxRatedCurrency being merged (Phase 1 ships these together)

---

## Verification

1. Fresh WoW install: load addon → all UI shows `<NEWNAME>`, slash `<NEWNAME_SLASH>` works
2. Existing save: copy `NelxRated.lua` SavedVariables → load addon → all data present, no errors
3. Old export string: paste `NelxRated-Export-v2` string into import → import succeeds
4. New export: export → string starts with `<NEWNAME>-Export-v1` → re-import succeeds
5. ESC key closes main frame (UISpecialFrames registration correct)
