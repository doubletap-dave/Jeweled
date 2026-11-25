# Attribution & Licenses

## Code
- **Jeweled** — Copyright (C) 2026 Dave. Licensed under **GPL-3.0-only** (`LICENSE`).
- Designed exclusively for World of Warcraft: Forever 1.60.1 (`Interface: 16001`).
- Unofficial fan addon; not affiliated with PopCap Games or Electronic Arts.

## Custom Visual Assets (`Media/`)
- All 26 textures in `Media/` (`icon.tga`, `gems/azeroth/*.tga`, `gems/polestar/*.tga`, `gems/special/*.tga`, `backgrounds/*.tga`, `fx/*.tga`) were created specifically for Jeweled. Zero Blizzard or third-party game assets are included.

## Audio Assets (`Media/snd/*.ogg`)
- All 16 `.ogg` audio files (`swap`, `error`, `match1`–`match3`, `cascade4`–`cascade5`, `special_line`, `special_blast`, `special_prism`, `reshuffle`, `click`, `record`, `achievement`, `go`, `land`) were procedurally synthesized from scratch using `tools/gen_sounds.py` and are released under **CC0 1.0 Universal (Public Domain)**.

## Architectural Inspiration
- **Polestar** (GPL-3.0-only): Skin API v2 color/font token integration, nil-culling defaults pattern, and `Polestar_Arcade` hand-rolled minimap & 8-channel audio handle patterns.
- **TacoTip Extras** & **Guild Vendetta**: Hidden addon-sync channel hygiene, token-bucket flood control, deterministic responder ordering, and transparent privacy disclosure.
