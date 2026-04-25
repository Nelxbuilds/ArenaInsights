# Epic 11 — Currency Tab (NelxRatedCurrency Merge)

Absorb NelxRatedCurrency into the main addon as a Currency tab in the sidebar. Retire NelxRatedCurrency as a standalone addon. Users with existing NelxRatedCurrency data get a one-time migration into the unified DB.

**Depends on**: Epic 10 (rename complete — new DB name established before merge)

---

## Story 11-1 — Currency Data Layer

**Goal**: Port NelxRatedCurrency's data model and capture logic into the main addon's Core module.

**Acceptance Criteria**:

- [ ] `<NEWNAME_NS>.TRACKED_CURRENCIES` defined — array of `{ id, name }` for all tracked PvP currencies (Honor, Conquest, Bloody Tokens, Marks of Honor, etc.)
- [ ] `<NEWNAME_NS>.TRACKED_ITEMS` defined — array of `{ id, name }` for tracked bag items (Mark of Honor, Flask of Honor, Medal of Conquest)
- [ ] `<NEWNAME_DB>.characters[key].currencies` — per-char currency map `[currencyID] = { amount, maxQuantity }`
- [ ] `<NEWNAME_DB>.characters[key].items` — per-char item map `[itemID] = { count }`
- [ ] Currency + item data captured on: `CURRENCY_DISPLAY_UPDATE`, `BAG_UPDATE_DELAYED`, `PLAYER_ENTERING_WORLD`
- [ ] Capture uses `C_CurrencyInfo.GetCurrencyInfo(id)` → `info.quantity`, `info.maxQuantity`
- [ ] Item count uses `GetItemCount(itemID, true)` (includes bank)
- [ ] Nil-guard on all `C_CurrencyInfo` calls
- [ ] `<NEWNAME_NS>.GetCharKey()` reused from existing Core (already exists as `UnitName + "-" + GetRealmName()`)

**Files**: `Core.lua` (add currency capture section) or new `Currency.lua` loaded after Core

---

## Story 11-2 — NelxRatedCurrency Data Migration

**Goal**: Users with existing NelxRatedCurrency SavedVariables data get their currency history carried into the unified DB automatically.

**Acceptance Criteria**:

- [ ] TOC temporarily declares `NelxRatedCurrencyDB` as a `SavedVariables` entry so WoW loads it into scope
- [ ] On `PLAYER_LOGIN`, migration check runs: if `NelxRatedCurrencyDB` exists, merge character currency/item data into `<NEWNAME_DB>.characters`
- [ ] Merge strategy: for each character key in `NelxRatedCurrencyDB.characters`, copy `currencies` and `items` fields into matching key in `<NEWNAME_DB>.characters` — do not overwrite existing rating/challenge data
- [ ] If character key exists in both DBs, currency fields are merged (not replaced)
- [ ] After migration, `NelxRatedCurrencyDB = nil` to free memory (WoW will clear the file on next logout if global is nil)
- [ ] Migration runs once — guarded by a migration flag in `<NEWNAME_DB>` (e.g. `migratedCurrencyDB = true`)
- [ ] Silent — no user-facing message

**Technical Hints**:

```lua
if NelxRatedCurrencyDB and not <NEWNAME_DB>.migratedCurrencyDB then
    for key, charData in pairs(NelxRatedCurrencyDB.characters or {}) do
        local target = <NEWNAME_DB>.characters[key]
        if target then
            target.currencies = charData.currencies
            target.items = charData.items
        else
            -- char only existed in currency addon (never played rated on this char)
            <NEWNAME_DB>.characters[key] = {
                name = charData.name,
                realm = charData.realm,
                classFileName = charData.classFileName,
                classDisplayName = charData.classDisplayName,
                currencies = charData.currencies,
                items = charData.items,
                brackets = {},
                specBrackets = {},
            }
        end
    end
    <NEWNAME_DB>.migratedCurrencyDB = true
    NelxRatedCurrencyDB = nil
end
```

---

## Story 11-3 — Currency Tab UI

**Goal**: Add a Currency tab to the main frame sidebar showing per-character currency and item counts, matching NelxRatedCurrency's overview panel.

**Acceptance Criteria**:

- [ ] "Currency" entry added to main frame sidebar nav (between existing tabs — position TBD, suggest after Characters)
- [ ] Currency tab panel created in new file `UI/CurrencyUI.lua`
- [ ] Panel shows a sortable table: one row per tracked character, columns for each currency and tracked item
- [ ] Columns: Character name (class-colored), Honor, Conquest, Bloody Tokens, Mark of Honor, Flask of Honor, Medal of Conquest — match NelxRatedCurrency's COLUMNS definition
- [ ] Alternating row background colors (match existing UI pattern)
- [ ] Hidden characters (from Settings) excluded from table
- [ ] `<NEWNAME_NS>.CreateCurrencyPanel(parent)` exported from `CurrencyUI.lua`
- [ ] Panel exposes `:Refresh()` — called on tab show and on `CURRENCY_DISPLAY_UPDATE`
- [ ] Column headers clickable to sort ascending/descending
- [ ] Empty state: if no currency data captured yet, show "No data — play a game or reload" message
- [ ] Follows design system (crimson theme, typography, spacing constants)

