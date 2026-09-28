extends Node
## Global game state, settings, input map (keyboard/mouse + gamepad + touch), and web test bridge.

signal settings_changed
signal score_changed(score: int)
signal kill_registered(info: Dictionary)
signal wave_changed(wave: int)
signal game_over(stats: Dictionary)
signal hud_message(text: String, kind: String)
signal hit_confirmed(kind: String, damage: float)   # kind: "hit", "head", "kill", "headkill", "armor"
signal player_hurt(from_pos: Vector3, amount: float)
signal ammo_changed(ammo: int, reserve: int, mag: int)
signal weapon_changed(def: Dictionary)
signal enemies_remaining(count: int)

const SETTINGS_PATH := "user://settings.cfg"

# Physics layers (bit values)
const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_HITBOX := 8
const L_PROPS := 16

var settings := {
	"sensitivity": 1.0,        # mouse, multiplier
	"ads_sensitivity": 0.85,
	"pad_sensitivity": 1.0,
	"touch_sensitivity": 1.0,
	"fov": 90.0,
	"invert_y": false,
	"master_volume": 0.9,
	"sfx_volume": 1.0,
	"music_volume": 0.6,
	"quality": 2,              # 0 low, 1 medium, 2 high
	"show_fps": false,
	"touch_controls": -1,      # -1 auto, 0 off, 1 on
	"aim_assist": true,
}

var score := 0
var kills := 0
var headshots := 0
var shots_fired := 0
var shots_hit := 0
var wave := 0
var in_game := false
var paused := false
var time_alive := 0.0

## Look input injected by touch controls / web bridge (pixels, consumed by the player each frame).
var injected_look := Vector2.ZERO
## Last input device family used: "kbm", "pad", "touch".
var input_mode := "kbm"

var player: Node = null
var world: Node = null

var _js_cb = null
var _js_window = null
var _state_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	_setup_web_bridge()


