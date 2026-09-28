class_name Weapon
extends Node3D
## One weapon instance: ammo state, model, and procedural animation clips (reload / pump / bolt).
## Viewmodel motion (sway/bob/ADS/recoil) is applied by WeaponManager on top of this node's anim pose.

signal clip_event(weapon: Weapon, event: String)

var id := ""
var def: Dictionary
var ammo := 0
var reserve := 0
var model: Node3D
var muzzle: Marker3D
var eject: Marker3D
var sight: Marker3D
var grip_r: Marker3D
var grip_l: Marker3D
var mag_node: Node3D
var pump_node: Node3D
var slide_node: Node3D
var bolt_node: Node3D
var shell_node: Node3D   # shotgun shell visual / sniper clip
var _mag_rest := Transform3D()
var _pump_rest := Transform3D()
var _slide_rest := Transform3D()
var _bolt_rest := Transform3D()

# animation output
var anim_pos := Vector3.ZERO
var anim_rot := Vector3.ZERO
var left_hand_w := 0.0

var clip: Dictionary = {}
var clip_name := ""
var clip_t := 0.0
var _fired_events := {}
var needs_cycle := false        # pump/bolt required before next shot
var shell_reload_active := false
var _shell_reload_cancel := false
var slide_locked := false


func setup(weapon_id: String) -> void:
	id = weapon_id
	def = WeaponDefs.get_def(weapon_id)
	ammo = def.mag
	reserve = def.reserve
	name = weapon_id
	model = WeaponModels.build(def.model)
	add_child(model)
	muzzle = model.get_node_or_null("Muzzle")
	eject = model.get_node_or_null("Eject")
	sight = model.get_node_or_null("Sight")
	grip_r = model.get_node_or_null("GripR")
	grip_l = model.get_node_or_null("GripL")
	mag_node = model.get_node_or_null("Mag")
	pump_node = model.get_node_or_null("Pump")
	slide_node = model.get_node_or_null("Slide")
	bolt_node = model.get_node_or_null("Bolt")
	if mag_node:
		_mag_rest = mag_node.transform
		shell_node = mag_node.get_node_or_null("Shell")
		if shell_node == null:
			shell_node = mag_node.get_node_or_null("Clip")
	if pump_node: _pump_rest = pump_node.transform
	if slide_node: _slide_rest = slide_node.transform
	if bolt_node: _bolt_rest = bolt_node.transform
	_set_layers(model)


