extends CanvasLayer
## On-screen touch controls (CoD Mobile style), multi-touch with per-finger tracking.
##   left  : floating joystick (appears under the thumb), push to the top edge => auto sprint
##   right : drag anywhere to look; the big FIRE button also looks while held
##   buttons: FIRE (x2), ADS (toggle), RELOAD, JUMP, CROUCH, SWAP, GRENADE, MELEE, PAUSE
## Active while main.state == "playing" and touch controls are wanted (setting Auto/On).
## With the setting forced On on a device without a touchscreen, the left mouse button drives
## the controls as a single simulated finger (desktop testing).

const T := preload("res://scripts/ui/ui_theme.gd")
const TEX_DIR := "res://assets/textures/ui/touch/"
const DESIGN := Vector2(915, 412)       # layout reference (CSS px of a typical phone in landscape)
const STICK_R := 64.0
const STICK_ZONE_X := 0.42             # floating joystick zone: left 42 % of the screen
const STICK_ZONE_TOP := 0.26           # ... below the top 26 % (score / left fire live there)
const DEADZONE := 0.12
const SPRINT_ENGAGE := 0.9             # pushed past 90 % towards the top => sprint
const LOOK_PER_SCREEN_H := 950.0       # look "pixels" per full-screen-height drag (x touch_sensitivity)
const TAP_HOLD := 0.07                 # seconds a tapped action stays pressed

var root: Control
var _k := 1.0                          # design unit -> screen px
var _active := false
var _fingers := {}                     # index -> {type, btn, last}
var _buttons: Array = []
var _btn_by_id := {}
var _tex := {}
var _stick_finger := -1
var _stick_base := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _sprint_latched := false
var _sprint_flash := 0.0
var _fire_holders := 0
var _ads_on := false
var _pending_release := {}             # action -> time left
var _removed_mouse_events := {}        # action -> Array[InputEvent] (restored on deactivate)
var _emulate_default := true
var _mouse_sim_down := false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_emulate_default = Input.emulate_mouse_from_touch
	root = Control.new()
	root.name = "TouchRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_root)
	add_child(root)
	for n in ["button_circle", "joystick_circle_pad_a", "joystick_circle_nub_a", "icon_fire", "icon_crosshair",
			"icon_arrow_rotate", "icon_jump", "icon_arrow", "icon_burst", "icon_hand", "icon_pause", "icon_target"]:
		var p: String = TEX_DIR + n + ".png"
		_tex[n] = load(p) if ResourceLoader.exists(p) else null
	# id, action, kind, anchor(0/1 x,y), offset (design px from anchor), radius, icon, caption
	_add_btn("fire", "fire", "fire", Vector2(1, 1), Vector2(-168, -118), 52, "icon_fire", "")
	_add_btn("fire_l", "fire", "fire_small", Vector2(0, 0), Vector2(96, 150), 31, "icon_fire", "")
	_add_btn("ads", "ads", "toggle", Vector2(1, 1), Vector2(-272, -158), 33, "icon_crosshair", "ADS")
	_add_btn("jump", "jump", "tap", Vector2(1, 1), Vector2(-64, -168), 34, "icon_jump", "JUMP")
	_add_btn("crouch", "crouch", "tap", Vector2(1, 1), Vector2(-64, -66), 32, "icon_jump", "CROUCH")
	_add_btn("reload", "reload", "tap", Vector2(1, 1), Vector2(-150, -232), 28, "icon_arrow_rotate", "RELOAD")
	_add_btn("grenade", "grenade", "tap", Vector2(1, 1), Vector2(-240, -262), 26, "icon_burst", "NADE")
	_add_btn("melee", "melee", "tap", Vector2(1, 1), Vector2(-62, -262), 26, "icon_hand", "MELEE")
	_add_btn("swap", "next_weapon", "tap", Vector2(1, 1), Vector2(-282, -58), 27, "icon_arrow", "SWAP")
	_add_btn("pause", "", "pause", Vector2(1, 0), Vector2(-38, 36), 22, "icon_pause", "")
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	root.visible = false


func _add_btn(id: String, action: String, kind: String, anchor: Vector2, off: Vector2, r: float, icon: String, caption: String) -> void:
	var b := {"id": id, "action": action, "kind": kind, "anchor": anchor, "off": off, "r": r, "icon": icon,
		"caption": caption, "pos": Vector2.ZERO, "rad": r, "down": false, "flash": 0.0}
	_buttons.append(b)
	_btn_by_id[id] = b


