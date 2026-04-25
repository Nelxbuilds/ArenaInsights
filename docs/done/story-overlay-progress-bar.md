# Story — Overlay Progress Bar

Opt-in progress bar above overlay rows showing discrete challenge completion: how many specs/classes have hit their goal out of total.

**Depends on**: Epic 4 (overlay), Epic 3 (settings), Epic 2 (challenge system)

---

## Goal

Users want a quick at-a-glance completion summary without counting individual rows. A progress bar on top of the overlay fills discretely as specs/classes reach `goalRating`, with a counter `X / Y` and percentage inside.

---

## Completion Definition

- **Total** = all specs/classes in active challenge — not affected by `hideZeroRatingRows`
- **Completed** = entries where best-character rating >= `challenge.goalRating`
- **Fill** = `completed / total` (discrete — jumps per spec, not smooth aggregate)
- No active challenge → bar hidden; total = 0 → bar hidden

### hideZeroRatingRows interaction

0-rated specs are not completed → contribute 0 to numerator, 1 to denominator. The denominator always equals the full spec/class count of the challenge.

---

## Layout

```
┌──────────────────────────────────────────┐  ← overlayFrame top
│ ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░  3 / 8  (37%)     │  ← progress bar (BAR_HEIGHT = 14px)
│                                          │  ← BAR_PADDING = 4px gap
│ [icon] 1847    [icon] 2100 ✓            │  ← rows (unchanged)
│ ...                                      │
└──────────────────────────────────────────┘
```

- Bar spans full content width (frame width minus `PADDING * 2` on each side)
- Fill color: `CRIMSON_BRIGHT` (`{0.88, 0.22, 0.18}`) for filled portion; dark crimson `{0.10, 0.04, 0.04}` bg
- Text: `"X / Y  (pct%)"` centered inside bar, `GameFontNormalTiny`, white

---

## Acceptance Criteria

- [ ] Setting **"Show progress bar on overlay"** exists in Settings tab, default **off**
- [ ] When off: overlay unchanged, no bar visible, rows at normal positions
- [ ] When on + active spec challenge: bar appears above rows, text shows `"X / Y  (pct%)"`
- [ ] When on + active class challenge: same behavior
- [ ] Bar fill is discrete — jumps when a spec/class crosses `goalRating`, not a smooth average
- [ ] `0 / N`: bar background only (empty fill), text shows `"0 / N  (0%)"`
- [ ] `N / N`: bar fully filled crimson, text shows `"N / N  (100%)"`
- [ ] `hideZeroRatingRows` toggled on: denominator unchanged in bar text (still = total specs in challenge)
- [ ] No active challenge: bar hidden, rows at normal y-positions
- [ ] Overlay frame height accounts for bar when shown — no row clipping
- [ ] Overlay frame shrinks back to normal when bar hidden or setting disabled
- [ ] Drag/reposition overlay works normally with bar present
- [ ] Opacity = 0: bar hidden with rest of overlay (follows existing opacity guard)

---

## Technical Hints

### New constants (Overlay.lua, near top)
```lua
local BAR_HEIGHT  = 14
local BAR_PADDING = 4   -- gap between bar bottom and first row top
```

### New setting (Core.lua SETTINGS_DEFAULTS)
```lua
showOverlayProgressBar = false,
```

### New local function: CalcChallengeProgress(challenge) — Overlay.lua
Iterate `challenge.specs` or `challenge.classes`. For each entry call existing
`NXR.FindMatchingCharactersForSpec` / `NXR.FindMatchingCharactersForClass`.
Check `matches[1].rating >= challenge.goalRating`. Return `completed, total`.

### Progress bar sub-frames — CreateOverlayFrame()
Create after overlayFrame. Frames: `pb` (Frame), `pbBg` (BACKGROUND texture, full),
`pbFill` (BORDER texture, left-anchored, width updated per refresh), `pbText` (FontString, centered).
Store as `overlayFrame.progressBar`, `.progressBarFill`, `.progressBarText`. Start hidden.

### Row y-offset shift — RefreshOverlay()
At top of `RefreshOverlay()`, compute:
```lua
local barOffset = 0
if NelxRatedDB.settings.showOverlayProgressBar and NXR.GetActiveChallenge() then
    local _, total = CalcChallengeProgress(NXR.GetActiveChallenge())
    if total > 0 then barOffset = BAR_HEIGHT + BAR_PADDING end
end
```
Add `barOffset` to all row `yOff` calculations and to `totalHeight` before `SetSize`.

### RefreshProgressBar(contentWidth) — called after SetSize
Position bar with `TOPLEFT` anchor. Set `pb:SetWidth(contentWidth)`.
Compute `fillW = floor(contentWidth * completed / total)`. Set fill width (`max(fillW, 1)`).
Set text string. Show or hide pb based on conditions.

### Settings UI — SettingsUI.lua
Add checkbox after `hideZeroRatingRows` block (~line 212). Same pattern:
`UICheckButtonTemplate`, label `"Show progress bar on overlay"`, OnClick saves setting + calls `NXR.RefreshOverlay()`.
Initialize from `NelxRatedDB.settings.showOverlayProgressBar or false`.

---

## Files to Modify

| File | Change |
|------|--------|
| `Core.lua` | `showOverlayProgressBar = false` in `SETTINGS_DEFAULTS` |
| `Overlay.lua` | `BAR_HEIGHT`/`BAR_PADDING` constants, `CalcChallengeProgress()`, `RefreshProgressBar()`, sub-frames in `CreateOverlayFrame()`, `barOffset` + `RefreshProgressBar()` call in `RefreshOverlay()` |
| `SettingsUI.lua` | Checkbox after `hideZeroRatingRows` block |
