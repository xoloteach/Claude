class_name WeaponManager
extends Node3D
## First-person weapon handling: input, firing (hitscan), viewmodel motion (ADS, sway, bob, sprint poses,
## recoil springs, wall pull-back), switching, and FP arms.

var player: Node   # Player
var camera: Camera3D
var weapons: Array[Weapon] = []
var current := 0
var view_root: Node3D
var arms: ViewmodelArms
var weapon: Weapon

var ads_t := 0.0            # 0 hip .. 1 fully aimed (eased)
var _ads_raw := 0.0
var spread := 0.0           # current cone half-angle (deg) for crosshair
var bloom := 0.0
var _next_fire := 0.0
var _time := 0.0
var _trigger_was_down := false
var _burst_count := 0
var _shots_in_burst := 0
var _equip_t := 1.0          # 0 lowered .. 1 raised
var _switch_to := -1
var _sprint_block := 0.0     # time until can fire after sprint
var _last_shot_time := -10.0
var _fire_anim_t := 1.0

var _kick_pos := Spring3.new(420.0, 26.0)
var _kick_rot := Spring3.new(380.0, 22.0)
var _sway_rot := Spring3.new(140.0, 16.0)
var _sway_pos := Spring3.new(160.0, 18.0)
var _move_pos := Spring3.new(90.0, 14.0)
var _land := Spring3.new(160.0, 12.0)
var _pose_pos := Vector3.ZERO
var _pose_rot := Vector3.ZERO
var _wall_t := 0.0
var _look_accum := Vector2.ZERO
var _ray_q := PhysicsRayQueryParameters3D.new()


func setup(p: Node, cam: Camera3D) -> void:
	player = p
	camera = cam
	view_root = Node3D.new()
	view_root.name = "ViewRoot"
	add_child(view_root)
	arms = ViewmodelArms.new()
	arms.name = "Arms"
	view_root.add_child(arms)
	for id in WeaponDefs.ORDER:
		var w := Weapon.new()
		w.setup(id)
		w.visible = false
		w.clip_event.connect(_on_clip_event)
		view_root.add_child(w)
		weapons.append(w)
	_set_arm_layers(arms)
	_equip(0, true)


func _set_arm_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 2
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_arm_layers(c)


func _equip(idx: int, instant := false) -> void:
	if weapon:
		weapon.interrupt()
		weapon.visible = false
	current = idx
	weapon = weapons[idx]
	weapon.visible = true
	arms.target_r = weapon.grip_r
	arms.target_l = weapon.grip_l
	arms.left_override = weapon.mag_node
	_equip_t = 1.0 if instant else 0.0
	_switch_to = -1
	_next_fire = maxf(_next_fire, _time + (0.0 if instant else weapon.def.equip * 0.8))
	if not instant:
		Audio.play("weapon_raise", -6.0)
	Game.weapon_changed.emit(weapon.def)
	_emit_ammo()


func select(idx: int) -> void:
	if idx < 0 or idx >= weapons.size() or idx == current or _switch_to >= 0:
		return
	_switch_to = idx
	weapon.interrupt()
	Audio.play("weapon_lower", -8.0)

func cycle(dir: int) -> void:
	select(posmod(current + dir, weapons.size()))

func _emit_ammo() -> void:
	Game.ammo_changed.emit(weapon.ammo, weapon.reserve, weapon.def.mag)

func refill_all(fraction := 1.0) -> void:
	for w in weapons:
		w.reserve = maxi(w.reserve, int(w.def.reserve * fraction))
	_emit_ammo()

func add_look(delta_px: Vector2) -> void:
	_look_accum += delta_px


func is_aiming() -> bool:
	return _ads_raw > 0.5

func is_reloading() -> bool:
	return weapon != null and (weapon.clip_name.begins_with("reload") or weapon.shell_reload_active)