func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_k = clampf(minf(vp.y / DESIGN.y, vp.x / DESIGN.x * 1.15), 0.5, 4.0)
	for b in _buttons:
		b.pos = Vector2(b.anchor.x * vp.x, b.anchor.y * vp.y) + b.off * _k
		b.rad = b.r * _k
	root.queue_redraw()


# ====================================================================== activation
func _main() -> Node:
	return get_parent()


func _wanted() -> bool:
	var t: int = int(Game.settings.get("touch_controls", -1))
	if t == 0:
		return false
	if t == 1:
		return true
	var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	return Game.wants_touch_controls() and (Game.input_mode == "touch" or mobile)


func is_active() -> bool:
	var m := _main()
	return _wanted() and m != null and str(m.get("state")) == "playing"


func _mouse_sim() -> bool:
	return _active and int(Game.settings.get("touch_controls", -1)) == 1 and not DisplayServer.is_touchscreen_available()


func _set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	root.visible = on
	if on:
		_relayout()
		# gameplay must not see emulated mouse clicks as "fire"/"ads"
		Input.emulate_mouse_from_touch = false
		for a in ["fire", "ads"]:
			var removed: Array = []
			for e in InputMap.action_get_events(a):
				if e is InputEventMouseButton:
					removed.append(e)
			for e in removed:
				InputMap.action_erase_event(a, e)
			_removed_mouse_events[a] = removed
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_release_all()
		Input.emulate_mouse_from_touch = _emulate_default
		for a in _removed_mouse_events:
			for e in _removed_mouse_events[a]:
				InputMap.action_add_event(a, e)
		_removed_mouse_events.clear()


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "fire", "ads"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	for a in _pending_release:
		_send_action(a, false)
	_pending_release.clear()
	_fingers.clear()
	_stick_finger = -1
	_stick_vec = Vector2.ZERO
	_sprint_latched = false
	_fire_holders = 0
	_ads_on = false
	_mouse_sim_down = false
	for b in _buttons:
		b.down = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _active:
			_release_all()


