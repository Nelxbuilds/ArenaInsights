# Bugs

| # | Description | File | Status |
|---|-------------|------|--------|
| 1 | `GetPersonalRatedInfo()` (deprecated per CLAUDE.md) still used for rating capture; migrate to `C_PvP.GetRatedBracketInfo(bracketIndex)` before it's removed in a patch. Verify field shape via `/wow-api-research` + in-game smoke test first. Stale comment at Insights.lua:1344 also claims the modern API is already used. | core/Core.lua:278 | Flagged |
