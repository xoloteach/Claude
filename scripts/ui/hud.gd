class_name HUD
extends CanvasLayer
## In-game HUD: dynamic crosshair, hitmarkers, damage direction, low-health overlay, ammo, compass,
## score popups, wave banners, sniper scope, prompts.

const FONT_NUM := "res://assets/fonts/Rajdhani-Bold.ttf"
const FONT_HEAD := "res://assets/fonts/BarlowCondensed-Bold.ttf"
const FONT_SEMI := "res://assets/fonts/BarlowCondensed-SemiBold.ttf"
const FONT_BODY := "res://assets/fonts/Barlow-SemiBold.ttf"

const C_WHITE := Color(0.96, 0.96, 0.94)
const C_DIM := Color(0.8, 0.82, 0.8, 0.75)
const C_ACCENT := Color(1.0, 0.68, 0.2)
const C_RED := Color(1.0, 0.22, 0.18)

var player: Player
var root: Control
var overlay: ColorRect         # hurt vignette (screen shader)
var draw_layer: Control        # crosshair, hitmarker, damage arcs, compass
var scope: Control
var ammo_mag: Label
var ammo_res: Label
var weapon_name: Label
var weapon_class: Label
var ammo_ticks: Control
var reload_prompt: Label
var score_label: Label
var wave_label: Label
var enemies_label: Label
var banner: Control
var banner_title: Label
var banner_sub: Label
var popups: VBoxContainer
var feed: VBoxContainer
var fps_label: Label
var hint_label: Label
var tac_bar: Control
var _ammo_box: Control
var _touch_layout := false

var _hit_t := 1.0
var _hit_kind := ""
var _dmg_arcs: Array = []   # [world_pos, t, amount]
var _enemy_pings: Array = []  # [world_pos, t]
var _cross_alpha := 1.0
var _hurt := 0.0
var _mag := 30
var _ammo := 30
var _time := 0.0
var _banner_t := 10.0
var _fonts := {}


func _font(path: String) -> Font:
	if not _fonts.has(path):
		_fonts[path] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[path]


