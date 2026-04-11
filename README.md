# NelxRated

Personal PvP rating challenge tracker for World of Warcraft (Midnight 12.x).

Track your arena and battleground ratings across multiple characters and accounts with customizable challenges and a movable in-game overlay.

## Features

- **Rating Tracking** — Automatically captures ratings and MMR for Solo Shuffle, 2v2, 3v3, and Blitz Battleground
- **Challenge System** — Set rating goals by spec or class, track progress across brackets
- **Overlay** — Movable frame showing color-coded progress toward your active challenge (orange at 80%, yellow at 90%, checkmark at 100%)
- **Multi-Character** — Track all your characters in one place, see your best-rated character per spec
- **Multi-Account** — Import/Export ratings between WoW accounts without overwriting existing data
- **Customizable** — Adjustable opacity (separate settings for arena/outside), lockable position, tooltips with character details

## Usage

| Command | Description |
|---------|-------------|
| `/nxr` | Open the main settings frame |
| `/nxr overlay` | Toggle overlay visibility |
| `/nxr lock` / `/nxr unlock` | Lock or unlock overlay position |
| `/nxr help` | Show all commands |

## Installation

### CurseForge

Download from [CurseForge](https://www.curseforge.com/wow/addons/nelxrated) and install with the CurseForge app.

### Manual

1. Download the latest release from [GitHub Releases](https://github.com/Nelxbuilds/NelxRated/releases)
2. Extract `NelxRated` into your `World of Warcraft/_midnight_/Interface/AddOns/` directory
3. Restart WoW or `/reload`

## Requirements

- World of Warcraft: Midnight (12.x)

## Built With

This addon is being developed with the assistance of [Claude Code](https://claude.ai/code) by Anthropic — from architecture and implementation to release automation.

## License

[MIT](LICENSE)
