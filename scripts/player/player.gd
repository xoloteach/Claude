class_name Player
extends CharacterBody3D
## First-person player controller: walk / sprint / tactical sprint / crouch / slide / jump / mantle,
## camera (recoil, shake, bob, FOV), health regen, and input from mouse, gamepad, touch and web bridge.

const STAND_H := 1.8
const CROUCH_H := 1.15
const SLIDE_H := 0.95
const EYE_STAND := 1.64
const EYE_CROUCH := 1.08
const EYE_SLIDE := 0.8
const RADIUS := 0.34

const WALK := 5.0
const SPRINT := 7.1
const TAC_SPRINT := 8.6
const CROUCH := 2.7
const JUMP_V := 6.1
const GRAVITY := 19.0
const ACCEL := 52.0
const DECEL := 44.0
const AIR_ACCEL := 9.0
const TAC_TIME := 3.2
const TAC_COOLDOWN := 3.5
const SLIDE_TIME := 0.9
const MAX_HEALTH := 100.0

var head: Node3D
var cam_pivot: Node3D
var camera: Camera3D
var weapons: WeaponManager
var collider: CollisionShape3D
var capsule: CapsuleShape3D

var yaw := 0.0
var pitch := 0.0
var health := MAX_HEALTH
var alive := true
var god_mode := false
var input_enabled := true

var sprinting := false
var tac_sprinting := false
var tac_time_left := TAC_TIME
var tac_cooldown := 0.0
var crouching := false
var sliding := false
var slide_t := 0.0
var slide_dir := Vector3.ZERO
var slide_cooldown := 0.0
var mantling := false
var _mantle_from := Vector3.ZERO
var _mantle_mid := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_t := 0.0
var _mantle_dur := 0.4

var sprint_t := 0.0
var tac_t := 0.0
var bob_phase := 0.0
var bob_amp := 0.0
var _step_index := 0
var _eye_h := EYE_STAND
var _was_on_floor := true
var _air_time := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _fall_speed := 0.0
var _last_damage_time := -100.0
var _time := 0.0
var _mouse_ignore_frame := 0
var _last_mouse_mode := -1

# camera effects
var recoil_punch := Vector2.ZERO    # (pitch, yaw) degrees, recovers
var _recoil_recover := 10.0
var _last_recoil_time := -10.0
var trauma := 0.0
var _noise := FastNoiseLite.new()
var _cam_dip := Spring3.new(140.0, 13.0)
var _cam_roll := 0.0
var _flinch := Spring3.new(200.0, 16.0)
var _fov_current := 90.0

# aim assist
var _aa_target: Node3D = null
var _aa_slow := 1.0

signal died


func _ready() -> void:
	add_to_group("player")
	collision_layer = Game.L_PLAYER
	collision_mask = Game.L_WORLD | Game.L_PROPS | Game.L_ENEMY
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.3
	collider = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = STAND_H
	collider.shape = capsule
	collider.position.y = STAND_H * 0.5
	add_child(collider)
	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE_STAND
	add_child(head)
	cam_pivot = Node3D.new()
	cam_pivot.name = "CamPivot"
	head.add_child(cam_pivot)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.015
	camera.far = 600.0
	camera.current = true
	cam_pivot.add_child(camera)
	var listener := AudioListener3D.new()
	camera.add_child(listener)
	listener.make_current()
	weapons = WeaponManager.new()
	weapons.name = "Weapons"
	camera.add_child(weapons)
	weapons.setup(self, camera)
	_noise.seed = randi()
	_noise.frequency = 1.0
	_noise.fractal_octaves = 2
	Game.player = self
	_mouse_ignore_frame = Engine.get_process_frames() + 6
	_fov_current = Game.settings.fov
	yaw = rotation.y


func set_view_angles(yaw_deg: float, pitch_deg: float) -> void:
	yaw = deg_to_rad(yaw_deg)
	pitch = deg_to_rad(pitch_deg)


func select_weapon(i: int) -> void:
	weapons.select(i)


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if not alive or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# browsers emit a bogus large delta when pointer lock engages; ignore briefly + reject spikes
		if Engine.get_process_frames() < _mouse_ignore_frame or event.relative.length() > 600.0:
			return
		_apply_look(event.relative, Game.settings.sensitivity * 0.0022)
	if event.is_action_pressed("next_weapon"):
		weapons.cycle(1)
	elif event.is_action_pressed("prev_weapon"):
		weapons.cycle(-1)
	for i in 5:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			weapons.select(i)