func _label(text: String, font: String, size: int, color := C_WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", 6)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# hurt / low-health screen overlay
	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/hurt_overlay.gdshader")
	overlay.material = sm
	root.add_child(overlay)
	# scope
	scope = Control.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.visible = false
	scope.draw.connect(_draw_scope)
	root.add_child(scope)
	# vector layer
	draw_layer = Control.new()
	draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_layer.draw.connect(_draw_vectors)
	root.add_child(draw_layer)
	_build_ammo()
	_build_topleft()
	_build_banner()
	# popups (score) right of crosshair
	popups = VBoxContainer.new()
	popups.set_anchors_preset(Control.PRESET_CENTER)
	popups.position = Vector2(60, 30)
	popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popups.add_theme_constant_override("separation", -4)
	root.add_child(popups)
	# kill feed bottom-left
	feed = VBoxContainer.new()
	feed.anchor_left = 0.0; feed.anchor_top = 1.0; feed.anchor_bottom = 1.0
	feed.offset_left = 36; feed.offset_top = -260; feed.offset_bottom = -150; feed.offset_right = 520
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed)
	reload_prompt = _label("", FONT_HEAD, 26, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	reload_prompt.set_anchors_preset(Control.PRESET_CENTER)
	reload_prompt.offset_left = -200; reload_prompt.offset_right = 200
	reload_prompt.offset_top = 70; reload_prompt.offset_bottom = 110
	root.add_child(reload_prompt)
	hint_label = _label("", FONT_BODY, 18, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.anchor_left = 0.5; hint_label.anchor_right = 0.5; hint_label.anchor_top = 1.0; hint_label.anchor_bottom = 1.0
	hint_label.offset_left = -400; hint_label.offset_right = 400; hint_label.offset_top = -70; hint_label.offset_bottom = -40
	root.add_child(hint_label)
	fps_label = _label("", FONT_BODY, 14, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	fps_label.anchor_left = 1.0; fps_label.anchor_right = 1.0
	fps_label.offset_left = -200; fps_label.offset_right = -12; fps_label.offset_top = 8
	root.add_child(fps_label)
	Game.hit_confirmed.connect(_on_hit)
	Game.player_hurt.connect(_on_hurt)
	Game.ammo_changed.connect(_on_ammo)
	Game.weapon_changed.connect(_on_weapon)
	Game.kill_registered.connect(_on_kill)
	Game.score_changed.connect(func(s): score_label.text = "%d" % s)
	Game.wave_changed.connect(func(w): wave_label.text = "WAVE %d" % w)
	Game.enemies_remaining.connect(func(n): enemies_label.text = "HOSTILES  %d" % n)
	Game.hud_message.connect(_on_message)


func _build_ammo() -> void:
	var box := Control.new()
	box.anchor_left = 1.0; box.anchor_right = 1.0; box.anchor_top = 1.0; box.anchor_bottom = 1.0
	box.offset_left = -420; box.offset_right = -40; box.offset_top = -150; box.offset_bottom = -34
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	_ammo_box = box
	weapon_name = _label("M13", FONT_HEAD, 24, C_WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	weapon_name.position = Vector2(0, 0); weapon_name.size = Vector2(380, 30)
	box.add_child(weapon_name)
	weapon_class = _label("ASSAULT RIFLE", FONT_SEMI, 15, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	weapon_class.position = Vector2(0, 26); weapon_class.size = Vector2(380, 20)
	box.add_child(weapon_class)
	ammo_mag = _label("30", FONT_NUM, 64, C_WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	ammo_mag.position = Vector2(0, 38); ammo_mag.size = Vector2(290, 70)
	box.add_child(ammo_mag)
	ammo_res = _label("/ 240", FONT_NUM, 30, C_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	ammo_res.position = Vector2(296, 66); ammo_res.size = Vector2(100, 36)
	box.add_child(ammo_res)
	ammo_ticks = Control.new()
	ammo_ticks.position = Vector2(80, 104); ammo_ticks.size = Vector2(300, 10)
	ammo_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_ticks.draw.connect(_draw_ticks)
	box.add_child(ammo_ticks)
	tac_bar = Control.new()
	tac_bar.anchor_left = 0.5; tac_bar.anchor_right = 0.5; tac_bar.anchor_top = 1.0; tac_bar.anchor_bottom = 1.0
	tac_bar.offset_left = -60; tac_bar.offset_right = 60; tac_bar.offset_top = -96; tac_bar.offset_bottom = -92
	tac_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tac_bar.draw.connect(_draw_tac)
	root.add_child(tac_bar)


func _build_topleft() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(36, 26)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", -6)
	root.add_child(v)
	wave_label = _label("WAVE 1", FONT_HEAD, 30, C_ACCENT)
	v.add_child(wave_label)
	score_label = _label("0", FONT_NUM, 40, C_WHITE)
	v.add_child(score_label)
	enemies_label = _label("", FONT_SEMI, 17, C_DIM)
	v.add_child(enemies_label)


func _build_banner() -> void:
	banner = Control.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 150
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	root.add_child(banner)
	banner_title = _label("", FONT_HEAD, 64, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	banner_title.position = Vector2(-500, 0); banner_title.size = Vector2(1000, 70)
	banner.add_child(banner_title)
	banner_sub = _label("", FONT_SEMI, 22, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	banner_sub.position = Vector2(-500, 68); banner_sub.size = Vector2(1000, 30)
	banner.add_child(banner_sub)


# ------------------------------------------------------------------ events
func _on_hit(kind: String, _dmg: float) -> void:
	_hit_kind = kind
	_hit_t = 0.0
	match kind:
		"kill": Audio.play("hitmarker_kill", -2.0, 0.02)
		"headkill":
			Audio.play("hitmarker_kill", -2.0, 0.02)
			Audio.play("headshot", -4.0, 0.03)
		"head": Audio.play("headshot", -5.0, 0.03)
		"armor":
			Audio.play("hitmarker", -5.0, 0.03)
			Audio.play("impact_metal", -14.0, 0.1)
		_: Audio.play("hitmarker", -5.0, 0.03)


func _on_hurt(from_pos: Vector3, amount: float) -> void:
	if amount <= 0.0:
		return
	_hurt = minf(1.0, _hurt + amount / 45.0)
	_dmg_arcs.append([from_pos, 0.0, amount])
	if _dmg_arcs.size() > 6:
		_dmg_arcs.pop_front()


func ping_enemy(world_pos: Vector3) -> void:
	_enemy_pings.append([world_pos, 0.0])
	if _enemy_pings.size() > 12:
		_enemy_pings.pop_front()


func _on_ammo(ammo: int, reserve: int, mag: int) -> void:
	_ammo = ammo
	_mag = mag
	ammo_mag.text = str(ammo)
	ammo_res.text = "/ %d" % reserve
	var low := ammo <= int(ceil(mag * 0.25))
	ammo_mag.add_theme_color_override("font_color", C_RED if ammo == 0 else (C_ACCENT if low else C_WHITE))
	ammo_ticks.queue_redraw()


func _on_weapon(def: Dictionary) -> void:
	weapon_name.text = def.name
	weapon_class.text = def["class"]
	var t := create_tween()
	weapon_name.modulate = Color(1.4, 1.2, 0.8)
	t.tween_property(weapon_name, "modulate", Color.WHITE, 0.4)


func _on_kill(info: Dictionary) -> void:
	var head: bool = info.get("headshot", false)
	_popup("+%d" % info.get("points", 100), "HEADSHOT" if head else "KILL")
	var l := _label("", FONT_SEMI, 18, C_WHITE)
	l.text = "%s   [%s]   %s%s" % ["YOU", info.get("weapon", ""), info.get("name", "HOSTILE"), "   ✚ HEADSHOT" if head else ""]
	feed.add_child(l)
	if feed.get_child_count() > 5:
		feed.get_child(0).queue_free()
	var t := create_tween()
	t.tween_interval(4.0)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


func _popup(points: String, reason: String) -> void:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 10)
	var a := _label(points, FONT_NUM, 30, C_ACCENT)
	var b := _label(reason, FONT_HEAD, 20, C_WHITE)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(a)
	h.add_child(b)
	popups.add_child(h)
	if popups.get_child_count() > 4:
		popups.get_child(0).queue_free()
	h.modulate = Color(1, 1, 1, 0)
	h.scale = Vector2(1.3, 1.3)
	var t := create_tween()
	t.tween_property(h, "modulate:a", 1.0, 0.08)
	t.parallel().tween_property(h, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.5)
	t.tween_property(h, "modulate:a", 0.0, 0.5)
	t.tween_callback(h.queue_free)


func _on_message(text: String, kind: String) -> void:
	if kind == "banner" or kind == "wave":
		var parts := text.split("|")
		banner_title.text = parts[0]
		banner_sub.text = parts[1] if parts.size() > 1 else ""
		_banner_t = 0.0
	elif kind == "hint":
		hint_label.text = text
	elif kind == "popup":
		var parts2 := text.split("|")
		_popup(parts2[0], parts2[1] if parts2.size() > 1 else "")


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	_time += delta
	_hit_t += delta
	_hurt = maxf(0.0, _hurt - delta * 0.9)
	_banner_t += delta
	var bt := _banner_t
	banner.modulate.a = clampf(bt / 0.25, 0.0, 1.0) * clampf((3.2 - bt) / 0.6, 0.0, 1.0)
	banner.scale = Vector2.ONE * (1.0 + maxf(0.0, 0.25 - bt) * 0.6)
	for a in _dmg_arcs:
		a[1] += delta
	_dmg_arcs = _dmg_arcs.filter(func(a): return a[1] < 2.0)
	for p in _enemy_pings:
		p[1] += delta
	_enemy_pings = _enemy_pings.filter(func(p): return p[1] < 2.5)
	if player and is_instance_valid(player):
		var w := player.weapons
		var hide := w.ads_t > 0.5 or player.sprinting or not player.alive or player.mantling
		_cross_alpha = move_toward(_cross_alpha, 0.0 if hide else 1.0, delta * 10.0)
		var scoped: bool = w.weapon and w.weapon.def.get("scope", false) and w.ads_t > 0.94
		scope.visible = scoped
		if scoped:
			scope.queue_redraw()
		var low := 1.0 - player.health_ratio()
		var mat := overlay.material as ShaderMaterial
		mat.set_shader_parameter("hurt", clampf(_hurt, 0.0, 1.0))
		mat.set_shader_parameter("low_health", clampf(low * 1.25 - 0.25, 0.0, 1.0))
		mat.set_shader_parameter("time", _time)
		if w.weapon:
			if _ammo == 0 and w.weapon.reserve == 0:
				reload_prompt.text = "NO AMMO"
				reload_prompt.add_theme_color_override("font_color", C_RED)
			elif _ammo <= int(ceil(_mag * 0.25)) and not w.is_reloading():
				reload_prompt.text = "[%s] RELOAD" % _glyph("reload")
				reload_prompt.add_theme_color_override("font_color", C_WHITE)
			else:
				reload_prompt.text = ""
		tac_bar.visible = player.tac_sprinting or player.tac_time_left < Player.TAC_TIME - 0.05
		tac_bar.queue_redraw()
		# heartbeat on low health
		if player.alive and player.health_ratio() < 0.35:
			var period := 0.75
			if fmod(_time, period) < delta:
				Audio.play("heartbeat", -6.0, 0.0)
	_update_touch_layout()
	fps_label.visible = Game.settings.show_fps
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	draw_layer.queue_redraw()


## Touch controls own the bottom corners: the touch layer draws its own ammo readout next to FIRE,
## so the big ammo block and bottom hint are hidden and the kill feed moves under the score.
func _update_touch_layout() -> void:
	var t: Node = Game.world.get("touch") if Game.world else null
	var on: bool = t != null and t.has_method("is_active") and t.is_active()
	if on == _touch_layout:
		return
	_touch_layout = on
	_ammo_box.visible = not on
	hint_label.visible = not on
	if on:
		feed.anchor_top = 0.0; feed.anchor_bottom = 0.0
		feed.offset_left = 150; feed.offset_top = 112; feed.offset_bottom = 230; feed.offset_right = 560
		feed.alignment = BoxContainer.ALIGNMENT_BEGIN
		fps_label.offset_right = -80
	else:
		feed.anchor_top = 1.0; feed.anchor_bottom = 1.0
		feed.offset_left = 36; feed.offset_top = -260; feed.offset_bottom = -150; feed.offset_right = 520
		feed.alignment = BoxContainer.ALIGNMENT_END
		fps_label.offset_right = -12


func _glyph(action: String) -> String:
	if Game.input_mode == "pad":
		return {"reload": "X", "interact": "X", "jump": "A", "crouch": "B", "swap": "Y", "grenade": "RB",
			"melee": "R3", "sprint": "L3", "ads": "LT", "fire": "RT", "pause": "START", "scoreboard": "BACK"}.get(action, action.to_upper())
	if _touch_layout or Game.input_mode == "touch":
		return "TAP"
	return {"reload": "R", "interact": "F", "jump": "SPACE", "crouch": "C", "swap": "Q", "grenade": "G",
		"melee": "V", "sprint": "SHIFT", "ads": "RMB", "fire": "LMB", "pause": "ESC", "scoreboard": "TAB"}.get(action, action.to_upper())


func _draw_vectors() -> void:
	var c := draw_layer.size * 0.5
	if player and is_instance_valid(player):
		_draw_crosshair(c)
		_draw_damage_arcs(c)
		_draw_compass()
	_draw_hitmarker(c)


func _draw_crosshair(c: Vector2) -> void:
	if _cross_alpha <= 0.01:
		return
	var w := player.weapons
	var cam := player.camera
	# convert spread angle to pixels
	var vfov := deg_to_rad(cam.fov)
	var px := tan(deg_to_rad(w.spread)) / tan(vfov * 0.5) * draw_layer.size.y * 0.5
	var gap := clampf(px, 4.0, 220.0)
	var col := Color(1, 1, 1, 0.9 * _cross_alpha)
	var sh := Color(0, 0, 0, 0.45 * _cross_alpha)
	var len := 9.0
	var shotgun: bool = w.weapon and w.weapon.def.pellets > 1
	if shotgun:
		draw_layer.draw_arc(c, gap + 6, 0, TAU, 48, sh, 3.0, true)
		draw_layer.draw_arc(c, gap + 6, 0, TAU, 48, col, 1.5, true)
	else:
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var a: Vector2 = c + d * gap
			var b: Vector2 = c + d * (gap + len)
			draw_layer.draw_line(a, b, sh, 4.0)
			draw_layer.draw_line(a, b, col, 2.0)
	draw_layer.draw_circle(c, 1.8, sh)
	draw_layer.draw_circle(c, 1.1, col)


func _draw_hitmarker(c: Vector2) -> void:
	var dur := 0.28 if _hit_kind in ["kill", "headkill"] else 0.18
	if _hit_t > dur:
		return
	var k := _hit_t / dur
	var col := C_WHITE
	var sz := 11.0
	var inner := 5.0
	var width := 2.2
	if _hit_kind in ["kill", "headkill"]:
		col = C_RED
		sz = 15.0
		width = 3.0
	elif _hit_kind == "head":
		col = Color(1.0, 0.9, 0.5)
		sz = 13.0
	elif _hit_kind == "armor":
		col = Color(0.55, 0.8, 1.0)
		sz = 12.0
	var grow := 1.0 + (1.0 - k) * 0.35 if _hit_kind in ["kill", "headkill"] else 1.0 + k * 0.15
	col.a = 1.0 - k * k
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var n: Vector2 = d.normalized()
		var a := c + n * inner * grow
		var b := c + n * (inner + sz) * grow
		draw_layer.draw_line(a, b, Color(0, 0, 0, col.a * 0.5), width + 2.0)
		draw_layer.draw_line(a, b, col, width)


func _draw_damage_arcs(c: Vector2) -> void:
	var cam := player.camera
	for a in _dmg_arcs:
		var from: Vector3 = a[0]
		var t: float = a[1]
		var local := cam.global_basis.inverse() * (from - cam.global_position)
		var ang := atan2(local.x, -local.z)   # 0 = in front, + = right
		var alpha := clampf(1.0 - t / 2.0, 0.0, 1.0) * clampf(a[2] / 15.0, 0.5, 1.0)
		var r := 150.0
		var start := ang - PI * 0.5 - 0.22
		draw_layer.draw_arc(c, r, start, start + 0.44, 24, Color(0.9, 0.08, 0.05, alpha * 0.9), 10.0, true)
		draw_layer.draw_arc(c, r + 7.0, start + 0.12, start + 0.32, 12, Color(1, 0.3, 0.2, alpha), 3.0, true)


func _draw_compass() -> void:
	var cam := player.camera
	var w := 520.0
	var cx := draw_layer.size.x * 0.5
	var y := 34.0
	var fwd := -cam.global_basis.z
	var heading := rad_to_deg(atan2(fwd.x, -fwd.z))   # 0 = north (-Z)
	var font := _font(FONT_SEMI)
	draw_layer.draw_rect(Rect2(cx - w * 0.5, y - 2, w, 1), Color(1, 1, 1, 0.25))
	for deg in range(0, 360, 15):
		var diff := wrapf(deg - heading, -180.0, 180.0)
		if absf(diff) > 45.0:
			continue
		var x := cx + diff / 45.0 * w * 0.5
		var alpha := 1.0 - absf(diff) / 45.0
		var major := deg % 45 == 0
		draw_layer.draw_line(Vector2(x, y), Vector2(x, y + (10 if major else 5)), Color(1, 1, 1, 0.7 * alpha), 2.0 if major else 1.0)
		if major:
			var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
			var txt: String = names.get(deg, str(deg))
			var col := C_ACCENT if deg == 0 else Color(1, 1, 1, alpha)
			col.a = alpha
			var fs := 18 if txt.length() == 1 else 15
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_layer.draw_string(font, Vector2(x - tw * 0.5, y + 30), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_layer.draw_colored_polygon(PackedVector2Array([Vector2(cx - 6, y - 10), Vector2(cx + 6, y - 10), Vector2(cx, y - 3)]), C_ACCENT)
	var hs := "%03d" % int(posmod(roundi(heading), 360))
	var hw := font.get_string_size(hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_layer.draw_string(font, Vector2(cx - hw * 0.5, y - 14), hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_DIM)
	# enemy fire pings
	for p in _enemy_pings:
		var to: Vector3 = p[0] - cam.global_position
		var h := rad_to_deg(atan2(to.x, -to.z))
		var diff2 := wrapf(h - heading, -180.0, 180.0)
		var x2 := cx + clampf(diff2 / 45.0, -1.0, 1.0) * w * 0.5
		var a2 := clampf(1.0 - p[1] / 2.5, 0.0, 1.0)
		draw_layer.draw_rect(Rect2(x2 - 4, y + 2, 8, 8), Color(1, 0.2, 0.15, a2))


func _draw_ticks() -> void:
	var n := _mag
	if n <= 0:
		return
	var w := ammo_ticks.size.x
	var gapw := 2.0
	var tw := minf((w - gapw * (n - 1)) / n, 8.0)
	var total := tw * n + gapw * (n - 1)
	var x0 := w - total
	for i in n:
		var filled := i >= n - _ammo
		var col := Color(1, 1, 1, 0.85) if filled else Color(1, 1, 1, 0.15)
		if filled and _ammo <= int(ceil(_mag * 0.25)):
			col = C_ACCENT
		ammo_ticks.draw_rect(Rect2(x0 + i * (tw + gapw), 0, tw, 8), col)


func _draw_tac() -> void:
	if not player:
		return
	var r := clampf(player.tac_time_left / Player.TAC_TIME, 0.0, 1.0)
	tac_bar.draw_rect(Rect2(Vector2.ZERO, tac_bar.size), Color(0, 0, 0, 0.35))
	tac_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(tac_bar.size.x * r, tac_bar.size.y)), C_ACCENT if player.tac_cooldown <= 0.0 else Color(0.6, 0.6, 0.6, 0.6))


func _draw_scope() -> void:
	var s := scope.size
	var c := s * 0.5
	var r := s.y * 0.46
	# black surround via thick ring
	var outer := s.length()
	scope.draw_arc(c, (r + outer) * 0.5, 0, TAU, 96, Color(0, 0, 0, 1), outer - r + 2.0, true)
	# lens shading
	for i in 10:
		var rr := r - i * 6.0
		scope.draw_arc(c, rr, 0, TAU, 96, Color(0, 0, 0, 0.12 * (1.0 - i / 10.0)), 6.0, true)
	var col := Color(0.02, 0.02, 0.02, 0.95)
	# thick outer posts + thin center crosshair
	scope.draw_line(Vector2(c.x - r, c.y), Vector2(c.x - r * 0.25, c.y), col, 5.0)
	scope.draw_line(Vector2(c.x + r * 0.25, c.y), Vector2(c.x + r, c.y), col, 5.0)
	scope.draw_line(Vector2(c.x, c.y + r * 0.25), Vector2(c.x, c.y + r), col, 5.0)
	scope.draw_line(Vector2(c.x - r * 0.25, c.y), Vector2(c.x + r * 0.25, c.y), col, 1.5)
	scope.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r * 0.25), col, 1.5)
	for i in range(1, 5):
		var o := r * 0.055 * i
		scope.draw_circle(Vector2(c.x + o, c.y), 2.2, col)
		scope.draw_circle(Vector2(c.x - o, c.y), 2.2, col)
		scope.draw_circle(Vector2(c.x, c.y + o), 2.2, col)
	scope.draw_circle(c, 1.6, Color(1, 0.15, 0.1, 0.95))
