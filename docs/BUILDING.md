# Building, playtesting & deploying IRONLINE

Engine: **Godot 4.7.2-stable**, renderer `gl_compatibility`, target **Web** (single-threaded, no GDExtension).

## 1. Setup

```bash
tools/setup_godot.sh          # idempotent; prints the godot binary path
```

- Downloads the Linux editor to `$GODOT_DIR` (default `~/.local/godot`, symlink `~/.local/godot/godot`).
- Downloads the 1.2 GB export-templates `.tpz`, extracts **only** `templates/web*.zip` + `version.txt` into
  `$GODOT_TEMPLATES` (default `~/.local/share/godot/export_templates/4.7.2.stable/`), then deletes the `.tpz`.
- Skips anything already installed. Override the version with `GODOT_VERSION`.

## 2. Export

```bash
tools/export_web.sh           # release; add --debug for a debug export
```

Runs `godot --headless --import`, then `godot --headless --export-release "Web" build/web/index.html`.
Godot often exits 0 even when scripts fail to parse, so the script also scans the logs (`build/logs/import.log` and
`build/logs/export.log`) for `ERROR` / `SCRIPT ERROR` / `Parse Error` lines and fails if it finds any. It then checks
that `index.{html,js,wasm,pck}` exist, adds `build/web/.nojekyll`, and prints the pck size. Godot binary lookup order:
`$GODOT_BIN`, then `godot` on `PATH`, then `~/.local/godot/godot`.

Preset `Web` (`export_presets.cfg`): threads **off** (GitHub Pages can't send COOP/COEP headers), extensions off,
VRAM compression for desktop (S3TC/BPTC) and mobile (ETC2/ASTC), adaptive canvas resize, focus canvas on start,
PWA off, default shell with a dark loading screen injected via `html/head_include`. `tools/`, `docs/` and `build/`
are excluded from the pck. `docs/`, `build/`, `tools/shots/` and `tools/node_modules/` contain a `.gdignore` so
the editor doesn't import them.

## 3. Playtest (headless Chromium)

```bash
npm install --prefix tools                        # once; or use a global playwright (/opt/tools is auto-detected)
npx --prefix tools playwright install chromium    # once
node tools/playtest.mjs smoke                     # or: combat, or a path to any scenario .json
```

Flags: `--timeout ms` (scenario budget, default 300000), `--boot-timeout ms` (default 180000), `--build dir`,
`--port n`, `--headed`, `--allow-errors` (don't fail on Godot `ERROR` lines).

The harness serves `build/web` over a small built-in HTTP server (with the correct MIME types, including
`application/wasm`), launches Chromium with SwiftShader WebGL2 at a 1600×900 viewport, and waits for the
`Godot Engine v…` console line and for the loading overlay to be removed. It then runs the scenario.

- Output: `tools/shots/<scenario>/*.png`, `tools/shots/<scenario>/summary.json`, and `tools/shots/console.log`
  (the full browser console).
- **Fails (exit 1)** on an uncaught JS error, a page crash, a boot timeout, or any Godot `ERROR:` /
  `SCRIPT ERROR:` console line.
- Samples FPS at every screenshot. It reads `ironline_state().fps` from the game and also runs its own
  `requestAnimationFrame` counter.

### Scenario format (`tools/scenarios/*.json`)

A scenario is either a JSON array of steps or `{"steps": [...]}`:

| step | effect |
|---|---|
| `{"wait": ms}` | sleep |
| `{"click": [x, y]}` | left click (optional `"button"`) |
| `{"key": "KeyW", "down": true}` / `{"key": "KeyW", "up": true}` | hold / release a key (DOM `code` names) |
| `{"press": "KeyR"}` | tap a key |
| `{"mouse_move": [dx, dy], "steps": n}` | relative mouse move |
| `{"mouse_to": [x, y]}` | absolute mouse move |
| `{"mouse_down": "left"}` / `{"mouse_up": "left"}` | mouse button |
| `{"screenshot": "name"}` | save `tools/shots/<scenario>/name.png` and sample FPS |
| `{"eval": "js"}` | evaluate JS in the page and log the result |
| `{"godot": "cmd"}` | call `window.ironline_cmd(cmd)` (logs a warning if it's missing). After `state`, logs the game state |
| `{"wait_for": "js expr", "timeout": ms}` | wait until the expression is truthy |
| `{"fps": "label"}` / `{"log": "text"}` | sample FPS / write a note to the log |

Pointer lock doesn't work headless: Godot reads mouse motion from `movementX/Y` only while the pointer is locked,
so drive the camera with `godot` commands instead.

## 4. JS bridge protocol (implemented by the game)

The game (web builds only, `OS.has_feature("web")`) exposes two globals:

- `window.ironline_cmd(cmd: string)` — a `JavaScriptBridge.create_callback`. It runs synchronously, and its return
  value is ignored.
- `window.ironline_state()` — returns the game state as an object. A Godot callback can't return a value to JS, so
  the game keeps `window.ironline_state_json` (a JSON string) up to date and defines
  `ironline_state = () => JSON.parse(window.ironline_state_json)` via `JavaScriptBridge.eval`.

  The harness accepts any of these: a function returning an object or string, a plain property, or only
  `ironline_state_json`.

Commands (space-separated):

| command | meaning |
|---|---|
| `look <dx> <dy>` | rotate the camera as if the mouse moved dx,dy pixels (same sensitivity as mouse) |
| `move fwd\|back\|left\|right on\|off` | hold / release a movement direction |
| `fire on\|off` | hold / release primary fire |
| `ads on\|off` | hold / release aim-down-sights |
| `key <action>` | tap an InputMap action (e.g. `reload`, `jump`, `sprint`, `slide`, `crouch`, `pause`) |
| `teleport <x> <y> <z>` | move the player to a world position |
| `state` | refresh `window.ironline_state_json` immediately |

State JSON should contain at least `{"fps": number}`. Suggested extra fields: `scene`, `pos`, `yaw`, `pitch`,
`health`, `ammo`, `weapon`, `enemies`.

Minimal reference implementation (tested with this harness):

```gdscript
var _cb  # keep a reference, or the callback gets freed

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_cb = JavaScriptBridge.create_callback(_on_js_cmd)
	JavaScriptBridge.get_interface("window").ironline_cmd = _cb
	JavaScriptBridge.eval("window.ironline_state = () => JSON.parse(window.ironline_state_json || 'null');", true)

func _on_js_cmd(args: Array) -> void:
	var p := str(args[0]).split(" ", false)
	match p[0]:
		"look": pass   # feed Vector2(float(p[1]), float(p[2])) into the camera
		"state": pass
	_publish_state()

func _publish_state() -> void:  # also call this every ~0.25 s from _process
	var s := {"fps": Engine.get_frames_per_second()}
	JavaScriptBridge.get_interface("window").ironline_state_json = JSON.stringify(s)
```

## 5. Deploy

`.github/workflows/pages.yml` runs on every push to `main` (and on `workflow_dispatch`):

1. Restores the cached Godot editor and web templates (cache key `godot-<version>-web-v1`).
2. Runs `tools/setup_godot.sh` and `tools/export_web.sh`.
3. Uploads `build/web` with `upload-pages-artifact`, then publishes it with `deploy-pages`.

A parallel `smoke` job runs `playtest.mjs smoke` against the same artifact and uploads screenshots as the
`playtest-shots` artifact. It is informational and does not block the deploy.

Pages is configured with `build_type=workflow`. Live build: <https://xoloteach.github.io/Claude/>