---

## Story 11-4 — Currency Tooltip Extension

**Goal**: Hovering a PvP currency icon or tracked item in bags shows per-character totals in the tooltip, ported from NelxRatedCurrency.

**Acceptance Criteria**:

- [ ] `Tooltip.lua` (new file) hooks `TooltipDataProcessor.AddTooltipPostCall` for both `Enum.TooltipDataType.Currency` and `Enum.TooltipDataType.Item`
- [ ] Currency tooltip: appends rows for each tracked character showing their quantity (class-colored name + amount)
- [ ] Item tooltip: appends rows for tracked items (Mark of Honor, Flask of Honor, Medal of Conquest) if item matches `TRACKED_ITEMS`
- [ ] Only characters with > 0 quantity shown in tooltip (hide zero rows)
- [ ] Tooltip disabled when `<NEWNAME_DB>.settings.disableTooltip = true`
- [ ] Max characters shown in tooltip: 10 (truncate with "+ N more" if exceeded)
- [ ] Nil-guard: if no currency data for a character, skip silently

---

## Story 11-5 — Minimap Button

**Goal**: Port NelxRatedCurrency's minimap button into the unified addon.

**Acceptance Criteria**:

- [ ] `MinimapButton.lua` ported from NelxRatedCurrency
- [ ] LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 embedded under `libs/`
- [ ] Minimap button registered on `PLAYER_LOGIN`
- [ ] Left-click toggles main frame
- [ ] Right-click opens Settings tab
- [ ] Minimap button position saved to `<NEWNAME_DB>.settings.minimapPosition`
- [ ] Button icon: use new addon icon if available, otherwise reuse NelxRatedCurrency icon
- [ ] Minimap button visibility toggle in Settings (show/hide)

---

## Story 11-6 — Currency Settings

**Goal**: Merge NelxRatedCurrency's settings into the main addon's Settings tab.

**Acceptance Criteria**:

- [ ] Settings tab gains a "Currency" section (below existing settings sections)
- [ ] Option: "Disable currency tooltip extension" (checkbox) — maps to `<NEWNAME_DB>.settings.disableTooltip`
- [ ] Option: "Show minimap button" (checkbox) — maps to `<NEWNAME_DB>.settings.showMinimapButton`
- [ ] Per-character hide toggle moved to Characters tab (or kept in Settings — TBD)
- [ ] Existing NelxRatedCurrency settings migrated in Story 11-2 migration block:
  - `NelxRatedCurrencyDB.settings.disableTooltip` → `<NEWNAME_DB>.settings.disableTooltip`
  - `NelxRatedCurrencyDB.settings.minimapPosition` → `<NEWNAME_DB>.settings.minimapPosition`
  - `NelxRatedCurrencyDB.settings.hiddenCharacters` → merge into `<NEWNAME_DB>.settings.hiddenCharacters`

---

## Story 11-7 — Retire NelxRatedCurrency

**Goal**: Communicate to users that NelxRatedCurrency is superseded and provide clean deprecation.

**Acceptance Criteria**:

- [ ] NelxRatedCurrency repo/project marked as archived or deprecated (human task)
- [ ] NelxRatedCurrency CurseForge project description updated to point to new addon (human task)
- [ ] Release notes for this version explain: currency features now in `<NEWNAME>`, NelxRatedCurrency can be removed, data migrates automatically

**Human TODOs**:
- [ ] Archive `Nelxbuilds/NelxRatedCurrency` GitHub repo
- [ ] Update NelxRatedCurrency CurseForge description: "Merged into `<NEWNAME>` as of vX.X. Install `<NEWNAME>` instead — your data migrates automatically."
- [ ] Remove NelxRatedCurrency from personal WoW AddOns folder after confirming migration worked

---

## Verification

1. Fresh install (no prior data): load addon → Currency tab visible → capture data in-game → tab populates
2. Existing NelxRated user: update → all ratings/challenges intact, currency tab empty until next login with game data
3. Existing NelxRatedCurrency user: update → Currency tab shows prior currency data immediately
4. Both addons previously installed: update → data merged, no duplicate characters, no data loss
5. Tooltip: hover Honor currency icon in character pane → per-char tooltip rows appear
6. Tooltip disabled: toggle setting → tooltip rows gone on next hover
7. Minimap button: left-click opens frame, right-click opens settings, position saves across reloads
8. ESC closes main frame (UISpecialFrames registration still correct after tab additions)
