# Jeweled — Leaderboard Network Privacy Disclosure

Jeweled includes an optional serverless guild and realm-wide leaderboard powered entirely by World of Warcraft's built-in addon message API (`C_ChatInfo.SendAddonMessage`). There is no external server, website, or account.

## What Leaves Your Client
When leaderboard sharing is enabled (`network = true`, on by default), Jeweled joins the hidden custom channel `jeweledsync` (filtered out of your chat frames) and also exchanges records over `GUILD` (when guilded) and `PARTY`/`RAID` fallbacks. Messages contain **only**:
- Your character GUID (`UnitGUID("player")`)
- Your character name (`UnitName("player")`)
- Your best score, best flight points-per-second (PPS), and games played
- Flight route names for route bests (e.g. `Stormwind->Ironforge`)
- Timestamps, move counts, and flight durations for submitted bests

## What Is NEVER Sent
- BattleTag or Battle.net account details
- Guild name (guild leaderboard views are filtered strictly using the receiver's own guild roster)
- Character class, spec, level, gear, gold, or inventory
- Live character coordinates or zone location outside flight route names
- Chat messages or information about other players (Jeweled only broadcasts your own records, plus query relays of records already shared on the channel)

## Public Channel Notice
The sync channel name (`jeweledsync`), password, and message format are open in the addon source files and are **not encrypted**. Any addon or player joining the channel can read and write messages on it. Leaderboard entries are best-effort community scores and are not verified by a central server.

## How to Opt Out Completely
Run `/jeweled network off` (or uncheck **Share scores on realm & guild leaderboard network** under **Options > AddOns > Jeweled**). Jeweled will immediately leave `jeweledsync`, stop all outbound addon messages, and display only your local scores.
