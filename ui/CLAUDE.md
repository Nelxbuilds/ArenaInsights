# ui/ — Frame and Panel Rendering

All UI panels and the main window. No networking, no WoW Settings registration.

CRITICAL: ui/MainFrame.lua MUST be last in ui/ TOC order — it calls NXR.Create*Panel() for all tabs during CreateMainFrame(). Reordering will break the main window.

## MainFrame.lua — Shared widget API (available to all ui/ files)
- NXR.NXR_BACKDROP — backdrop table for BackdropTemplate frames
- NXR.COLORS.BG_BASE, NXR.COLORS.BG_RAISED — defined here (table started in core/Core.lua)
- NXR.CreateNXRButton(parent, text, width, height) → Button
- NXR.CreateNXRInput(parent, width, height) → EditBox
- NXR.ToggleMainFrame() — lazily creates main window on first call
- NXR.SelectTab(tabName) — show tab; opens main window if hidden
- Tab names: "Home", "Insights", "History", "Challenges", "Characters", "Currency", "Settings"

## Overlay.lua
- Independent floating frame — not a tab in the main window
- NXR.RefreshOverlay(), NXR.Overlay.Toggle(), NXR.Overlay.SetLocked(bool)
- Reads NXR.specData, NXR.classData (from core/Challenges.lua)
- Lint D1: opacity=0 → EnableMouse(false) on all interactive sub-frames

## Tab panel contract
Each panel file must:
- Expose NXR.Create*Panel(parentFrame) called by MainFrame.lua
- Expose NXR.Refresh*() for external refresh calls
- Parent all frames to the passed parentFrame argument

## Icon atlas rules
- classicon-<class> — flat circular (Overlay, ChallengesUI)
- Spec icons via GetSpecializationInfoForClassID() — 3D texture IDs
- FontStrings cannot parent textures — parent texture to containing frame, anchor to FontString
