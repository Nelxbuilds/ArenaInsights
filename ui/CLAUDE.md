# ui/ — Frame and Panel Rendering

All UI panels and the main window. No networking, no WoW Settings registration.

CRITICAL: ui/MainFrame.lua MUST be last in ui/ TOC order — it calls AI.Create*Panel() for all tabs during CreateMainFrame(). Reordering will break the main window.

## MainFrame.lua — Shared widget API (available to all ui/ files)
- AI.AI_BACKDROP — backdrop table for BackdropTemplate frames
- AI.COLORS.BG_BASE, AI.COLORS.BG_RAISED — defined here (table started in core/Core.lua)
- AI.CreateAIButton(parent, text, width, height) → Button
- AI.CreateAIInput(parent, width, height) → EditBox
- AI.ToggleMainFrame() — lazily creates main window on first call
- AI.SelectTab(tabName) — show tab; opens main window if hidden
- Tab names: "Insights", "History", "Challenges", "Characters", "Currency", "Settings", "How-To"

## Overlay.lua
- Independent floating frame — not a tab in the main window
- AI.RefreshOverlay(), AI.Overlay.Toggle(), AI.Overlay.SetLocked(bool)
- Reads AI.specData, AI.classData (from core/Challenges.lua)
- Lint D1: opacity=0 → EnableMouse(false) on all interactive sub-frames

## SessionUI.lua
- Session summary popup — not a tab; shows after leaving a PvP instance when a match was recorded
- AI.ShowSessionSummary(charKey) — manual trigger, charKey nil = all chars (`/run AI.ShowSessionSummary()` to test)
- AI.OnMatchRecorded(rec) — called nil-guarded by core/Insights.lua after each match write; defers popup while inside arena/BG (PLAYER_ENTERING_WORLD releases it)
- Reads AI.GetLatestSession() from core/Insights.lua; SS scores shown as rounds, other brackets as match W-L
- Setting: sessionPopupEnabled

## QueueOverlay.lua
- Independent floating frame; auto-shows while in any PvP queue, hides when none
- Events: UPDATE_BATTLEFIELD_STATUS, PLAYER_ENTERING_WORLD; APIs GetBattlefieldStatus/GetBattlefieldTimeWaited (pcall + secret-value guarded, unverified in Midnight)
- AI.QueueOverlay.Refresh() — re-evaluates queues + enabled setting (called by SettingsUI toggle)
- Drag position saved to settings.queueOverlayPos; setting: queueOverlayEnabled

## Tab panel contract
Each panel file must:
- Expose AI.Create*Panel(parentFrame) called by MainFrame.lua
- Expose AI.Refresh*() for external refresh calls
- Parent all frames to the passed parentFrame argument

## Icon atlas rules
- classicon-<class> — flat circular (Overlay, ChallengesUI)
- Spec icons via GetSpecializationInfoForClassID() — 3D texture IDs
- FontStrings cannot parent textures — parent texture to containing frame, anchor to FontString