func _apply_look(rel: Vector2, scale: float) -> void:
	var fov_ratio := 1.0
	if weapons.ads_t > 0.0:
		var ads_fov: float = weapons.weapon.def.ads_fov
		fov_ratio = lerpf(1.0, ads_fov * Game.settings.ads_sensitivity, weapons.ads_t)
	var s := scale * fov_ratio * _aa_slow
	var inv := -1.0 if Game.settings.invert_y else 1.0
	yaw -= rel.x * s
	pitch = clampf(pitch - rel.y * s * inv, deg_to_rad(-88.0), deg_to_rad(88.0))
	weapons.add_look(rel * fov_ratio)


func _process_stick_look(delta: float) -> void:
	var v := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if v.length() > 0.0:
		# response curve for fine aim
		var m := v.length()
		v = v.normalized() * pow(m, 1.8)
		var speed: float = deg_to_rad(230.0) * Game.settings.pad_sensitivity
		if m > 0.97:
			speed *= 1.35   # outer-ring acceleration
		var px_per_rad := 1.0 / 0.0022
		_apply_look(v * speed * delta * px_per_rad, 0.0022)
	# injected (touch / web bridge)
	if Game.injected_look != Vector2.ZERO:
		var mult: float = Game.settings.touch_sensitivity if Game.input_mode == "touch" else Game.settings.sensitivity
		_apply_look(Game.injected_look, 0.0022 * mult)
		Game.injected_look = Vector2.ZERO


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	_time += delta
	if not alive:
		velocity.y -= GRAVITY * delta
		velocity.x = move_toward(velocity.x, 0, 10 * delta)
		velocity.z = move_toward(velocity.z, 0, 10 * delta)
		move_and_slide()
		return
	if mantling:
		_update_mantle(delta)
		return
	var on_floor := is_on_floor()
	var in_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := basis_yaw * Vector3(in_dir.x, 0, in_dir.y)
	var fwd_amount := -in_dir.y

	# timers
	slide_cooldown = maxf(0.0, slide_cooldown - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if on_floor:
		_coyote = 0.12
	else:
		_coyote = maxf(0.0, _coyote - delta)
	if input_enabled and Input.is_action_just_pressed("jump"):
		_jump_buffer = 0.14

	# ---- sprint state
	var block_sprint := weapons.wants_block_sprint() or crouching and not sliding
	if input_enabled and Input.is_action_just_pressed("sprint") and fwd_amount > 0.3:
		if sprinting and not tac_sprinting and tac_cooldown <= 0.0 and tac_time_left > 0.5:
			tac_sprinting = true
		elif not sprinting:
			sprinting = true
			if crouching and not sliding:
				_try_stand()
	if fwd_amount < 0.3 or block_sprint or sliding:
		if sprinting and tac_sprinting:
			tac_cooldown = TAC_COOLDOWN * (1.0 - tac_time_left / TAC_TIME) + 0.5
		sprinting = false
		tac_sprinting = false
	if tac_sprinting:
		tac_time_left -= delta
		if tac_time_left <= 0.0:
			tac_sprinting = false
			tac_cooldown = TAC_COOLDOWN
	else:
		tac_cooldown = maxf(0.0, tac_cooldown - delta)
		if tac_cooldown <= 0.0:
			tac_time_left = minf(TAC_TIME, tac_time_left + delta * 1.5)

	# ---- crouch / slide
	if input_enabled and Input.is_action_just_pressed("crouch"):
		var hs := Vector2(velocity.x, velocity.z).length()
		if on_floor and sprinting and hs > 5.5 and slide_cooldown <= 0.0 and not sliding:
			_start_slide()
		elif sliding:
			_end_slide(true)
		elif crouching:
			_try_stand()
		else:
			crouching = true
	if sliding:
		slide_t += delta
		var hs2 := Vector2(velocity.x, velocity.z).length()
		if slide_t > SLIDE_TIME or hs2 < 3.2 or not on_floor and slide_t > 0.25:
			_end_slide(false)

	# ---- mantle / jump
	if _jump_buffer > 0.0 and input_enabled:
		if _try_mantle():
			_jump_buffer = 0.0
			return
		if _coyote > 0.0:
			if crouching and not sliding:
				_try_stand()
			else:
				_jump()
			_jump_buffer = 0.0
	elif not on_floor and input_enabled and Input.is_action_pressed("jump") and fwd_amount > 0.2 and velocity.y < 2.0:
		if _try_mantle():
			return

	# ---- horizontal movement
	var target_speed := WALK
	if sprinting:
		target_speed = TAC_SPRINT if tac_sprinting else SPRINT
	elif crouching:
		target_speed = CROUCH
	if weapons.ads_t > 0.0:
		target_speed *= lerpf(1.0, weapons.weapon.def.ads_move, weapons.ads_t)
	if in_dir.y > 0.1:  # backpedal slower
		target_speed *= 0.85
	var hv := Vector3(velocity.x, 0, velocity.z)
	if sliding:
		# slide friction; slight steering
		var fr := lerpf(3.0, 9.0, slide_t / SLIDE_TIME)
		hv = hv.move_toward(Vector3.ZERO, fr * delta)
		if wish.length() > 0.1:
			var steer := hv.length()
			hv = hv.lerp(wish.normalized() * steer, delta * 1.5)
		# slope boost
		var fn := get_floor_normal()
		if on_floor and fn.y < 0.98:
			hv += Vector3(fn.x, 0, fn.z) * 9.0 * delta
	elif on_floor:
		var target := wish * target_speed
		var rate := ACCEL if target.length() > hv.length() * 0.9 else DECEL
		hv = hv.move_toward(target, rate * delta)
	else:
		var target_air := wish * maxf(target_speed, hv.length())
		hv = hv.move_toward(target_air, AIR_ACCEL * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if not on_floor:
		velocity.y -= GRAVITY * delta
		_fall_speed = minf(_fall_speed, velocity.y)
		_air_time += delta
	move_and_slide()

	# ---- landing
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		_on_land(-_fall_speed)
		_fall_speed = 0.0
		_air_time = 0.0
	_was_on_floor = now_floor

	# ---- capsule / eye height
	var eye_target := EYE_STAND
	var h_target := STAND_H
	if sliding:
		eye_target = EYE_SLIDE
		h_target = SLIDE_H
	elif crouching:
		eye_target = EYE_CROUCH
		h_target = CROUCH_H
	capsule.height = move_toward(capsule.height, h_target, delta * 6.0)
	collider.position.y = capsule.height * 0.5
	_eye_h = lerpf(_eye_h, eye_target, minf(1.0, delta * (14.0 if sliding else 10.0)))

	# ---- health regen
	if health < MAX_HEALTH and _time - _last_damage_time > 3.6:
		health = minf(MAX_HEALTH, health + 34.0 * delta)


func _process(delta: float) -> void:
	var mm := Input.mouse_mode
	if mm != _last_mouse_mode:
		_last_mouse_mode = mm
		if mm == Input.MOUSE_MODE_CAPTURED:
			_mouse_ignore_frame = Engine.get_process_frames() + 6
	if alive and input_enabled:
		_process_stick_look(delta)
		_update_aim_assist(delta)
	# ---- recoil punch recovery
	if _time - _last_recoil_time > 0.06:
		recoil_punch = recoil_punch.lerp(Vector2.ZERO, minf(1.0, delta * _recoil_recover))
	trauma = maxf(0.0, trauma - delta * 1.8)
	rotation.y = yaw
	head.rotation.x = pitch
	head.position.y = _eye_h
	# ---- bob
	var hs := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor() and not sliding
	var stride := 2.3 if not sprinting else (2.9 if not tac_sprinting else 3.2)
	if crouching: stride = 1.6
	if grounded and hs > 0.5:
		bob_phase += hs / stride * PI * delta
		bob_amp = lerpf(bob_amp, clampf(hs / WALK, 0.0, 1.8), minf(1.0, delta * 8.0))
		var idx := int(floor(bob_phase / PI))
		if idx != _step_index:
			_step_index = idx
			_footstep(hs)
	else:
		bob_amp = lerpf(bob_amp, 0.0, minf(1.0, delta * 6.0))
	sprint_t = move_toward(sprint_t, 1.0 if sprinting else 0.0, delta * 5.0)
	tac_t = move_toward(tac_t, 1.0 if tac_sprinting else 0.0, delta * 4.0)
	# ---- camera composition
	_cam_dip.step(delta)
	_flinch.step(delta)
	var shake := trauma * trauma
	var t := _time * 22.0
	var sp := Vector3(_noise.get_noise_2d(t, 0.0), _noise.get_noise_2d(0.0, t), _noise.get_noise_2d(t, t)) * shake
	var bob_y := sin(bob_phase * 2.0) * 0.018 * bob_amp * (1.0 - weapons.ads_t * 0.8)
	var bob_x := cos(bob_phase) * 0.012 * bob_amp * (1.0 - weapons.ads_t * 0.8)
	var target_roll := 0.0
	if sliding:
		target_roll = deg_to_rad(-5.0)
	var local_v := global_basis.inverse() * velocity
	target_roll += -local_v.x * deg_to_rad(0.18) * (1.0 - weapons.ads_t * 0.7)
	_cam_roll = lerpf(_cam_roll, target_roll, minf(1.0, delta * 8.0))
	cam_pivot.position = Vector3(bob_x, bob_y + _cam_dip.value.y, 0)
	cam_pivot.rotation = Vector3(
		deg_to_rad(recoil_punch.x + sp.x * 3.0 + _flinch.value.x),
		deg_to_rad(recoil_punch.y + sp.y * 3.0 + _flinch.value.y),
		_cam_roll + deg_to_rad(sp.z * 4.0 + _flinch.value.z + sin(bob_phase) * 0.35 * bob_amp * (1.0 - weapons.ads_t)))
	# ---- FOV (horizontal setting converted to vertical for 16:9)
	var base_h: float = Game.settings.fov
	var fov_mult := 1.0
	if sprinting:
		fov_mult += 0.04 + (0.05 if tac_sprinting else 0.0)
	if sliding:
		fov_mult += 0.06
	if weapons.weapon:
		fov_mult = lerpf(fov_mult, weapons.weapon.def.ads_fov, weapons.ads_t)
	var target_h := base_h * fov_mult
	_fov_current = lerpf(_fov_current, target_h, minf(1.0, delta * 12.0))
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_fov_current) * 0.5) * 9.0 / 16.0))
	# ---- weapons
	var ctx := {
		"sprinting": sprinting, "sprint_t": sprint_t, "tac_t": tac_t, "crouching": crouching, "sliding": sliding,
		"grounded": is_on_floor(), "speed_ratio": clampf(hs / WALK, 0.0, 1.5), "local_vel": local_v,
		"bob_phase": bob_phase, "bob_amp": bob_amp, "mantling": mantling, "input": alive and input_enabled,
	}
	weapons.tick(delta, ctx)


