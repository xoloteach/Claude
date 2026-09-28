# IRONLINE

A fast, first-person arena shooter built with **Godot 4.7.2** (Compatibility renderer) and playable in the browser.

**▶ Play the latest build:** <https://xoloteach.github.io/Claude/>

## Controls (placeholder)

| Action | Key |
|---|---|
| Move | W A S D |
| Look | Mouse (click the game to capture the pointer) |
| Fire / Aim | Left / Right mouse |
| Jump | Space |
| Sprint | Shift |
| Slide / Crouch | Ctrl / C |
| Reload | R |
| Pause | Esc |

## Build

```bash
tools/setup_godot.sh      # installs Godot 4.7.2 + web templates
tools/export_web.sh       # exports to build/web/
node tools/playtest.mjs smoke   # headless playtest, screenshots in tools/shots/
```

Every push to `main` is built and deployed to GitHub Pages. For details, see [docs/BUILDING.md](docs/BUILDING.md).
