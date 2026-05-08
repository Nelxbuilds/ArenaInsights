# ArenaInsights

Personal PvP rating challenge tracker for World of Warcraft (Midnight 12.x).

Track your arena and battleground ratings across multiple characters and accounts with customizable challenges, a movable in-game overlay, a rating history graph, and per-match insights.

## Features

- **Rating Tracking** — Automatically captures ratings and MMR for Solo Shuffle, 2v2, 3v3, and Blitz Battleground
- **Challenge System** — Set rating goals by spec or class, track progress across brackets; first challenge auto-activates
- **Overlay** — Movable frame showing challenge title, color-coded spec rows (orange at 80%, yellow at 90%, checkmark at 100%), opt-in progress bar, manual spec/class completion marking, multi-column layout, role grouping, and gold indicator for your currently logged-in spec
- **Match Insights** — Per-match history log with outcome colors, MMR delta, spec icons, bracket filter toggles (persisted), stats bar (win rate, W/D/L), sortable columns, expandable rows with full team breakdown, and stats tooltips
- **Rating History** — Graph visualization of rating progression per character/spec/bracket with goal line overlay and class color option
- **Multi-Character** — Track all your characters in one place, see your best-rated character per spec
- **Party Sync** — One-button bidirectional sync with other ArenaInsights accounts in your party; merges character rating data without overwriting existing entries
- **Multi-Account** — Import/Export characters, challenges, settings, and ratings between WoW accounts without overwriting existing data
- **Currency Tracking** — Per-character PvP currency ledger (Honor, Conquest, Bloody Tokens, PvP items) with visibility toggles and horizontal scroll
- **Minimap Button** — Quick-access minimap icon to open the main frame
- **Customizable** — Adjustable opacity (separate settings for arena/outside), scale slider, lockable position, hide unrated rows, tooltips with character details; discoverable via WoW's built-in addon settings panel

## Usage

| Command | Description |
|---------|-------------|
| `/ai` | Open the main frame |
| `/ai overlay` | Toggle overlay visibility |
| `/ai lock` / `/ai unlock` | Lock or unlock overlay position |
| `/ai sync` | Sync character data with other ArenaInsights accounts in party |
| `/ai help` | Show all commands |

## Main Frame Tabs

| Tab | Description |
|-----|-------------|
| Insights | Per-match history with stats bar, bracket filters, sortable columns, and team details |
| History | Rating graph per character/spec/bracket with filters |
| Challenges | Create, edit, and activate rating challenges |
| Characters | View all tracked characters and their ratings |
| Currency | PvP currency and item ledger across characters (Honor, Conquest, etc.) |
| Settings | Opacity, scale, chart color, overlay options |
| How-To | In-game usage guide and tips |
| Import/Export | Share rating data across WoW accounts |

## Installation

### CurseForge

Download from [CurseForge](https://www.curseforge.com/wow/addons/arena-insights) and install with the CurseForge app.

### Manual

1. Download the latest release from [GitHub Releases](https://github.com/Nelxbuilds/ArenaInsights/releases)
2. Extract `ArenaInsights` into your `World of Warcraft/_retail_/Interface/AddOns/` directory
3. Restart WoW or `/reload`

## Requirements

- World of Warcraft: Midnight (12.x)

## Built With

Built through AI-assisted development: Nelx designed the features and directed the work; [Claude Code](https://claude.ai/code) (Anthropic) implemented the code, architecture, and release automation.

## License

[MIT](LICENSE)