# ------------------------------------------------------------------ movement helpers
func _jump() -> void:
	var slide_jump := sliding
	if sliding:
		_end_slide(true)
	velocity.y = JUMP_V
	_coyote = 0.0
	_fall_speed = 0.0
	Audio.play("jump", -10.0)
	weapons.jump_impulse()
	if slide_jump:
		var hv := Vector3(velocity.x, 0, velocity.z)
		velocity.x = hv.x * 0.95
		velocity.z = hv.z * 0.95


func _start_slide() -> void:
	sliding = true
	crouching = true
	sprinting = false
	tac_sprinting = false
	slide_t = 0.0
	var hv := Vector3(velocity.x, 0, velocity.z)
	var dir := hv.normalized()
	var spd := maxf(hv.length() + 2.0, 9.6)
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	Audio.play("slide", -6.0)
	_cam_dip.impulse(Vector3(0, -0.6, 0))
	add_trauma(0.12)


func _end_slide(jumped: bool) -> void:
	sliding = false
	slide_cooldown = 0.35
	if jumped:
		crouching = false
		if not _can_stand():
			crouching = true


func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := CapsuleShape3D.new()
	s.radius = RADIUS * 0.9
	s.height = STAND_H - 0.1
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, STAND_H * 0.5 + 0.05, 0))
	q.collision_mask = Game.L_WORLD | Game.L_PROPS
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()