func _set_layers(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(n as VisualInstance3D).layers = 2   # viewmodel layer
	for c in n.get_children():
		_set_layers(c)


func is_busy() -> bool:
	return clip_name != ""

func can_fire() -> bool:
	return ammo > 0 and not needs_cycle and (clip_name == "" or clip_name == "shell_loop" or clip_name == "shell_start")

func can_reload() -> bool:
	return ammo < def.mag and reserve > 0 and clip_name == ""


# ------------------------------------------------------------------ clips
func play_clip(n: String) -> void:
	clip = _make_clip(n)
	clip_name = n
	clip_t = 0.0
	_fired_events.clear()

func stop_clip() -> void:
	clip_name = ""
	clip = {}
	anim_pos = Vector3.ZERO
	anim_rot = Vector3.ZERO
	left_hand_w = 0.0
	if mag_node:
		mag_node.transform = _mag_rest
		mag_node.visible = true
	if shell_node:
		shell_node.visible = false
	if pump_node: pump_node.transform = _pump_rest
	if bolt_node: bolt_node.transform = _bolt_rest

func start_reload() -> void:
	if def.mode == "pump":
		shell_reload_active = true
		_shell_reload_cancel = false
		play_clip("shell_start")
	else:
		play_clip("reload_empty" if ammo == 0 else "reload")

func cancel_shell_reload() -> void:
	if shell_reload_active:
		_shell_reload_cancel = true

func interrupt() -> void:
	# e.g. weapon switch / sprint cancel
	shell_reload_active = false
	stop_clip()


func update_anim(delta: float) -> void:
	if slide_node:
		var target := _slide_rest
		if slide_locked:
			target = _slide_rest.translated_local(Vector3(0, 0, 0.035))
		slide_node.transform = slide_node.transform.interpolate_with(target, minf(1.0, delta * 30.0))
	if clip_name == "":
		anim_pos = anim_pos.lerp(Vector3.ZERO, minf(1.0, delta * 12.0))
		anim_rot = anim_rot.lerp(Vector3.ZERO, minf(1.0, delta * 12.0))
		left_hand_w = lerpf(left_hand_w, 0.0, minf(1.0, delta * 12.0))
		return
	clip_t += delta
	var dur: float = clip.duration
	var u := clampf(clip_t / dur, 0.0, 1.0)
	var pr := _sample(clip.get("pose", []), u)
	anim_pos = pr[0]
	anim_rot = pr[1]
	left_hand_w = _sample_f(clip.get("left", []), u)
	if mag_node and clip.has("mag"):
		var mr := _sample(clip.mag, u)
		mag_node.transform = _mag_rest * Transform3D(Basis.from_euler(mr[1] * (PI / 180.0)), mr[0])
		mag_node.visible = _sample_vis(clip.get("mag_vis", []), u)
	if shell_node and clip.has("shell_vis"):
		shell_node.visible = _sample_vis(clip.shell_vis, u)
	if pump_node and clip.has("pump"):
		var pp := _sample(clip.pump, u)
		pump_node.transform = _pump_rest * Transform3D(Basis.IDENTITY, pp[0])
	if bolt_node and clip.has("bolt"):
		var bp := _sample(clip.bolt, u)
		bolt_node.transform = _bolt_rest * Transform3D(Basis.from_euler(bp[1] * (PI / 180.0)), bp[0])
	for e in clip.get("events", []):
		var key := "%s@%s" % [e[1], e[0]]
		if u >= e[0] and not _fired_events.has(key):
			_fired_events[key] = true
			_on_event(e[1])
	if u >= 1.0:
		_on_clip_end()


func _on_event(ev: String) -> void:
	match ev:
		"ammo":
			var need: int = def.mag - ammo
			var take := mini(need, reserve)
			ammo += take
			reserve -= take
			slide_locked = false
		"shell":
			if reserve > 0 and ammo < def.mag:
				ammo += 1
				reserve -= 1
		"cycled":
			needs_cycle = false
		"slide_release":
			slide_locked = false
	clip_event.emit(self, ev)


func _on_clip_end() -> void:
	var finished := clip_name
	stop_clip()
	match finished:
		"shell_start":
			_next_shell()
		"shell_loop":
			_next_shell()
		"shell_end_pump":
			needs_cycle = false
		_:
			pass


func _next_shell() -> void:
	if _shell_reload_cancel or ammo >= def.mag or reserve <= 0:
		shell_reload_active = false
		if needs_cycle:
			play_clip("shell_end_pump")
		else:
			play_clip("shell_end")
	else:
		play_clip("shell_loop")


# ------------------------------------------------------------------ clip sampling
static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

func _sample(keys: Array, u: float) -> Array:
	if keys.is_empty():
		return [Vector3.ZERO, Vector3.ZERO]
	if u <= keys[0][0]:
		return [keys[0][1], keys[0][2]]
	for i in range(1, keys.size()):
		if u <= keys[i][0]:
			var a = keys[i - 1]
			var b = keys[i]
			var f := _ease((u - a[0]) / maxf(b[0] - a[0], 0.0001))
			return [a[1].lerp(b[1], f), a[2].lerp(b[2], f)]
	var l = keys[keys.size() - 1]
	return [l[1], l[2]]

func _sample_f(keys: Array, u: float) -> float:
	if keys.is_empty():
		return 0.0
	if u <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if u <= keys[i][0]:
			var a = keys[i - 1]
			var b = keys[i]
			return lerpf(a[1], b[1], _ease((u - a[0]) / maxf(b[0] - a[0], 0.0001)))
	return keys[keys.size() - 1][1]

func _sample_vis(keys: Array, u: float) -> bool:
	var v := true
	for k in keys:
		if u >= k[0]:
			v = k[1]
	return v


# ------------------------------------------------------------------ clip definitions
func _make_clip(n: String) -> Dictionary:
	var Z := Vector3.ZERO
	match n:
		"reload", "reload_empty":
			var empty := n == "reload_empty"
			var dur: float = def.reload_empty if empty else def.reload
			if def.mode == "bolt":
				return _sniper_reload(dur)
			var tilt := Vector3(10, 14, 30) if id != "pistol" else Vector3(18, 10, 22)
			var p_tilt := Vector3(0.025, -0.02, 0.02)
			var end_u := 0.78 if empty else 0.86
			var c := {
				"duration": dur,
				"pose": [
					[0.0, Z, Z], [0.14, p_tilt, tilt], [0.26, p_tilt + Vector3(0, 0.006, 0), tilt + Vector3(-3, 0, 2)],
					[0.5, p_tilt + Vector3(0, -0.004, 0), tilt + Vector3(2, 0, -1)], [0.55, p_tilt + Vector3(0, 0.012, 0), tilt + Vector3(-5, 0, 3)],
					[0.62, p_tilt, tilt], [end_u, Vector3(-0.005, 0.0, 0.0), Vector3(0, -4, -6)], [1.0, Z, Z]],
				"mag": [[0.0, Z, Z], [0.14, Z, Z], [0.2, Vector3(0, -0.025, 0.003), Vector3(-4, 0, 0)],
					[0.32, Vector3(-0.02, -0.34, 0.08), Vector3(-40, 0, 25)], [0.33, Vector3(-0.05, -0.3, 0.1), Vector3(-10, 0, -10)],
					[0.46, Vector3(-0.01, -0.06, 0.012), Vector3(-6, 0, 0)], [0.53, Vector3(0, -0.012, 0), Z], [0.56, Z, Z], [1.0, Z, Z]],
				"mag_vis": [[0.0, true], [0.325, false], [0.36, true]],
				"left": [[0.0, 0.0], [0.12, 1.0], [0.58, 1.0], [0.68, 0.0]],
				"events": [[0.02, "cloth"], [0.17, "mag_out"], [0.52, "mag_in"], [0.56, "ammo"], [0.6, "mag_tap"]],
			}
			if empty:
				c.events.append([0.72, "bolt_release" if id != "pistol" else "slide_release"])
				c.pose.insert(6, [0.72, p_tilt * 0.5 + Vector3(0, 0.01, 0), Vector3(4, 4, 12)])
				c.left = [[0.0, 0.0], [0.12, 1.0], [0.58, 1.0], [0.66, 0.0]]
			return c
		"shell_start":
			return {"duration": def.reload_start,
				"pose": [[0.0, Z, Z], [1.0, Vector3(0.01, 0.01, 0.01), Vector3(14, 12, 34)]],
				"left": [[0.0, 0.0], [1.0, 0.6]], "events": [[0.05, "cloth"]]}
		"shell_loop":
			var base_r := Vector3(14, 12, 34)
			var base_p := Vector3(0.01, 0.01, 0.01)
			return {"duration": def.reload_shell,
				"pose": [[0.0, base_p, base_r], [0.55, base_p + Vector3(0, 0.006, 0), base_r + Vector3(-2, 0, 1)], [0.7, base_p + Vector3(0, -0.004, 0), base_r + Vector3(1, 0, -1)], [1.0, base_p, base_r]],
				"mag": [[0.0, Vector3(-0.02, -0.12, 0.05), Vector3(-20, 0, 0)], [0.45, Vector3(0, -0.02, 0.0), Z], [0.62, Vector3(0, 0.0, -0.04), Z], [1.0, Vector3(0, 0.0, -0.04), Z]],
				"shell_vis": [[0.0, true], [0.62, false]],
				"left": [[0.0, 1.0], [0.7, 1.0], [1.0, 0.8]],
				"events": [[0.55, "shotgun_shell"], [0.6, "shell"]]}
		"shell_end", "shell_end_pump":
			var pump := n == "shell_end_pump"
			var c2 := {"duration": 0.3 if not pump else 0.62,
				"pose": [[0.0, Vector3(0.01, 0.01, 0.01), Vector3(14, 12, 34)], [0.5 if pump else 1.0, Z, Z], [1.0, Z, Z]],
				"left": [[0.0, 0.6], [0.4, 0.0]], "events": []}
			if pump:
				c2.pump = [[0.0, Z, Z], [0.5, Z, Z], [0.7, Vector3(0, 0, 0.075), Z], [0.9, Z, Z], [1.0, Z, Z]]
				c2.pose.insert(2, [0.72, Vector3(0, -0.01, 0.02), Vector3(-6, 0, -3)])
				c2.events = [[0.52, "shotgun_pump"], [0.7, "eject"], [0.95, "cycled"]]
			return c2
		"pump":
			return {"duration": 0.58,
				"pose": [[0.0, Z, Z], [0.15, Vector3(0, -0.006, 0.01), Vector3(4, 2, 6)], [0.45, Vector3(0, -0.018, 0.03), Vector3(-7, 3, 8)], [0.75, Vector3(0, -0.004, 0.0), Vector3(2, 0, 2)], [1.0, Z, Z]],
				"pump": [[0.0, Z, Z], [0.18, Z, Z], [0.45, Vector3(0, 0, 0.08), Z], [0.75, Z, Z], [1.0, Z, Z]],
				"events": [[0.18, "shotgun_pump"], [0.45, "eject"], [0.8, "cycled"]]}
		"bolt":
			return {"duration": 0.95,
				"pose": [[0.0, Z, Z], [0.2, Vector3(0.01, -0.03, 0.03), Vector3(6, 8, 22)], [0.75, Vector3(0.01, -0.03, 0.03), Vector3(6, 8, 22)], [1.0, Z, Z]],
				"bolt": [[0.0, Z, Z], [0.22, Z, Z], [0.35, Z, Vector3(0, 0, 60)], [0.5, Vector3(0, 0, 0.09), Vector3(0, 0, 60)], [0.65, Z, Vector3(0, 0, 60)], [0.78, Z, Z], [1.0, Z, Z]],
				"left": [],
				"events": [[0.22, "sniper_bolt"], [0.5, "eject"], [0.85, "cycled"]]}
	return {"duration": 0.1}


func _sniper_reload(dur: float) -> Dictionary:
	var Z := Vector3.ZERO
	var tilt := Vector3(12, 14, 30)
	var p := Vector3(0.02, -0.02, 0.02)
	return {"duration": dur,
		"pose": [[0.0, Z, Z], [0.12, p, tilt], [0.85, p, tilt], [1.0, Z, Z]],
		"bolt": [[0.0, Z, Z], [0.1, Z, Z], [0.16, Z, Vector3(0, 0, 60)], [0.24, Vector3(0, 0, 0.09), Vector3(0, 0, 60)], [0.7, Vector3(0, 0, 0.09), Vector3(0, 0, 60)], [0.78, Z, Vector3(0, 0, 60)], [0.84, Z, Z], [1.0, Z, Z]],
		"mag": [[0.0, Vector3(0, 0.12, 0.0), Z], [0.3, Vector3(0, 0.12, 0), Z], [0.45, Vector3(0, 0.06, 0), Z], [0.62, Vector3(0, 0.0, 0), Z], [1.0, Z, Z]],
		"mag_vis": [[0.0, true]],
		"shell_vis": [[0.0, false], [0.3, true], [0.64, false]],
		"left": [[0.0, 0.0], [0.28, 1.0], [0.64, 1.0], [0.72, 0.0]],
		"events": [[0.1, "sniper_bolt"], [0.5, "mag_in"], [0.62, "ammo"], [0.66, "mag_tap"], [0.76, "bolt_release"], [0.84, "cycled"]]}