func wants_block_sprint() -> bool:
	# firing or aiming cancels sprint (like CoD)
	return Input.is_action_pressed("ads") or (Input.is_action_pressed("fire") and weapon.ammo > 0 and _time - _last_shot_time < 0.2)


# ------------------------------------------------------------------ main update
func tick(delta: float, ctx: Dictionary) -> void:
	_time += delta
	if weapon == null:
		return
	var sprinting: bool = ctx.sprinting
	var input_enabled: bool = ctx.get("input", true)

	# ---- weapon switching (lower -> swap -> raise)
	if _switch_to >= 0:
		_equip_t = maxf(0.0, _equip_t - delta / 0.18)
		if _equip_t <= 0.0:
			_equip(_switch_to)
	else:
		_equip_t = minf(1.0, _equip_t + delta / maxf(weapon.def.equip, 0.05))

	# ---- ADS
	var want_ads: bool = input_enabled and Input.is_action_pressed("ads") and not sprinting and not ctx.get("mantling", false) and _switch_to < 0
	if weapon.def.mode == "bolt" and weapon.is_busy() and weapon.clip_name != "":
		want_ads = want_ads and weapon.clip_name == "bolt" and false
	var prev_ads := _ads_raw
	_ads_raw = move_toward(_ads_raw, 1.0 if want_ads else 0.0, delta / weapon.def.ads_time)
	if prev_ads < 0.05 and _ads_raw >= 0.05:
		Audio.play("ads_in", -10.0)
	elif prev_ads > 0.95 and _ads_raw <= 0.95:
		Audio.play("ads_out", -12.0)
	ads_t = _ads_raw * _ads_raw * (3.0 - 2.0 * _ads_raw)

	# ---- sprint-out delay
	if sprinting:
		_sprint_block = weapon.def.sprint_to_fire
	else:
		_sprint_block = maxf(0.0, _sprint_block - delta)

	# ---- reload input
	if input_enabled and Input.is_action_just_pressed("reload") and weapon.can_reload() and _switch_to < 0:
		weapon.start_reload()
		player.on_reload_started()
	if weapon.ammo == 0 and weapon.reserve > 0 and not weapon.is_busy() and _time - _last_shot_time > 0.25 and _switch_to < 0 and not Input.is_action_pressed("fire"):
		weapon.start_reload()   # auto reload

	# ---- firing
	var trigger := input_enabled and Input.is_action_pressed("fire")
	var just := trigger and not _trigger_was_down
	_trigger_was_down = trigger
	if weapon.shell_reload_active and just and weapon.ammo > 0:
		weapon.cancel_shell_reload()
	if trigger and _equip_t > 0.85 and _switch_to < 0 and _sprint_block <= 0.0 and not ctx.get("mantling", false):
		if weapon.ammo <= 0 and just and not weapon.is_busy():
			Audio.play("dry_fire", -4.0)
			if weapon.reserve > 0:
				weapon.start_reload()
		elif weapon.can_fire() and not (weapon.shell_reload_active):
			var mode: String = weapon.def.mode
			var interval := 60.0 / float(weapon.def.rpm)
			if mode == "auto":
				if _time >= _next_fire:
					if _time - _next_fire > interval:
						_next_fire = _time
					_fire(ctx)
					_next_fire += interval
			elif just and _time >= _next_fire:
				_fire(ctx)
				_next_fire = _time + interval

	weapon.update_anim(delta)
	_update_spread(delta, ctx)
	_update_viewmodel(delta, ctx)


func _update_spread(delta: float, ctx: Dictionary) -> void:
	var d := weapon.def
	var s: float = lerpf(d.hip_spread, d.ads_spread, ads_t)
	var mv: float = ctx.speed_ratio
	s += d.move_spread * mv * (1.0 - ads_t * 0.85)
	if not ctx.grounded:
		s += d.air_spread * (1.0 - ads_t * 0.5)
	if ctx.crouching:
		s *= 0.8
	bloom = move_toward(bloom, 0.0, delta * 6.0)
	s += bloom * (1.0 - ads_t * 0.9)
	spread = lerpf(spread, s, minf(1.0, delta * 18.0))