func _try_stand() -> void:
	if _can_stand():
		crouching = false


func _try_mantle() -> bool:
	var space := get_world_3d().direct_space_state
	var fwd := -Basis(Vector3.UP, yaw).z
	var feet := global_position
	# forward probe at knee and chest
	var hit_wall := false
	for h in [0.55, 1.0, 1.5]:
		var q := PhysicsRayQueryParameters3D.create(feet + Vector3(0, h, 0), feet + Vector3(0, h, 0) + fwd * (RADIUS + 0.55), Game.L_WORLD | Game.L_PROPS)
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			hit_wall = true
			break
	if not hit_wall:
		return false
	# find ledge top
	var probe := feet + fwd * (RADIUS + 0.45) + Vector3(0, 2.3, 0)
	var q2 := PhysicsRayQueryParameters3D.create(probe, probe + Vector3(0, -2.2, 0), Game.L_WORLD | Game.L_PROPS)
	q2.exclude = [get_rid()]
	var top := space.intersect_ray(q2)
	if top.is_empty():
		return false
	var ledge_h: float = top.position.y - feet.y
	if ledge_h < 0.45 or ledge_h > 2.05 or top.normal.y < 0.7:
		return false
	# check clearance on top (crouch height at least)
	var qs := PhysicsShapeQueryParameters3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = RADIUS * 0.9
	cs.height = CROUCH_H
	qs.shape = cs
	var dest: Vector3 = top.position + Vector3(0, 0.02, 0)
	qs.transform = Transform3D(Basis.IDENTITY, dest + Vector3(0, CROUCH_H * 0.5 + 0.05, 0))
	qs.collision_mask = Game.L_WORLD | Game.L_PROPS
	if not space.intersect_shape(qs, 1).is_empty():
		return false
	mantling = true
	sliding = false
	sprinting = false
	tac_sprinting = false
	_mantle_from = global_position
	_mantle_to = dest
	_mantle_mid = Vector3(_mantle_from.x, dest.y + 0.08, _mantle_from.z)
	_mantle_dur = lerpf(0.28, 0.55, clampf((ledge_h - 0.45) / 1.6, 0.0, 1.0))
	_mantle_t = 0.0
	velocity = Vector3.ZERO
	Audio.play("cloth", -6.0)
	Audio.play("land", -12.0)
	_cam_dip.impulse(Vector3(0, -0.3, 0))
	if not _can_stand_at(dest):
		crouching = true
	return true


