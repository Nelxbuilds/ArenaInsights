# Changelog

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