# ------------------------------------------------------------------ firing
func _fire(ctx: Dictionary) -> void:
	var d := weapon.def
	weapon.ammo -= 1
	_last_shot_time = _time
	Game.shots_fired += 1
	_emit_ammo()
	# audio
	Audio.play(d.sound, -1.0 if not d.get("suppressed", false) else -4.0, 0.035)
	if weapon.ammo <= 3 and d.mag > 8 and d.mode == "auto":
		Audio.play("dry_fire", -20.0 + weapon.ammo * -2.0, 0.1)   # low-ammo mechanical tick
	# hitscan pellets
	var cam_xf := camera.global_transform
	var origin := cam_xf.origin
	var fwd := -cam_xf.basis.z
	var pellets: int = d.pellets
	var hit_any := false
	var result_kind := ""
	var total_damage := 0.0
	var muzzle_pos := weapon.muzzle.global_position if weapon.muzzle else origin
	for i in pellets:
		var cone: float = spread
		if pellets > 1:
			cone = d.pellet_spread * (1.0 - ads_t * 0.25) + spread * 0.3
		var dir := _cone_dir(cam_xf.basis, cone)
		var res := _trace(origin, dir, 350.0)
		var end_pos: Vector3 = res.get("position", origin + dir * 350.0)
		if not res.is_empty():
			var r := _apply_hit(res, origin, dir, d)
			if r.kind != "":
				hit_any = true
				total_damage += r.damage
				if _kind_rank(r.kind) > _kind_rank(result_kind):
					result_kind = r.kind
		var tr_every: int = d.tracer_every
		if pellets > 1:
			if i % 3 == 0:
				FX.tracer(muzzle_pos, end_pos, 0.6)
		elif tr_every <= 1 or (Game.shots_fired % tr_every) == 0:
			FX.tracer(muzzle_pos, end_pos, 1.0)
	if hit_any:
		Game.shots_hit += 1
		Game.hit_confirmed.emit(result_kind, total_damage)
	# muzzle fx
	if weapon.muzzle:
		FX.muzzle_flash(weapon.muzzle, d.flash_scale, d.get("suppressed", false))
	if d.mode != "pump" and d.mode != "bolt":
		_eject_shell()
	# recoil: camera (aim) + viewmodel kick
	var adsr: float = lerpf(1.0, d.ads_recoil, ads_t)
	var crouch_m := 0.85 if ctx.crouching else 1.0
	var v: float = d.recoil_v * randf_range(0.85, 1.15) * adsr * crouch_m
	var h: float = (d.recoil_h_bias + randf_range(-d.recoil_h, d.recoil_h)) * adsr * crouch_m
	player.add_recoil(v, h, d.recoil_recover)
	player.add_trauma(d.shake * (1.0 - ads_t * 0.5))
	var kb: float = d.kick_back * (1.0 - ads_t * 0.45)
	_kick_pos.impulse(Vector3(randf_range(-0.2, 0.2) * kb, kb * 0.25, kb) * 60.0)
	_kick_rot.impulse(Vector3(d.kick_up * (1.0 - ads_t * 0.55), randf_range(-d.kick_side, d.kick_side), randf_range(-d.kick_roll, d.kick_roll)) * 60.0)
	bloom = minf(bloom + (0.5 if pellets == 1 else 1.5), 4.0)
	_fire_anim_t = 0.0
	# slide / pump / bolt
	if weapon.slide_node:
		weapon.slide_node.transform = weapon.slide_node.transform.translated_local(Vector3(0, 0, 0.03))
		if weapon.ammo == 0:
			weapon.slide_locked = true
	if d.mode == "pump" and weapon.ammo >= 0:
		weapon.needs_cycle = true
		_delayed_clip("pump", 0.16)
	elif d.mode == "bolt":
		weapon.needs_cycle = true
		_delayed_clip("bolt", 0.3)
	# alert enemies
	if player.has_method("make_noise"):
		player.make_noise(45.0 if not d.get("suppressed", false) else 18.0)