func _can_stand_at(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := CapsuleShape3D.new()
	s.radius = RADIUS * 0.9
	s.height = STAND_H - 0.1
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, STAND_H * 0.5 + 0.05, 0))
	q.collision_mask = Game.L_WORLD | Game.L_PROPS
	return space.intersect_shape(q, 1).is_empty()


func _update_mantle(delta: float) -> void:
	_mantle_t += delta / _mantle_dur
	var t := clampf(_mantle_t, 0.0, 1.0)
	var up_t := clampf(t / 0.6, 0.0, 1.0)
	var fw_t := clampf((t - 0.35) / 0.65, 0.0, 1.0)
	up_t = 1.0 - pow(1.0 - up_t, 2.0)
	fw_t = fw_t * fw_t * (3.0 - 2.0 * fw_t)
	var p := _mantle_from
	p.y = lerpf(_mantle_from.y, _mantle_mid.y, up_t)
	p.x = lerpf(_mantle_from.x, _mantle_to.x, fw_t)
	p.z = lerpf(_mantle_from.z, _mantle_to.z, fw_t)
	global_position = p
	_cam_roll = lerpf(_cam_roll, deg_to_rad(3.0) * sin(t * PI), 0.3)
	if _mantle_t >= 1.0:
		mantling = false
		global_position = _mantle_to
		var fwd := -Basis(Vector3.UP, yaw).z
		velocity = fwd * 2.5
		_was_on_floor = true
		Audio.play("footstep_concrete", -8.0)


func _on_land(impact: float) -> void:
	if impact < 2.5:
		return
	var s := clampf((impact - 2.5) / 9.0, 0.0, 1.0)
	_cam_dip.impulse(Vector3(0, -0.6 - s * 2.2, 0))
	weapons.land_impulse(0.3 + s)
	Audio.play("land", -8.0 + s * 6.0)
	if s > 0.35:
		add_trauma(0.25 * s)
	_step_index = int(floor(bob_phase / PI))