# ---------------------------------------------------------------- input map
func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mb(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e

func _jb(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e

func _ja(axis: JoyAxis, dir: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = dir
	return e

func _add(action: String, events: Array, deadzone := 0.2) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	for e in events:
		InputMap.action_add_event(action, e)

func _setup_input() -> void:
	_add("move_forward", [_key(KEY_W), _key(KEY_UP), _ja(JOY_AXIS_LEFT_Y, -1.0)], 0.15)
	_add("move_back", [_key(KEY_S), _key(KEY_DOWN), _ja(JOY_AXIS_LEFT_Y, 1.0)], 0.15)
	_add("move_left", [_key(KEY_A), _key(KEY_LEFT), _ja(JOY_AXIS_LEFT_X, -1.0)], 0.15)
	_add("move_right", [_key(KEY_D), _key(KEY_RIGHT), _ja(JOY_AXIS_LEFT_X, 1.0)], 0.15)
	_add("look_left", [_ja(JOY_AXIS_RIGHT_X, -1.0)], 0.12)
	_add("look_right", [_ja(JOY_AXIS_RIGHT_X, 1.0)], 0.12)
	_add("look_up", [_ja(JOY_AXIS_RIGHT_Y, -1.0)], 0.12)
	_add("look_down", [_ja(JOY_AXIS_RIGHT_Y, 1.0)], 0.12)
	_add("jump", [_key(KEY_SPACE), _jb(JOY_BUTTON_A)])
	_add("crouch", [_key(KEY_C), _key(KEY_CTRL), _jb(JOY_BUTTON_B)])
	_add("sprint", [_key(KEY_SHIFT), _jb(JOY_BUTTON_LEFT_STICK)])
	_add("fire", [_mb(MOUSE_BUTTON_LEFT), _ja(JOY_AXIS_TRIGGER_RIGHT, 1.0)], 0.3)
	_add("ads", [_mb(MOUSE_BUTTON_RIGHT), _ja(JOY_AXIS_TRIGGER_LEFT, 1.0)], 0.3)
	_add("reload", [_key(KEY_R), _jb(JOY_BUTTON_X)])
	_add("next_weapon", [_key(KEY_Q), _mb(MOUSE_BUTTON_WHEEL_DOWN), _jb(JOY_BUTTON_Y)])
	_add("prev_weapon", [_mb(MOUSE_BUTTON_WHEEL_UP)])
	_add("weapon_1", [_key(KEY_1)])
	_add("weapon_2", [_key(KEY_2)])
	_add("weapon_3", [_key(KEY_3)])
	_add("weapon_4", [_key(KEY_4)])
	_add("weapon_5", [_key(KEY_5)])
	_add("grenade", [_key(KEY_G), _jb(JOY_BUTTON_RIGHT_SHOULDER)])
	_add("melee", [_key(KEY_V), _jb(JOY_BUTTON_RIGHT_STICK)])
	_add("hold_breath", [_key(KEY_SHIFT), _jb(JOY_BUTTON_LEFT_STICK)])
	_add("pause", [_key(KEY_ESCAPE), _key(KEY_P), _jb(JOY_BUTTON_START)])
	_add("scoreboard", [_key(KEY_TAB), _jb(JOY_BUTTON_BACK)])
	_add("ui_accept_pad", [_jb(JOY_BUTTON_A)])


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		input_mode = "pad"
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		input_mode = "touch"
	elif event is InputEventKey or (event is InputEventMouseMotion and event.relative.length() > 2.0) or event is InputEventMouseButton:
		if not (event is InputEventMouseButton and DisplayServer.is_touchscreen_available() and input_mode == "touch"):
			input_mode = "kbm"


func wants_touch_controls() -> bool:
	var t: int = settings.touch_controls
	if t == 0:
		return false
	if t == 1:
		return true
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


# ---------------------------------------------------------------- settings
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in settings.keys():
			settings[k] = cfg.get_value("settings", k, settings[k])
	apply_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)

func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()
	save_settings()

func apply_settings() -> void:
	_set_bus("Master", settings.master_volume)
	_set_bus("SFX", settings.sfx_volume)
	_set_bus("Music", settings.music_volume * 0.7)
	settings_changed.emit()

func _set_bus(bus: String, lin: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(lin, 0.0001)))
		AudioServer.set_bus_mute(idx, lin <= 0.001)


# ---------------------------------------------------------------- game state
func reset_run() -> void:
	score = 0
	kills = 0
	headshots = 0
	shots_fired = 0
	shots_hit = 0
	wave = 0
	time_alive = 0.0
	score_changed.emit(score)

func add_score(amount: int, reason := "") -> void:
	score += amount
	score_changed.emit(score)

func register_kill(info: Dictionary) -> void:
	kills += 1
	if info.get("headshot", false):
		headshots += 1
	var pts := 100 + (50 if info.get("headshot", false) else 0)
	add_score(pts)
	info["points"] = pts
	kill_registered.emit(info)

func set_wave(w: int) -> void:
	wave = w
	wave_changed.emit(w)

func end_run() -> void:
	in_game = false
	var stats := {
		"score": score, "kills": kills, "headshots": headshots, "wave": wave,
		"accuracy": (float(shots_hit) / float(shots_fired) * 100.0) if shots_fired > 0 else 0.0,
		"time": time_alive,
	}
	game_over.emit(stats)

func message(text: String, kind := "info") -> void:
	hud_message.emit(text, kind)


func _process(delta: float) -> void:
	if in_game and not paused:
		time_alive += delta
	if _js_window != null:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_state_timer = 0.25
			_publish_state()


# ---------------------------------------------------------------- web test bridge
func _setup_web_bridge() -> void:
	if not OS.has_feature("web"):
		return
	_js_window = JavaScriptBridge.get_interface("window")
	if _js_window == null:
		return
	_js_cb = JavaScriptBridge.create_callback(_on_js_cmd)
	_js_window.ironline_cmd = _js_cb
	JavaScriptBridge.eval("window.ironline_state = () => JSON.parse(window.ironline_state_json || 'null');", true)
	_publish_state()

func _on_js_cmd(args: Array) -> void:
	if args.is_empty():
		return
	run_command(str(args[0]))
	_publish_state()

## Debug/test command interface (also usable from native builds).
func run_command(cmd: String) -> void:
	var p := cmd.strip_edges().split(" ", false)
	if p.is_empty():
		return
	match p[0]:
		"look":
			if p.size() >= 3:
				injected_look += Vector2(float(p[1]), float(p[2]))
		"move":
			if p.size() >= 3:
				var map := {"fwd": "move_forward", "back": "move_back", "left": "move_left", "right": "move_right"}
				_hold(map.get(p[1], ""), p[2] == "on")
		"fire":
			if p.size() >= 2: _hold("fire", p[1] == "on")
		"ads":
			if p.size() >= 2: _hold("ads", p[1] == "on")
		"hold":
			if p.size() >= 3: _hold(p[1], p[2] == "on")
		"key":
			if p.size() >= 2:
				_tap(p[1])
		"teleport":
			if p.size() >= 4 and player:
				player.global_position = Vector3(float(p[1]), float(p[2]), float(p[3]))
				player.velocity = Vector3.ZERO
		"face":
			# face <yaw_deg> <pitch_deg>
			if p.size() >= 3 and player and player.has_method("set_view_angles"):
				player.set_view_angles(float(p[1]), float(p[2]))
		"start":
			if world and world.has_method("start_game"):
				world.start_game()
		"god":
			if player: player.set("god_mode", true)
		"weapon":
			if p.size() >= 2 and player and player.has_method("select_weapon"):
				player.select_weapon(int(p[1]))
		"spawn":
			if world and world.has_method("debug_spawn_enemy"):
				world.debug_spawn_enemy(int(p[1]) if p.size() > 1 else 1)
		"timescale":
			if p.size() >= 2: Engine.time_scale = float(p[1])
		"set":
			# set <setting> <value>
			if p.size() >= 3 and settings.has(p[1]):
				var cur = settings[p[1]]
				var v: Variant = p[2]
				if cur is bool: v = p[2] in ["1", "true", "on"]
				elif cur is int: v = int(p[2])
				elif cur is float: v = float(p[2])
				set_setting(p[1], v)
		"state":
			pass

func _hold(action: String, on: bool) -> void:
	if action == "" or not InputMap.has_action(action):
		return
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)

func _tap(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.05, true, false, true).timeout
	var ev2 := InputEventAction.new()
	ev2.action = action
	ev2.pressed = false
	Input.parse_input_event(ev2)

func get_state() -> Dictionary:
	var s := {
		"fps": Engine.get_frames_per_second(),
		"in_game": in_game, "paused": paused, "score": score, "kills": kills, "wave": wave,
	}
	if player and is_instance_valid(player) and player.has_method("debug_state"):
		s.merge(player.debug_state())
	if world and is_instance_valid(world) and world.has_method("debug_state"):
		s.merge(world.debug_state())
	return s

func _publish_state() -> void:
	if _js_window:
		_js_window.ironline_state_json = JSON.stringify(get_state())


func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test") and ResourceLoader.exists("res://tools/tests/runner.gd"):
			var r: Node = load("res://tools/tests/runner.gd").new()
			r.name = "TestRunner"
			add_child.call_deferred(r)
