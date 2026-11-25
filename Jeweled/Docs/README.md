# Jeweled — Match-3 Built for Flight Paths (WoW Forever)

**Jeweled** is a polished, custom-art match-3 puzzle game built exclusively for **World of Warcraft: Forever (1.60.1)** and designed for the dead time the game already hands you: flight paths.

Board a gryphon or wind rider, chase a new route record before you touch down, and pick up your half-finished board right where you left off on your next flight.

---

## Highlights

### Built for Flight Paths (and Polite by Default)
- **Asks First, Never Startles You**: On your first flight, Jeweled asks once whether you want it to auto-open on takeoff and auto-close on landing—and remembers your answer.
- **Flight-Aware Scoring**: Self-learns flight durations as you fly to display a real landing countdown (and an honest count-up timer on unseen routes), scores your run in **points per second (PPS)** so 40-second hops and 4-minute cross-continent flights compare fairly, and tracks a **per-route scorebook** with **"beat the landing" streaks**.
- **Automatic Save & Resume**: Your 8×8 board, special gems, score, and move count persist automatically across window closes, `/reload`, and full logouts.
- **Combat-Safe & Zero Idle Cost**: Immediately pauses and hides the moment you enter combat, never captures keys outside its window, and runs zero `OnUpdate` scripts while closed.

### 100% Custom Art, Animated Specials & Quiet Audio
- **Zero Blizzard Icons**: Every gem, background, effect, and icon is custom-made for Jeweled.
- **Classic 3D Faceted Crystals**: Six distinct colors *and* six distinct geometric silhouettes (square ruby, downward-triangle sapphire, octagon emerald, diamond topaz, pear amethyst, round brilliant diamond) for instant readability—including colorblind-friendly shape recognition.
- **Contour-Matched Elemental Specials**:
  - **4-Match → Line Clear**: Crackling directional lightning hugging the gem's edges with glowing `◄ ►` or `▲ ▼` indicators.
  - **L/T-Match → Flame Bomb (3×3)**: Live dancing flames flowing off the exact contour of the gem's cut.
  - **5-Match → Prismatic Crystal**: Upright crystal orb combining prismatic outer flames, crackling lightning, breathing halo, and gliding sheen—swap with any gem to zap every gem of that color off the board.
  - **Special Combos & Chain Reactions**: Combine any two specials (cross-clears, 5×5 mega blasts, full-board dual-prismatic clears) with color-matched crystal shard shatters, screen shake, and WoW-voiced cascade calls (`Combo!`, `Critical Match!`, `Multistrike!`, `Legendary!`).
- **Quiet by Design**: Ships with 16 custom CC0 `.ogg` audio effects normalized low so nothing blasts your ears while fishing or waiting on a pull, plus a one-click mute toggle.

### Live Polestar Theme Sync (Standalone-Ready)
- **Polestar-Native Look**: When **Polestar** is installed, Jeweled reads your active skin, color scheme, accent, and font live through Polestar's Skin API v2 and repaints automatically whenever you change looks.
- **Works Standalone**: Runs completely independently with bundled Night-scheme house tokens if you don't use Polestar.
- **Live Side-by-Side Settings**: Click **Options** right from the game window to switch between all three unlocked window backgrounds (**Night Sky**, **Deep Mine**, **Arcane Vault**), window size presets (`small` / `medium` / `large`), gem packs, effects, and screen shake while watching the board update live.

### Achievements, Unlockable Gem Packs & Serverless Leaderboards
- **18 Achievements**: Track milestones from your first match and ×5 cascades to route mastery, flight streaks, and leaderboard rankings—with clean, chat-free gold unlock toasts and unlockable gem packs (including the **Polestar** crystal pack).
- **Guild & Realm-Wide Leaderboards**: Compete with guildmates and other Jeweled players across your realm—zero external servers or websites required.
  - Five views: **Global**, **Points/Sec**, **This Week**, **Guild** (with classic faction PvP rank titles from *Private/Scout* up to *Grand Marshal/High Warlord*), and **Per-Route** standings.
  - Live online count, `Top` / `My Rank` jump buttons, live name search, and sortable columns.

---

## Controls & Slash Commands

- **Click-to-Swap** or **Drag-and-Release** (gems preview the swap while dragging and commit only when you let go).
- **Idle Auto-Hint**: Automatically pulses a quiet legal move hint if you haven't moved for 6 seconds, plus an on-demand **Hint** button and automatic reshuffle when no moves remain.
- **Minimap Button & Addon Compartment**: Left-click toggles the board, right-click opens quick actions, drag to reposition.

Primary command: `/jeweled` (short alias `/jwl`):

| Command | Action |
|---|---|
| `/jeweled` | Open or close the game window |
| `/jeweled new` | Start a new game |
| `/jeweled auto` | Toggle auto-open on flight paths |
| `/jeweled close` | Toggle auto-close on landing |
| `/jeweled sound` | Toggle sound effects |
| `/jeweled fx` | Toggle visual effects (`full` / `reduced`) |
| `/jeweled shake` | Toggle screen shake |
| `/jeweled minimap` | Show or hide the minimap button |
| `/jeweled board` (or `leaderboard`) | Open the Guild & Global leaderboard |
| `/jeweled network [on\|off]` | Join or leave the leaderboard sync network |
| `/jeweled ranks` | Print your global and guild standings in chat |
| `/jeweled scores` | Print your top flight route scorebook |
| `/jeweled size small\|medium\|large` | Resize the game window |
| `/jeweled reset [all]` | Reset window position (or all settings) |
| `/jeweled help` | List all commands |

---

## Leaderboard Network & Privacy

When leaderboard sharing is enabled (on by default), Jeweled syncs over a hidden addon channel (`jeweledsync`) plus `GUILD` and group fallbacks.
- **Shared**: Character GUID, character name, best score, best points-per-second, games played, flight route names for route bests, and timestamps.
- **Never shared**: BattleTag, account info, guild name (guild views are filtered strictly from your own guild roster), class, level, gear, live coordinates, or chat.
- Channel traffic is unencrypted and scores are player-shared (not server-verified), with client-side plausibility checks to filter out invalid data.
- **Total opt-out**: Run `/jeweled network off` or uncheck leaderboard sharing in Settings to leave the channel immediately and keep everything local.

---

*Jeweled is an unofficial, free fan addon for World of Warcraft: Forever and is not affiliated with, endorsed by, or connected to PopCap Games or Electronic Arts. Licensed under GPL-3.0-only.*