func _surface_below() -> String:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, -0.4, 0), Game.L_WORLD | Game.L_PROPS)
	q.exclude = [get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty():
		return "concrete"
	var c: Object = r.collider
	return c.get_meta("surface", "concrete") if c else "concrete"


func _footstep(speed: float) -> void:
	var surf := _surface_below()
	var base := "footstep_metal" if surf == "metal" else "footstep_concrete"
	var vol := -14.0
	if sprinting: vol = -9.0
	if tac_sprinting: vol = -7.0
	if crouching: vol = -22.0
	Audio.play(base, vol, 0.08)
	if sprinting and randf() < 0.5:
		Audio.play("cloth", vol - 8.0)
	if not crouching:
		make_noise(12.0 if not sprinting else 20.0)


# ------------------------------------------------------------------ combat hooks
func add_recoil(vertical_deg: float, horizontal_deg: float, recover: float) -> void:
	# part of recoil moves the aim permanently (must be compensated), part is punch that recovers
	pitch = clampf(pitch + deg_to_rad(vertical_deg * 0.55), deg_to_rad(-88.0), deg_to_rad(88.0))
	yaw -= deg_to_rad(horizontal_deg * 0.6)
	recoil_punch += Vector2(vertical_deg * 0.45, -horizontal_deg * 0.4)
	recoil_punch.x = minf(recoil_punch.x, 6.0)
	_recoil_recover = recover
	_last_recoil_time = _time


func add_trauma(a: float) -> void:
	trauma = clampf(trauma + a, 0.0, 1.0)


func on_reload_started() -> void:
	pass


func make_noise(radius: float) -> void:
	get_tree().call_group("enemy", "hear_noise", global_position, radius)


func take_damage(amount: float, from_pos: Vector3 = Vector3.ZERO) -> void:
	if not alive or god_mode:
		Game.player_hurt.emit(from_pos, 0.0)
		return
	health -= amount
	_last_damage_time = _time
	Game.player_hurt.emit(from_pos, amount)
	Audio.play("player_hurt", -4.0)
	var to := (from_pos - global_position)
	var local := global_basis.inverse() * to
	_flinch.impulse(Vector3(-2.5, signf(local.x) * 3.0, -signf(local.x) * 4.0) * clampf(amount / 20.0, 0.4, 1.5) * 10.0)
	add_trauma(0.18)
	if health <= 0.0:
		_die()


func _die() -> void:
	alive = false
	health = 0.0
	Audio.play("death", 0.0)
	weapons.visible = false
	var t := create_tween()
	t.tween_property(self, "_eye_h", 0.35, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "_cam_roll", deg_to_rad(70.0), 0.8)
	died.emit()
	Game.end_run()


func heal_full() -> void:
	health = MAX_HEALTH


func health_ratio() -> float:
	return health / MAX_HEALTH


func time_since_damage() -> float:
	return _time - _last_damage_time


# ------------------------------------------------------------------ aim assist (gamepad / touch)
func _update_aim_assist(delta: float) -> void:
	_aa_slow = 1.0
	if not Game.settings.aim_assist or Game.input_mode == "kbm":
		return
	var cam_xf := camera.global_transform
	var fwd := -cam_xf.basis.z
	var best: Node3D = null
	var best_ang := deg_to_rad(5.5 if weapons.ads_t > 0.5 else 3.5)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e.has_method("aim_point") or not e.get("alive"):
			continue
		var p: Vector3 = e.aim_point()
		var to := p - cam_xf.origin
		var dist := to.length()
		if dist > 70.0:
			continue
		var ang := fwd.angle_to(to / dist)
		if ang < best_ang:
			best_ang = ang
			best = e
	if best:
		_aa_slow = 0.55
		# gentle rotational pull when aiming
		if weapons.ads_t > 0.3:
			var p2: Vector3 = best.aim_point()
			var local := camera.global_basis.inverse() * (p2 - cam_xf.origin)
			var yaw_err := atan2(-local.x, -local.z)
			var pitch_err := atan2(local.y, -local.z)
			yaw += yaw_err * minf(1.0, delta * 4.0)
			pitch += pitch_err * minf(1.0, delta * 4.0)


func debug_state() -> Dictionary:
	return {
		"pos": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
		"yaw": snappedf(rad_to_deg(yaw), 0.1), "pitch": snappedf(rad_to_deg(pitch), 0.1),
		"health": health, "weapon": weapons.weapon.id if weapons.weapon else "",
		"ammo": weapons.weapon.ammo if weapons.weapon else 0, "reserve": weapons.weapon.reserve if weapons.weapon else 0,
		"ads": snappedf(weapons.ads_t, 0.01), "sprint": sprinting, "tac": tac_sprinting, "crouch": crouching,
		"slide": sliding, "mantle": mantling, "on_floor": is_on_floor(), "speed": snappedf(Vector2(velocity.x, velocity.z).length(), 0.01),
		"reloading": weapons.is_reloading(),
	}