func _delayed_clip(n: String, delay: float) -> void:
	var w := weapon
	await get_tree().create_timer(delay, false).timeout
	if is_instance_valid(w) and w == weapon and w.needs_cycle and not w.is_busy():
		w.play_clip(n)


func _kind_rank(k: String) -> int:
	return {"": 0, "hit": 1, "armor": 1, "head": 2, "kill": 3, "headkill": 4}.get(k, 0)


func _cone_dir(basis: Basis, half_angle_deg: float) -> Vector3:
	if half_angle_deg <= 0.001:
		return -basis.z
	# gaussian-ish distribution inside cone (more shots near center)
	var r := deg_to_rad(half_angle_deg) * sqrt(randf()) * (0.5 + 0.5 * randf())
	var a := randf() * TAU
	var local := Vector3(sin(r) * cos(a), sin(r) * sin(a), -cos(r))
	return (basis * local).normalized()


func _trace(origin: Vector3, dir: Vector3, dist: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	_ray_q.from = origin
	_ray_q.to = origin + dir * dist
	_ray_q.collision_mask = Game.L_WORLD | Game.L_HITBOX | Game.L_PROPS
	_ray_q.collide_with_areas = true
	_ray_q.collide_with_bodies = true
	_ray_q.exclude = [player.get_rid()]
	_ray_q.hit_from_inside = false
	return space.intersect_ray(_ray_q)


func _apply_hit(res: Dictionary, origin: Vector3, dir: Vector3, d: Dictionary) -> Dictionary:
	var col: Object = res.collider
	var pos: Vector3 = res.position
	var nrm: Vector3 = res.normal
	var dist := origin.distance_to(pos)
	var fall := clampf(inverse_lerp(d.range_start, d.range_end, dist), 0.0, 1.0)
	var dmg: float = lerpf(d.damage, d.damage_min, fall)
	if col and col.has_meta("hitbox"):
		var enemy = col.get_meta("enemy")
		var zone: String = col.get_meta("zone", "body")
		var mult := 1.0
		if zone == "head":
			mult = d.head_mult
		elif zone == "limb":
			mult = d.limb_mult
		if enemy and is_instance_valid(enemy) and enemy.has_method("take_damage"):
			var r: Dictionary = enemy.take_damage(dmg * mult, {"zone": zone, "pos": pos, "dir": dir, "normal": nrm, "weapon": d.name, "attacker": player})
			FX.blood(pos, nrm, dir)
			var kind := "hit"
			if r.get("killed", false):
				kind = "headkill" if zone == "head" else "kill"
			elif zone == "head":
				kind = "head"
			return {"kind": kind, "damage": dmg * mult}
		return {"kind": "", "damage": 0.0}
	var surface := "concrete"
	if col and col.has_meta("surface"):
		surface = col.get_meta("surface")
	FX.impact(pos, nrm, surface, dir)
	if col and col.has_method("take_damage"):
		col.take_damage(dmg, {"pos": pos, "dir": dir, "attacker": player})
	if col is RigidBody3D:
		(col as RigidBody3D).apply_impulse(dir * dmg * 0.04, pos - (col as RigidBody3D).global_position)
	return {"kind": "", "damage": 0.0}


func _eject_shell() -> void:
	if weapon.eject == null:
		return
	var b := weapon.eject.global_transform.basis
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var back := camera.global_basis.z
	var vel := right * randf_range(2.2, 3.2) + up * randf_range(1.2, 2.2) + back * randf_range(-0.3, 0.6)
	vel += player.velocity
	FX.shell(weapon.eject.global_position, vel, weapon.def.shell)


func _on_clip_event(w: Weapon, ev: String) -> void:
	if w != weapon:
		return
	match ev:
		"cloth": Audio.play("cloth", -12.0)
		"mag_out": Audio.play("mag_out", -4.0)
		"mag_in":
			Audio.play("mag_in", -3.0)
			_kick_rot.impulse(Vector3(-40, 0, 20))
		"mag_tap":
			Audio.play("mag_tap", -5.0)
			_kick_pos.impulse(Vector3(0, 0.25, 0))
		"bolt_release":
			Audio.play("bolt_release", -3.0)
			_kick_rot.impulse(Vector3(60, 20, -40))
		"slide_release":
			Audio.play("pistol_slide", -3.0)
			_kick_rot.impulse(Vector3(60, 0, 20))
		"shotgun_shell":
			Audio.play("shotgun_shell", -4.0)
			_kick_rot.impulse(Vector3(-25, 0, 10))
		"shotgun_pump":
			Audio.play("shotgun_pump", -2.0)
		"sniper_bolt":
			Audio.play("sniper_bolt", -2.0)
		"eject":
			_eject_shell()
		"ammo", "shell":
			_emit_ammo()
		"cycled":
			pass


# ------------------------------------------------------------------ viewmodel motion
func _update_viewmodel(delta: float, ctx: Dictionary) -> void:
	var d := weapon.def
	var aim := 1.0 - ads_t * 0.92
	# sway from look input (lag)
	var look: Vector2 = _look_accum
	_look_accum = Vector2.ZERO
	var lk := look / maxf(delta * 60.0, 0.5)
	_sway_rot.target = Vector3(clampf(-lk.y * 0.12, -6, 6), clampf(-lk.x * 0.12, -6, 6), clampf(-lk.x * 0.1, -5, 5)) * aim
	_sway_pos.target = Vector3(clampf(-lk.x * 0.0006, -0.015, 0.015), clampf(lk.y * 0.0006, -0.012, 0.012), 0.0) * aim
	_sway_rot.step(delta)
	_sway_pos.step(delta)
	# movement: strafe tilt, forward push, bob
	var lv: Vector3 = ctx.local_vel   # player-local velocity (x right, z back)
	var sprint_t: float = ctx.sprint_t
	var tac_t: float = ctx.tac_t
	var bob_phase: float = ctx.bob_phase
	var bob_amp: float = ctx.bob_amp * (1.0 - ads_t * 0.85)
	var bob := Vector3(sin(bob_phase) * 0.011, -absf(cos(bob_phase)) * 0.008, 0.0) * bob_amp
	var bob_rot := Vector3(-absf(cos(bob_phase)) * 1.2, sin(bob_phase) * 1.0, sin(bob_phase) * 1.6) * bob_amp
	_move_pos.target = Vector3(-lv.x * 0.0025, -absf(lv.z) * 0.001, lv.z * 0.0022) * aim
	_move_pos.step(delta)
	# idle breathing
	var br := Vector3(sin(_time * 1.3) * 0.0012, sin(_time * 2.1) * 0.0015, 0.0) * (1.0 - ads_t * 0.7)
	# landing / jump
	_land.target = Vector3.ZERO
	_land.step(delta)
	# poses: sprint / tac sprint / crouch / slide / reload / equip
	var sprint_pos := Vector3(-0.03, -0.04, 0.04)
	var sprint_rot := Vector3(-16, 42, -14)
	if weapon.id == "pistol":
		sprint_pos = Vector3(-0.02, -0.08, 0.06)
		sprint_rot = Vector3(-40, 10, -10)
	var tac_pos := Vector3(-0.02, 0.02, 0.06)
	var tac_rot := Vector3(58, 18, 22)
	var sprint_w := sprint_t * (1.0 - tac_t)
	var target_pos := sprint_pos * sprint_w + tac_pos * tac_t
	var target_rot := sprint_rot * sprint_w + tac_rot * tac_t
	if ctx.sliding:
		target_pos += Vector3(-0.02, 0.01, 0.01)
		target_rot += Vector3(4, 4, -18)
	elif ctx.crouching:
		target_pos += Vector3(0.0, -0.004, 0.005) * aim
		target_rot += Vector3(0, 0, -4) * aim
	if ctx.get("mantling", false):
		target_pos += Vector3(0.0, -0.12, 0.05)
		target_rot += Vector3(-30, 10, -10)
	_pose_pos = _pose_pos.lerp(target_pos, minf(1.0, delta * 9.0))
	_pose_rot = _pose_rot.lerp(target_rot, minf(1.0, delta * 9.0))
	var eq := 1.0 - _equip_t
	var eq_e := eq * eq
	var equip_pos := Vector3(0.0, -0.22, 0.06) * eq_e
	var equip_rot := Vector3(-35, 12, -20) * eq_e
	# wall pull-back
	var wall := _check_wall()
	_wall_t = lerpf(_wall_t, wall, minf(1.0, delta * 10.0))
	var wall_pos := Vector3(-0.02, -0.03, 0.14) * _wall_t
	var wall_rot := Vector3(-8, 30, -10) * _wall_t
	# kick springs
	_kick_pos.step(delta)
	_kick_rot.step(delta)
	# ADS position: align sight marker with camera center at ads_dist
	var sight_local: Vector3 = weapon.sight.position if weapon.sight else Vector3.ZERO
	var ads_pos := Vector3(0, 0, -d.ads_dist) - sight_local
	var base := (d.hip_pos as Vector3).lerp(ads_pos, ads_t)
	var reload_mul := 1.0 - ads_t
	var pos := base + bob + br * 1.0 + _sway_pos.value + _move_pos.value + _land.value + _pose_pos + equip_pos + wall_pos
	pos += weapon.anim_pos * (0.6 + 0.4 * reload_mul)
	pos += Vector3(0, 0, _kick_pos.value.z) + Vector3(_kick_pos.value.x, _kick_pos.value.y, 0) * (1.0 - ads_t * 0.6)
	var rot := bob_rot + _sway_rot.value + _pose_rot + equip_rot + wall_rot + weapon.anim_rot + _kick_rot.value * Vector3(1.0, 1.0, 1.0)
	rot.x += -lv.z * 0.0 + ctx.get("pitch_lag", 0.0)
	rot.z += -lv.x * 0.25 * aim   # strafe cant
	# rotate around a pivot near the grip so rotations look natural
	var pivot := Vector3(0, -0.02, 0.08)
	var basis := Basis.from_euler(rot * (PI / 180.0), EULER_ORDER_YXZ)
	var xf := Transform3D(basis, pos + pivot - basis * pivot)
	weapon.transform = xf
	# scope: hide weapon when fully scoped
	var scoped: bool = d.get("scope", false) and ads_t > 0.94
	view_root.visible = not scoped
	arms.left_override_w = weapon.left_hand_w
	arms.update_arms()


func _check_wall() -> float:
	var space := get_world_3d().direct_space_state
	var cam_xf := camera.global_transform
	var q := PhysicsRayQueryParameters3D.create(cam_xf.origin, cam_xf.origin - cam_xf.basis.z * 0.75 + cam_xf.basis.y * -0.1, Game.L_WORLD | Game.L_PROPS)
	q.exclude = [player.get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty():
		return 0.0
	var dd := cam_xf.origin.distance_to(r.position)
	return clampf(1.0 - (dd - 0.25) / 0.5, 0.0, 1.0) * (1.0 - ads_t * 0.7)


func land_impulse(strength: float) -> void:
	_land.impulse(Vector3(0, -strength * 0.25, 0))
	_kick_rot.impulse(Vector3(-strength * 18.0, 0, strength * 6.0))

func jump_impulse() -> void:
	_land.impulse(Vector3(0, -0.15, 0.05))
	_kick_rot.impulse(Vector3(-12, 0, 0))
