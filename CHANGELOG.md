# Changelog

## [2.2.0] -- 2026-05-09

### Added
- Insights stats bar with inline W/L counts and per-round Solo Shuffle winrate

### Fixed
- Center Win/Loss labels and values within bracket half-panes in insights

## [2.1.0] -- 2026-05-09

### Added
- Insights: bracket filter toggles replacing outcome filter, with stats bar (win rate, W/D/L)
- Insights: expandable rows with all-player stats and full team breakdown
- Insights: sortable detail columns and compact stats chips
- Insights: win rate % on title row, W/D/L on second row
- Insights: custom stats tooltips
- Insights: persist bracket filter selection across sessions
- How-To tab in main frame

### Fixed
- Insights: guard nil entries in player sort comparator
- Insights: fix sort comparator operator precedence
- Insights: normalize -0.0 to "0" in FormatStat
- Insights: SS icon anchor, remove detail background overlay
- Insights: drop W/D/L letter suffixes (color conveys outcome)
- Insights: remove undefined DETAIL_H_STATS causing SetHeight nil crash
- Insights: replace goto/label with if-block for Lua 5.1 compatibility
- Insights: prevWins taint guard in stats bar

## [2.0.0] -- 2026-05-08

### Added
- Rename addon NelxRated → ArenaInsights

### Fixed
- Add migration popup for NelxRated data and fix minimap icon path
- NelxRatedDB data not carried over to ArenaInsightsDB
- Show popup every login until dismissed or migrated
- Change button wording and fix reload behavior
- Store dismissal flag at top-level ArenaInsightsDB key
- Cache dismissal flag into AI namespace to survive reload

## [1.7.4] -- 2026-05-08

### Fixed
- Tighten middle columns in Insights to prevent team icons clipping
- Abbreviate bracket names in Insights rows (Solo Shuffle -> Shuffle, Blitz BG -> Blitz)

## [1.7.3] -- 2026-05-06

### Fixed
- Insights: use PVP_MATCH_COMPLETE winner arg for correct 2v2/3v3 outcome detection

## [1.7.2] -- 2026-05-04

### Fixed
- Insights: match rating column showed previous match's post-rating instead of current. Scoreboard `info.rating` returns stale data in Midnight 12.x; now overridden with authoritative DB rating from `C_PvP.GetRatedBracketInfo`.

## [1.7.1] -- 2026-05-04

### Fixed
- Insights: bracket misdetected as 2v2 when playing 3v3; first-of-season and zero-rating-change matches showed "Unknown"
- Insights: losses with 0 ratingChange recorded as "draw"; now derived from authoritative scoreboard signals
- Insights: MMR shown as "?" for arena 2v2/3v3; falls back to GetBattlefieldTeamInfo team MMR when per-player prematchMMR unavailable
- Insights: ally/enemy specs and team display missing; talentSpec is a localized name string, now resolved to specID via classToken+name lookup
- Insights: bare names without realm; player's realm appended for charKey resolution

### Added
- Insights: per-player charKey (name-realm) captured for each ally/enemy in match record (`enemyPlayers[]` / `allyPlayers[]` arrays alongside existing `enemySpecs` / `allySpecs`)

## [1.7.0] -- 2026-05-04

### Added
- Match Insights panel: per-match history log with outcome colors, MMR column, spec icons, character filter, team column
- SS per-round tracking and outcome detection
- NXR.DebugInsights() for isolated insights logging
- NXR.PurgeCorruptMatches() for debug cleanup

