# Jeweled (WoW Forever 1.60.1)

Development repository for the **Jeweled** match-3 addon. See [Jeweled/Docs/README.md](Jeweled/Docs/README.md) for player-facing documentation.

## Layout
- `Jeweled/` — Self-contained WoW Forever (`Interface: 16001`) addon folder (deploy or zip directly).
- `assets_src/` — Source images and 64px gem consistency contact sheet (`contact_sheet_64px.png`).
- `tools/` — Asset converter (`convert_assets.py`), sound synthesizer (`gen_sounds.py`), asset verifier (`verify_assets.py`), and Forever deploy script (`deploy.ps1`).
- `tests/` — Offline LuaJIT (Lua 5.1) test suites (`test_board.lua`, `test_comms.lua`).

## Quick Deploy & Verify (Windows)

```powershell
# Run syntax checks + board tests + multi-client comms sim + deploy to Forever AddOns
.\tools\deploy.ps1 -Verify

# Verify all 26 TGA textures & 16 OGG audio files
python tools/verify_assets.py
```