# ====================================================================== input
func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()
	elif _mouse_sim():
		# desktop testing: left mouse button = one finger (index 0)
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed and not _mouse_sim_down:
					_mouse_sim_down = true
					_touch_down(0, event.position)
				elif not event.pressed and _mouse_sim_down:
					_mouse_sim_down = false
					_touch_up(0, event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and _mouse_sim_down:
			_touch_drag(0, event.position, event.relative)
			get_viewport().set_input_as_handled()


func _hit_button(p: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for b in _buttons:
		var d: float = p.distance_to(b.pos)
		# generous hit area (fingers are fat), nearest wins where they overlap
		if d < b.rad * 1.2 + 6.0 * _k and d / b.rad < best_d:
			best_d = d / b.rad
			best = b
	return best


func _touch_down(idx: int, p: Vector2) -> void:
	if _fingers.has(idx):
		_touch_up(idx, p)
	var vp := get_viewport().get_visible_rect().size
	var b := _hit_button(p)
	if not b.is_empty():
		_fingers[idx] = {"type": "btn", "btn": b.id, "last": p}
		_button_down(b)
		return
	if _stick_finger < 0 and p.x < vp.x * STICK_ZONE_X and p.y > vp.y * STICK_ZONE_TOP:
		_fingers[idx] = {"type": "stick", "last": p}
		_stick_finger = idx
		var r := STICK_R * _k
		_stick_base = Vector2(clampf(p.x, r + 8.0, vp.x - r), clampf(p.y, r + 8.0, vp.y - r - 8.0))
		_stick_pos = p
		_update_stick()
		return
	_fingers[idx] = {"type": "look", "last": p}


func _touch_drag(idx: int, p: Vector2, rel: Vector2) -> void:
	if not _fingers.has(idx):
		return
	var f: Dictionary = _fingers[idx]
	f.last = p
	match f.type:
		"stick":
			_stick_pos = p
			_update_stick()
		"look":
			_look(rel)
		"btn":
			var b: Dictionary = _btn_by_id[f.btn]
			if b.kind == "fire":
				_look(rel)   # CoD Mobile: the fire button doubles as an aim pad


func _touch_up(idx: int, _p: Vector2) -> void:
	if not _fingers.has(idx):
		return
	var f: Dictionary = _fingers[idx]
	_fingers.erase(idx)
	match f.type:
		"stick":
			_stick_finger = -1
			_stick_vec = Vector2.ZERO
			_sprint_latched = false
			_apply_move()
		"btn":
			_button_up(_btn_by_id[f.btn])


func _look(rel: Vector2) -> void:
	var vh := get_viewport().get_visible_rect().size.y
	Game.injected_look += rel * (LOOK_PER_SCREEN_H / maxf(vh, 1.0))


# ====================================================================== stick
func _update_stick() -> void:
	var r := STICK_R * _k
	var d := _stick_pos - _stick_base
	var v := d / r
	if v.length() > 1.0:
		v = v.normalized()
	_stick_vec = v if v.length() > DEADZONE else Vector2.ZERO
	_apply_move()
	# auto sprint when pushed to the top edge (within ~35 deg of straight up)
	var up := -v.y
	var in_zone := up > SPRINT_ENGAGE * 0.92 and v.length() > SPRINT_ENGAGE and absf(v.x) < 0.58
	if in_zone and not _sprint_latched:
		_sprint_latched = true
		_sprint_flash = 1.0
		if _ads_on:
			_set_ads(false)
		_tap("sprint")
	elif _sprint_latched and up < 0.45:
		_sprint_latched = false


func _apply_move() -> void:
	var v := _stick_vec
	# rescale so the deadzone edge maps to 0
	if v != Vector2.ZERO:
		var m := clampf((v.length() - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
		v = v.normalized() * m
	_axis("move_right", maxf(v.x, 0.0))
	_axis("move_left", maxf(-v.x, 0.0))
	_axis("move_back", maxf(v.y, 0.0))
	_axis("move_forward", maxf(-v.y, 0.0))


func _axis(action: String, s: float) -> void:
	if s > 0.001:
		Input.action_press(action, s)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


# ====================================================================== buttons
func _button_down(b: Dictionary) -> void:
	b.down = true
	b.flash = 1.0
	match b.kind:
		"fire", "fire_small":
			_fire_holders += 1
			Input.action_press("fire")
		"toggle":
			_set_ads(not _ads_on)
		"tap":
			_tap(b.action)
		"pause":
			pass


func _button_up(b: Dictionary) -> void:
	b.down = false
	match b.kind:
		"fire", "fire_small":
			_fire_holders = maxi(0, _fire_holders - 1)
			if _fire_holders == 0:
				Input.action_release("fire")
		"pause":
			var m := _main()
			_release_all()
			if m and m.has_method("pause_game"):
				m.pause_game()


func _set_ads(on: bool) -> void:
	_ads_on = on
	if on:
		Input.action_press("ads")
	else:
		Input.action_release("ads")


## Quick press + release a little later (an InputEventAction so _unhandled_input users such as
## next_weapon see it, and held long enough that physics-frame "just pressed" checks catch it).
func _tap(action: String) -> void:
	if not InputMap.has_action(action):
		return
	if _pending_release.has(action):
		_send_action(action, false)
	_send_action(action, true)
	_pending_release[action] = TAP_HOLD


func _send_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


# ====================================================================== frame
func _process(delta: float) -> void:
	_set_active(is_active())
	if not _active:
		return
	for a in _pending_release.keys():
		_pending_release[a] -= delta
		if _pending_release[a] <= 0.0:
			_pending_release.erase(a)
			_send_action(a, false)
	# ADS toggle is cleared if the player starts sprinting some other way
	if _ads_on and Game.player and is_instance_valid(Game.player) and Game.player.get("sprinting"):
		_set_ads(false)
	_sprint_flash = maxf(0.0, _sprint_flash - delta * 2.5)
	for b in _buttons:
		b.flash = maxf(0.0, b.flash - delta * 5.0)
	root.queue_redraw()


# ====================================================================== drawing
func _draw_root() -> void:
	if not _active:
		return
	var k := _k
	# ---- joystick
	var r := STICK_R * k
	var base := _stick_base
	var knob := _stick_base + _stick_vec * r
	var idle := _stick_finger < 0
	if idle:
		base = Vector2(150, get_viewport().get_visible_rect().size.y - 118 * k)
		base.x = 150 * k
		knob = base
	var a := 0.45 if idle else 1.0
	root.draw_circle(base, r, Color(0.02, 0.03, 0.04, 0.26 * a))
	_draw_tex("joystick_circle_pad_a", base, r * 2.0, Color(1, 1, 1, 0.42 * a))
	# direction wedge
	if not idle and _stick_vec.length() > DEADZONE:
		var ang := _stick_vec.angle()
		root.draw_arc(base, r - 3.0 * k, ang - 0.5, ang + 0.5, 16, Color(T.C_ACCENT, 0.85), 4.0 * k, true)
	root.draw_circle(knob, r * 0.42, Color(0.9, 0.9, 0.88, 0.32 * a + 0.1))
	root.draw_arc(knob, r * 0.42, 0, TAU, 32, Color(1, 1, 1, 0.7 * a), 2.0 * k, true)
	# sprint lock chip above the stick
	var chip_c := base + Vector2(0, -r - 22.0 * k)
	var sprinting: bool = Game.player != null and is_instance_valid(Game.player) and bool(Game.player.get("sprinting"))
	var chip_col := Color(T.C_ACCENT, 0.95) if sprinting else Color(1, 1, 1, 0.35 * a)
	var cw := 64.0 * k
	var chh := 20.0 * k
	root.draw_rect(Rect2(chip_c - Vector2(cw, chh) * 0.5, Vector2(cw, chh)), Color(0, 0, 0, 0.35 * a + (0.2 if sprinting else 0.0)))
	root.draw_rect(Rect2(chip_c - Vector2(cw, chh) * 0.5, Vector2(cw, chh)), chip_col, false, 1.5 * k)
	var tac: bool = sprinting and bool(Game.player.get("tac_sprinting"))
	_text(chip_c + Vector2(0, 5.5 * k), "TAC SPRINT" if tac else "SPRINT", 12.0 * k * (0.85 if tac else 1.0), chip_col)
	if _sprint_flash > 0.0:
		root.draw_arc(base, r + (1.0 - _sprint_flash) * 20.0 * k, 0, TAU, 40, Color(T.C_ACCENT, _sprint_flash), 3.0 * k, true)
	# ---- buttons
	for b in _buttons:
		_draw_button(b)


func _draw_button(b: Dictionary) -> void:
	var k := _k
	var c: Vector2 = b.pos
	var rr: float = b.rad * (0.93 if b.down else 1.0)
	var on: bool = b.down or (b.kind == "toggle" and _ads_on)
	var big: bool = b.kind == "fire"
	var fill := Color(0.03, 0.035, 0.04, 0.34 if not big else 0.4)
	if on:
		fill = Color(T.C_ACCENT, 0.42)
	root.draw_circle(c, rr, fill)
	var ring := Color(1, 1, 1, 0.55) if not on else Color(1, 0.85, 0.6, 0.95)
	root.draw_arc(c, rr, 0, TAU, 48, ring, (2.6 if big else 2.0) * k, true)
	if big:
		root.draw_arc(c, rr - 6.0 * k, 0, TAU, 48, Color(1, 1, 1, 0.14), 1.0 * k, true)
	if b.flash > 0.0:
		root.draw_arc(c, rr + (1.0 - b.flash) * 12.0 * k, 0, TAU, 40, Color(1, 1, 1, b.flash * 0.6), 2.0 * k, true)
	var icol := Color(1, 1, 1, 0.92) if not on else Color(1, 1, 1, 1)
	var isz: float = rr * (0.95 if big else 1.0)
	match b.id:
		"crouch":
			root.draw_set_transform(c, PI, Vector2.ONE)
			_draw_tex(b.icon, Vector2.ZERO, isz * 0.9, icol)
			root.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"swap":
			root.draw_set_transform(c + Vector2(0, -rr * 0.2), 0.0, Vector2.ONE)
			_draw_tex("icon_arrow", Vector2.ZERO, isz * 0.62, icol)
			root.draw_set_transform(c + Vector2(0, rr * 0.2), PI, Vector2.ONE)
			_draw_tex("icon_arrow", Vector2.ZERO, isz * 0.62, icol)
			root.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"pause":
			_draw_tex(b.icon, c, isz * 0.9, icol)
		_:
			_draw_tex(b.icon, c, isz, icol)
	if b.caption != "":
		_text(c + Vector2(0, rr + 13.0 * k), b.caption, 10.5 * k, Color(1, 1, 1, 0.75))


func _draw_tex(name: String, c: Vector2, size: float, col: Color) -> void:
	var t: Texture2D = _tex.get(name)
	if t == null:
		return
	root.draw_texture_rect(t, Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size)), false, col)


func _text(c: Vector2, s: String, size: float, col: Color) -> void:
	var f := T.font(T.FONT_HEAD, 1)
	var fs := maxi(8, int(size))
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	root.draw_string(f, c - Vector2(w * 0.5, 0) + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, col.a * 0.6))
	root.draw_string(f, c - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# ====================================================================== debug
func debug_state() -> Dictionary:
	return {"touch_active": _active, "fingers": _fingers.size(), "stick": [snappedf(_stick_vec.x, 0.01), snappedf(_stick_vec.y, 0.01)], "ads_toggle": _ads_on}
