# system/ — WoW Integration and Peripheral Hooks

Integrates with WoW subsystems. Files are independent of each other. All defer via events — load order within system/ is not significant. All load after ui/ (MainFrame.lua must be loaded before WoWOptionsPanel + MinimapButton execute).

## Sync.lua
- Addon messaging over C_ChatInfo (prefix: "AI_SYNC")
- Chunked sends (200 chars/chunk), buffer timeout 30s, response timeout 5s
- AI.InitiateSync() — /ai sync; AI.SyncSelfTest() — /ai sync selftest
- After inbound merge: AI.RefreshOverlay() (nil-guarded)
- Lint D2: merge by account key, never overwrite (ArenaInsightsDB.characters = importedData is forbidden)

## Tooltip.lua
- TooltipDataProcessor hooks for Enum.TooltipDataType.Currency and .Item
- Appends per-character amounts for IDs in AI.TRACKED_CURRENCIES / AI.TRACKED_ITEMS
- Respects ArenaInsightsDB.settings.disableTooltip

## WoWOptionsPanel.lua
- Settings.RegisterCanvasLayoutCategory — WoW Settings > AddOns discovery page
- Static launch page only; calls AI.CreateAIButton + AI.ToggleMainFrame (deferred to ADDON_LOADED)
- Stores AI.wowOptionsCategoryID = category:GetID()

## MinimapButton.lua
- LibDataBroker + LibDBIcon-1.0; deferred to PLAYER_LOGIN
- Left-click: AI.ToggleMainFrame(); Right-click: AI.SelectTab("Settings")
- Position saved to ArenaInsightsDB.settings.minimapPosition
