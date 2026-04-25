# Epic 2 — Challenge System

Named rating challenges with multi-spec selection, optional class-level selection, multi-bracket support, and an "active challenge" concept that drives the overlay. Only one challenge is active at a time.

---

## Data Model

```lua
-- NelxRatedDB.challenges is an array of:
{
    id         = 1,                        -- unique numeric ID
    name       = "S1 Transmog",            -- user-defined name
    goalRating = 1800,                     -- target rating
    brackets   = {                         -- which brackets count (multi-select)
        [0] = true,                        -- 2v2
        [7] = true,                        -- Solo Shuffle
    },
    specs      = {                         -- set of selected specIDs
        [256] = true,                      -- Discipline Priest
        [257] = true,                      -- Holy Priest
        [258] = true,                      -- Shadow Priest
        [62]  = true,                      -- Arcane Mage
    },
    classes    = {                         -- set of selected classes, similar to specs, just with classIDs
    },
    active     = false,                    -- only one challenge has active=true
}
```

### Matching Logic

A character matches a spec row in a challenge when:

1. The character's class includes that spec (i.e., the spec belongs to the character's class)
2. The character has a rating > 0 in **any** of the challenge's selected `brackets`:
   - **Per-character brackets** (2v2, 3v3): check `character.brackets[bracketIndex]` — same rating regardless of spec
   - **Per-spec brackets** (Solo Shuffle, Blitz): check `character.specBrackets[specID][bracketIndex]` — rating is specific to each spec

Use `NXR.GetRating(charKey, bracketIndex, specID)` to look up the correct value for any bracket type.

When multiple characters match the same spec, the one with the **highest rating** (across any selected bracket) is displayed in the overlay.

### Class Challenges

"Class challenge" is a UI convenience, not a separate data type. When the user selects a class in the create/edit form, all specs of that class are toggled into the `specs` table. The underlying data model is always spec-based. This means:

- The overlay shows corresponding class icon, if a class got selected
- The user can deselect individual specs after selecting a class

---

## Story 2-1 — Challenge CRUD & Active Logic

**Goal**: Implement create, read, update, and delete for challenges, plus the active-challenge enforcement rule.

**Acceptance Criteria**:

- [x] `NXR.AddChallenge(data)` creates a challenge record with a unique auto-incrementing ID and appends it to `NelxRatedDB.challenges`
- [x] `NXR.RemoveChallenge(id)` removes a challenge by ID
- [x] `NXR.UpdateChallenge(id, data)` updates name, goalRating, brackets, and specs for an existing challenge
- [x] `NXR.SetActiveChallenge(id)` sets one challenge active and all others inactive; triggers `NXR.RefreshOverlay()` if it exists
- [x] `NXR.GetActiveChallenge()` returns the challenge record with `active = true`, or `nil`
- [x] Deleting the active challenge removes it and triggers overlay refresh (overlay hides); no other challenge is automatically promoted to active — the user must set a new one manually
- [x] On `ADDON_LOADED`, if challenges exist but none is active, the first one is set active
- [x] All mutations persist immediately to `NelxRatedDB` (it's a SavedVariable — WoW saves on logout/reload)

**Technical Hints**:

- Keep CRUD functions in `Core.lua` or a dedicated `Challenges.lua`
- Active enforcement: iterate all challenges, set `c.active = (c.id == targetID)`

---

## Story 2-2 — Challenge List UI

**Goal**: In the Challenges tab of Settings, show all challenges as a scrollable list with summary info and action buttons.

**Acceptance Criteria**:

- [x] Each challenge row shows: name, bracket names, goal rating, count of selected specs, and a small row of spec icon previews (first 5-6 icons)
- [x] Each row has a **Delete** button
- [x] Each row has an **Edit** button that opens the create/edit form pre-populated
- [x] Each row has a **Set Active** / **Active** toggle — the active challenge is visually highlighted
- [x] Setting a challenge active immediately refreshes the overlay
- [x] If no challenges exist, show an empty-state message: "No challenges yet. Create one below."
- [x] A "Create New Challenge" button at the top or bottom opens the create form

**Technical Hints**:

- Do NOT use `EasyMenu` or `UIDropDownMenuTemplate` — removed in 12.x
- For scroll lists, use `ScrollUtil` with a registered template or `SetElementExtentCalculator`
- Spec icon preview: for each spec in the challenge, `select(4, GetSpecializationInfoByID(specID))` returns the icon fileID

---

## Story 2-3 — Challenge Create / Edit Form

**Goal**: Build a form for creating and editing challenges. Includes name input, bracket multi-select, goal rating input, and a spec/class picker with class grouping and role sections.

**Acceptance Criteria**:

- [x] **Name input**: text EditBox for the challenge name
- [x] **Bracket selector**: four toggle buttons (2v2, 3v3, Blitz BG, Solo Shuffle) — multi-select, at least one required
- [x] **Goal rating input**: numeric EditBox
- [x] **Spec picker** organized by role (Healers, DPS, Tanks):
  - Each role section has **All** and **None** buttons to bulk-select/deselect
  - Each spec entry shows: checkbox, spec icon, spec name colored by class color
- [x] **Class picker**: clicking a class icon/button checks all specs of that class in the spec picker; clicking the same class again unchecks all of its specs
- [x] At least one spec/class must be selected to save
- [x] **Save / Create** button commits the challenge; **Cancel** returns to the list
- [x] When editing, the form is pre-populated with the existing challenge's data
- [x] After save, the challenge list refreshes and the overlay updates if the saved challenge is active
- [x] Validation feedback: show inline error messages for empty name, no specs, no brackets, invalid rating

**Technical Hints**:

- Build spec/class data at `ADDON_LOADED` using `GetNumClasses()`, `GetClassInfo(i)`, `GetNumSpecializationsForClassID(classID)`, `GetSpecializationInfoForClassID(classID, specIndex)`
- Role grouping: `GetSpecializationRoleByID(specID)` returns `"HEALER"`, `"DAMAGER"`, or `"TANK"`
- Class colors: `RAID_CLASS_COLORS[classFileName]` for coloring spec names
- Spec icons: `select(4, GetSpecializationInfoByID(specID))` returns the icon fileID
- Use `CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")` for checkboxes
- Bracket selection: four `CreateFrame("Button")` styled as toggles (highlighted when selected)
- The form can be a separate content frame that replaces the challenge list when open, with a back/cancel button

**Out of Scope**:

- Challenge ordering / drag-to-reorder (future enhancement)