### Fixed
- Scroll background uses opaque texture (BackdropTemplate alpha didn't cover)
- SS round state numbers corrected for Midnight 12.x
- SS rounds preserved across inter-round zones and zone-in
- Score lookup and SS round tracking
- Bracket detection uses DB-based approach instead of seasonPlayed API snapshot
- Insights deferred to PVP_RATED_STATS_UPDATE for bracket detection and finalization
- C_PvP.GetRatedBracketInfo guarded in restricted PvP context
- History tab selects most-played spec on auto-select

### Changed
- Insights UI overhauled: char filter, team column, white bg fixed, ASCII-safe text
- NXR namespace exposed as global for /run access

## [1.6.0] -- 2026-04-27

### Added
- Currency tab: PvP currency and item ledger (Honor, Conquest, Bloody Tokens, Mark/Flask/Medal of Honor) with per-column visibility toggles and horizontal scroll
- Minimap button for quick access to main frame

### Fixed
- Currency tab: invalid sort comparator causing nil crash
- Currency tab: nil scrollChild guard during frame construction
- Currency tab: column widths adjusted to fit labels

### Changed
- Lua files reorganized into core/, ui/, system/ subdirectories

## [1.5.0] -- 2026-04-26

### Added
- Party Sync: bidirectional one-button sync of character rating data with other NelxRated accounts in party via `/nxr sync` and Settings tab button; merges using `updatedAt` timestamp, never overwrites

## [1.4.0] -- 2026-04-26

### Added
- Overlay: challenge title display above spec rows
- Overlay: opt-in progress bar above challenge rows
- Overlay: manual spec/class completion marking
- WoW Settings panel entry for addon discovery

### Fixed
- Settings tab order, overlay layout, progress bar manual completion interaction

## [1.3.2] -- 2026-04-25

### Fixed
- Import/Export: MergeCharacters now merges brackets, specBrackets, and ratingHistory into existing characters instead of skipping them; fixes other-spec data being lost on cross-account import
- Import/Export: MergeChallenges respects deleted challenge tombstones so user-deleted challenges no longer resurrect on re-import
- Import/Export: RemoveChallenge records tombstones; AddChallenge respects explicit active flag to prevent imported challenges from silently activating

## [1.3.1] -- 2026-04-25

### Fixed
- Overlay rows for old specs no longer disappear after respeccing; historical specBrackets data is now matched even when the character has switched to a different spec
- Characters tab now shows per-spec ratings for all specs with data, not only the currently active spec

## [1.3.0] -- 2026-04-24

### Added
- New setting "Hide unrated rows" — hides specs/classes with no rating data from the overlay; overlay auto-hides if all rows are filtered

## [1.2.0] -- 2026-04-24

### Added
- Overlay polish: multi-column layout, checkmark replaces rating text at 100%, wider rating padding, current-character indicator
- Full data export/import covering characters, challenges, and settings

### Fixed
- Disable role grouping for class challenges
- Checkmark centering, settings scroll, role columns, melee/ranged split
- Typo in README

## [1.1.0] -- 2026-04-19

### Changed
- History tab improvements: race/gender icons in character dropdown, class-colored and class-ordered entries, scrollable dropdown, auto-bracket selection on character change
- History tab bugfixes: goal label background, dropdown style unification, z-order fixes, dropdown rendering above graph

## [1.0.1] -- 2026-04-17

### Fixed
- Interface info display corrections
- History tracking and persistence issues
- History visualization improvements and cleanup

## [1.0.0] -- 2026-04-12

### Changed
- Major version bump from 0.1.0 — all six epics complete

### Completed
- Epic 1: Core Tracking — arena rating and MMR capture for all brackets
- Epic 2: Challenge System — multi-spec, multi-bracket challenge CRUD
- Epic 3: Settings UI — full settings panel with all configuration options
- Epic 4: Overlay — movable overlay with color-coded progress and tooltips
- Epic 5: Home Screen — dashboard with summary stats
- Epic 6: Rating History — historical rating tracking and UI

## [0.1.0] — Initial Release

### Added
- Arena rating and MMR tracking for Solo Shuffle, 2v2, 3v3, and Blitz BG
- Personal challenge system — set rating goals by spec or class
- Movable overlay showing spec/class icons with color-coded progress (80% orange, 90% yellow, 100% checkmark)
- Hover tooltips showing character name and current rating
- Settings panel with Challenges, Characters, Settings, and Import/Export tabs
- Per-account character tracking with name, realm, and account metadata
- Cross-account Import/Export to share ratings between WoW accounts without overwriting each account's own data
- Overlay opacity control for inside and outside arena (tooltips auto-disabled at 0 opacity)
