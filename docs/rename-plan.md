# Addon Rename Plan

## Context
Rename addon from "NelxRated" to a new name (TBD). Replace all identity strings in code, config, and docs. Preserve user data via DB migration. Keep old export headers importable.

## Placeholders
Replace these before executing:

| Placeholder | Meaning | Example |
|------------|---------|---------|
| `<NEWNAME>` | Addon folder/title (PascalCase) | `ArenaLedger` |
| `<NEWNAME_UPPER>` | Uppercase for slash cmd var | `ARENALEDGER` |
| `<NEWNAME_LOWER>` | Lowercase for slash cmd + CurseForge slug | `arenaledger` |
| `<NEWNAME_NS>` | Namespace short prefix (2-4 chars) | `AL` |
| `<NEWNAME_DB>` | SavedVariables name | `ArenaLedgerDB` |
| `<NEWNAME_SLASH>` | Primary slash cmd | `/al` |
| `<NEWNAME_SLUG>` | CurseForge project slug | `arena-ledger` |

---

## Human TODOs (cannot be automated)

- [ ] **GitHub**: Rename repo `Nelxbuilds/NelxRated` → `Nelxbuilds/<NEWNAME>` (Settings → Rename)
- [ ] **CurseForge**: Create new project with slug `<NEWNAME_SLUG>` OR rename existing project in CurseForge admin
- [ ] **CurseForge URL**: Update project URL in HomeUI.lua and README after new slug confirmed
- [ ] **GitHub URL**: Update repo URLs in HomeUI.lua and README after repo rename confirmed
- [ ] **WoW Macros**: Update any `/nxr` or `/nelxrated` macros in-game after release
- [ ] **Local WoW folder**: Rename addon folder `NelxRated/` → `<NEWNAME>/` in WoW AddOns directory
- [ ] **Release notes**: Document DB auto-migration + slash command changes

---

## Code Changes

### Step 1 — DB Migration (Core.lua) — DO THIS FIRST
Add to top of `PLAYER_LOGIN` handler, before `InitDB()`:
```lua
-- One-time migration from old SavedVariables name
if NelxRatedDB and not <NEWNAME_DB> then
    <NEWNAME_DB> = NelxRatedDB
    NelxRatedDB = nil
end
```

### Step 2 — TOC file (`NelxRated.toc`)
- `## Title: NelxRated` → `## Title: <NEWNAME>`
- `## SavedVariables: NelxRatedDB` → `## SavedVariables: <NEWNAME_DB>`
- GitHub URL lines → new repo URL
- Rename file: `NelxRated.toc` → `<NEWNAME>.toc`

### Step 3 — Slash commands (Core.lua ~line 321)
```lua
-- Before
SLASH_NELXRATED1 = "/nxr"
SLASH_NELXRATED2 = "/nelxrated"
SlashCmdList["NELXRATED"] = ...

-- After
SLASH_<NEWNAME_UPPER>1 = "<NEWNAME_SLASH>"
SlashCmdList["<NEWNAME_UPPER>"] = ...
```

### Step 4 — Global DB references (batch replace across all Lua files)
`NelxRatedDB` → `<NEWNAME_DB>` in:
- `Core.lua` (~15 occurrences)
- `Overlay.lua` (~22 occurrences)
- `SettingsUI.lua` (~30 occurrences)
- `Challenges.lua` (~7 occurrences)
- `ChallengesUI.lua` (~2 occurrences)
- `HistoryUI.lua` (~6 occurrences)
- `CharactersUI.lua` (~2 occurrences)
- `ImportExportUI.lua` (~6 occurrences)

### Step 5 — Namespace prefix (batch replace across all Lua files)
`NXR` → `<NEWNAME_NS>` everywhere, including:
- `local addonName, NXR = ...` → `local addonName, <NEWNAME_NS> = ...`

### Step 6 — Frame name (MainFrame.lua ~lines 180, 192)
```lua
-- Both lines must match
CreateFrame("Frame", "NelxRatedMainFrame", ...)
tinsert(UISpecialFrames, "NelxRatedMainFrame")
-- →
CreateFrame("Frame", "<NEWNAME>MainFrame", ...)
tinsert(UISpecialFrames, "<NEWNAME>MainFrame")
```

### Step 7 — Import/Export headers (ImportExportUI.lua ~lines 7-8)
Keep old headers as accepted inputs for backward compatibility, add new export header:
```lua
local HEADER_V1 = "NelxRated-Export-v1"   -- keep: accept on import
local HEADER_V2 = "NelxRated-Export-v2"   -- keep: accept on import
local HEADER_V3 = "<NEWNAME>-Export-v1"   -- new: use for export output
```
Export writes `HEADER_V3`. Import validation accepts all three.

### Step 8 — UI labels (batch replace)
`NelxRated` → `<NEWNAME>` in all `SetText()` calls and `print()` statements.

### Step 9 — .pkgmeta
`package-as: NelxRated` → `package-as: <NEWNAME>`

### Step 10 — Docs + CLAUDE.md
Batch replace `NelxRated`, `NelxRatedDB`, `NXR`, `/nxr`, `/nelxrated` in:
- `CLAUDE.md`
- `README.md`
- `docs/epic-*.md`

---

## Critical Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| DB rename without migration | All user data lost | Step 1 must be done first |
| Old exports with `NelxRated-Export-v*` headers | Import fails | Keep old headers in validation (Step 7) |
| Slash cmd var naming wrong | WoW won't register command | Must follow pattern: `SLASH_<UPPER>N` + matching `SlashCmdList["<UPPER>"]` |

---

## Execution Order

1. Fill in all placeholders above
2. **Step 1** (DB migration) — always first
3. Steps 2–9 — any order, can batch
4. Step 10 — docs last
5. Human TODOs — after GitHub/CurseForge confirmed
