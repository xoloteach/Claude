extends Node
## Pooled visual effects: muzzle flashes, tracers, impacts (decals + particles), blood, shell casings, explosions.

const FXDIR := "res://assets/textures/fx/"
const DECAL_MAX := 160
const SHELL_MAX := 40
const TRACER_MAX := 32

var _root: Node3D
var _decals: Array[MeshInstance3D] = []
var _decal_i := 0
var _decal_mats := {}
var _tracers: Array = []   # [MeshInstance3D, from, to, t, len, speed]
var _tracer_i := 0
var _shells: Array = []    # dict per shell
var _shell_i := 0
var _particles := {}       # type -> Array[CPUParticles3D]
var _particle_i := {}
var _lights: Array[OmniLight3D] = []
var _light_i := 0
var _flash_nodes := {}     # muzzle Marker3D -> flash Node3D
var quality := 2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_root = Node3D.new()
	_root.name = "FXRoot"
	add_child(_root)
	Game.settings_changed.connect(func(): quality = Game.settings.quality)
	quality = Game.settings.quality
	_build_pools()


func reset() -> void:
	for d in _decals:
		d.visible = false
	for s in _shells:
		s.node.visible = false
		s.alive = false
	for t in _tracers:
		t[0].visible = false


# ------------------------------------------------------------------ pools
func _sprite_mat(tex: String, color: Color, additive := false, lit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = MeshKit.tex(FXDIR + tex)
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _make_particles(kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	var q := QuadMesh.new()
	var grad := Gradient.new()
	match kind:
		"dust":
			p.amount = 10
			p.lifetime = 1.1
			q.size = Vector2(0.35, 0.35)
			q.material = _sprite_mat("smoke.png", Color(0.75, 0.72, 0.66, 0.55), false, true)
			p.direction = Vector3(0, 0, 1)
			p.spread = 35.0
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 2.4
			p.damping_min = 3.0
			p.damping_max = 5.0
			p.gravity = Vector3(0, 0.25, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.2
			var c := Curve.new()
			c.add_point(Vector2(0, 0.35)); c.add_point(Vector2(1, 1.8))
			p.scale_amount_curve = c
			grad.set_color(0, Color(1, 1, 1, 0.8)); grad.set_color(1, Color(1, 1, 1, 0.0))
			p.angle_min = -180; p.angle_max = 180
		"debris":
			p.amount = 10
			p.lifetime = 0.9
			var bm := BoxMesh.new()
			bm.size = Vector3(0.018, 0.012, 0.015)
			bm.material = MeshKit.flat(Color(0.5, 0.48, 0.45), 0.9)
			p.mesh = bm
			p.direction = Vector3(0, 0, 1)
			p.spread = 45.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 5.5
			p.gravity = Vector3(0, -12, 0)
			p.angular_velocity_min = -720; p.angular_velocity_max = 720
			p.particle_flag_rotate_y = true
			p.scale_amount_min = 0.5; p.scale_amount_max = 1.6
			grad.set_color(0, Color.WHITE); grad.set_color(1, Color.WHITE)
		"sparks":
			p.amount = 14
			p.lifetime = 0.38
			q.size = Vector2(0.05, 0.012)
			var sm := _sprite_mat("spark.png", Color(1.0, 0.75, 0.35, 1.0), true)
			sm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			sm.albedo_color = Color(4.0, 2.4, 0.9, 1.0)
			q.material = sm
			p.direction = Vector3(0, 0, 1)
			p.spread = 55.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 11.0
			p.gravity = Vector3(0, -14, 0)
			p.particle_flag_align_y = true
			q.size = Vector2(0.012, 0.09)
			p.scale_amount_min = 0.5; p.scale_amount_max = 1.3
			grad.set_color(0, Color(1, 1, 1, 1)); grad.set_color(1, Color(1, 0.4, 0.1, 0))
		"flash":
			p.amount = 1
			p.lifetime = 0.07
			q.size = Vector2(0.35, 0.35)
			q.material = _sprite_mat("impact_flash.png", Color(3.0, 2.2, 1.2, 1.0), true)
			p.initial_velocity_min = 0; p.initial_velocity_max = 0
			p.gravity = Vector3.ZERO
			p.angle_min = -180; p.angle_max = 180
			p.scale_amount_min = 0.6; p.scale_amount_max = 1.0
			grad.set_color(0, Color(1, 1, 1, 1)); grad.set_color(1, Color(1, 1, 1, 0))
		"blood":
			p.amount = 8
			p.lifetime = 0.55
			q.size = Vector2(0.3, 0.3)
			q.material = _sprite_mat("blood.png", Color(0.55, 0.03, 0.02, 0.95), false, true)
			p.direction = Vector3(0, 0, 1)
			p.spread = 30.0
			p.initial_velocity_min = 0.8; p.initial_velocity_max = 3.0
			p.damping_min = 4.0; p.damping_max = 6.0
			p.gravity = Vector3(0, -3.0, 0)
			var c2 := Curve.new()
			c2.add_point(Vector2(0, 0.4)); c2.add_point(Vector2(1, 1.6))
			p.scale_amount_curve = c2
			p.angle_min = -180; p.angle_max = 180
			grad.set_color(0, Color(1, 1, 1, 1)); grad.set_color(1, Color(1, 1, 1, 0))
		"muzzle_smoke":
			p.amount = 5
			p.lifetime = 0.9
			p.explosiveness = 0.8
			q.size = Vector2(0.18, 0.18)
			q.material = _sprite_mat("smoke.png", Color(0.8, 0.8, 0.8, 0.22), false, true)
			p.direction = Vector3(0, 0, -1)
			p.spread = 18.0
			p.initial_velocity_min = 0.3; p.initial_velocity_max = 1.2
			p.damping_min = 2.0; p.damping_max = 3.0
			p.gravity = Vector3(0, 0.5, 0)
			var c3 := Curve.new()
			c3.add_point(Vector2(0, 0.4)); c3.add_point(Vector2(1, 2.5))
			p.scale_amount_curve = c3
			p.angle_min = -180; p.angle_max = 180
			grad.set_color(0, Color(1, 1, 1, 0.9)); grad.set_color(1, Color(1, 1, 1, 0))
		"fire":
			p.amount = 18
			p.lifetime = 0.7
			q.size = Vector2(1.6, 1.6)
			q.material = _sprite_mat("smoke_02.png", Color(4.0, 1.8, 0.5, 1.0), true)
			p.direction = Vector3(0, 1, 0)
			p.spread = 90.0
			p.initial_velocity_min = 2.0; p.initial_velocity_max = 7.0
			p.damping_min = 5.0; p.damping_max = 8.0
			p.gravity = Vector3(0, 2.0, 0)
			var c4 := Curve.new()
			c4.add_point(Vector2(0, 0.5)); c4.add_point(Vector2(1, 2.0))
			p.scale_amount_curve = c4
			p.angle_min = -180; p.angle_max = 180
			grad.set_color(0, Color(1, 1, 1, 1)); grad.set_color(0.5, Color(1, 0.5, 0.2, 0.6)); grad.set_color(1, Color(0.2, 0.1, 0.05, 0))
		"smoke_big":
			p.amount = 16
			p.lifetime = 3.2
			p.explosiveness = 0.7
			q.size = Vector2(2.2, 2.2)
			q.material = _sprite_mat("smoke.png", Color(0.22, 0.2, 0.19, 0.75), false, true)
			p.direction = Vector3(0, 1, 0)
			p.spread = 70.0
			p.initial_velocity_min = 1.0; p.initial_velocity_max = 4.0
			p.damping_min = 1.5; p.damping_max = 2.5
			p.gravity = Vector3(0, 0.8, 0)
			var c5 := Curve.new()
			c5.add_point(Vector2(0, 0.5)); c5.add_point(Vector2(1, 2.6))
			p.scale_amount_curve = c5
			p.angle_min = -180; p.angle_max = 180
			grad.set_color(0, Color(1, 1, 1, 0.9)); grad.set_color(1, Color(1, 1, 1, 0))
	if p.mesh == null:
		p.mesh = q
	p.color_ramp = grad
	_root.add_child(p)
	return p


func _build_pools() -> void:
	var counts := {"dust": 10, "debris": 8, "sparks": 10, "flash": 10, "blood": 8, "muzzle_smoke": 6, "fire": 3, "smoke_big": 3}
	for k in counts:
		var arr: Array[CPUParticles3D] = []
		for i in counts[k]:
			arr.append(_make_particles(k))
		_particles[k] = arr
		_particle_i[k] = 0
	# decals
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	for i in DECAL_MAX:
		var d := MeshInstance3D.new()
		d.mesh = q
		d.visible = false
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(d)
		_decals.append(d)
	for s in ["concrete", "metal"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = MeshKit.tex("res://assets/textures/decals/bullet_hole_%s.png" % s)
		m.normal_enabled = true
		m.normal_texture = MeshKit.tex("res://assets/textures/decals/bullet_hole_%s_normal.png" % s)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.9
		m.render_priority = -1
		_decal_mats[s] = m
	var bm: StandardMaterial3D = _decal_mats["concrete"].duplicate()
	bm.albedo_texture = MeshKit.tex(FXDIR + "blood.png")
	bm.albedo_color = Color(0.35, 0.02, 0.02, 0.9)
	bm.normal_enabled = false
	_decal_mats["blood"] = bm
	# tracers
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(5.0, 3.2, 1.4, 0.9)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.006
	cyl.bottom_radius = 0.012
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.material = tm
	for i in TRACER_MAX:
		var t := MeshInstance3D.new()
		t.mesh = cyl
		t.visible = false
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(t)
		_tracers.append([t, Vector3.ZERO, Vector3.ZERO, 0.0, 0.0, 0.0])
	# shells
	var brass := MeshKit.flat(Color(0.85, 0.62, 0.3), 0.28, 1.0)
	var red := MeshKit.flat(Color(0.65, 0.07, 0.05), 0.5, 0.0)
	for i in SHELL_MAX:
		var n := MeshInstance3D.new()
		n.mesh = MeshKit.cyl(0.0045, 0.03, 8)
		n.material_override = brass
		n.visible = false
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(n)
		_shells.append({"node": n, "vel": Vector3.ZERO, "spin": Vector3.ZERO, "alive": false, "t": 0.0, "bounced": 0, "type": "rifle", "brass": brass, "red": red})
	# lights
	for i in 4:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = false
		l.omni_range = 6.0
		l.light_color = Color(1.0, 0.72, 0.4)
		_root.add_child(l)
		_lights.append(l)


func _emit(kind: String, pos: Vector3, normal := Vector3.UP, color := Color.WHITE) -> void:
	var arr: Array = _particles[kind]
	var i: int = _particle_i[kind]
	_particle_i[kind] = (i + 1) % arr.size()
	var p: CPUParticles3D = arr[i]
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var b := Basis.looking_at(-normal, up) if normal.length() > 0.1 else Basis.IDENTITY
	p.global_transform = Transform3D(b, pos)
	p.restart()
	p.emitting = true


func _flash_light(pos: Vector3, energy: float, rng: float, dur: float, color := Color(1.0, 0.72, 0.4)) -> void:
	var l := _lights[_light_i]
	_light_i = (_light_i + 1) % _lights.size()
	l.global_position = pos
	l.light_energy = energy
	l.omni_range = rng
	l.light_color = color
	l.visible = true
	var t := create_tween()
	t.tween_property(l, "light_energy", 0.0, dur)
	t.tween_callback(func(): l.visible = false)


# ------------------------------------------------------------------ public API
func muzzle_flash(muzzle: Node3D, scale := 1.0, suppressed := false) -> void:
	var f: Node3D = _flash_nodes.get(muzzle)
	if f == null or not is_instance_valid(f):
		f = _build_flash()
		muzzle.add_child(f)
		_flash_nodes[muzzle] = f
	f.visible = true
	var s := scale * randf_range(0.8, 1.2)
	if suppressed:
		s *= 0.4
	f.scale = Vector3.ONE * s
	f.rotation.z = randf() * TAU
	for c in f.get_children():
		if c is MeshInstance3D:
			c.visible = randf() > 0.15 or c.name == "Core"
	var gen: int = f.get_meta("gen", 0) + 1
	f.set_meta("gen", gen)
	get_tree().create_timer(0.035, false).timeout.connect(func():
		if is_instance_valid(f) and f.get_meta("gen", 0) == gen:
			f.visible = false)
	_flash_light(muzzle.global_position, 5.0 * (0.4 if suppressed else 1.0) * clampf(scale, 0.6, 1.5), 7.0, 0.06)
	if quality >= 1:
		_emit("muzzle_smoke", muzzle.global_position, muzzle.global_basis.z)


func _build_flash() -> Node3D:
	var root := Node3D.new()
	root.name = "Flash"
	root.visible = false
	var front := _flash_mat("muzzle_flash_front.png", Color(3.2, 2.2, 1.2, 1.0))
	var side := _flash_mat("muzzle_flash_side.png", Color(3.0, 1.9, 0.9, 1.0))
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = q
	core.material_override = front
	core.position = Vector3(0, 0, -0.01)
	root.add_child(core)
	# side flames (cross quads, extending forward along -Z)
	for i in 3:
		var sq := QuadMesh.new()
		sq.size = Vector2(0.2, 0.07)
		var m := MeshInstance3D.new()
		m.mesh = sq
		m.material_override = side
		m.transform = Transform3D(Basis(Vector3.FORWARD, i * PI / 3.0) * Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, -0.1))
		root.add_child(m)
	for c in root.get_children():
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(c as VisualInstance3D).layers = 2
	return root


func _flash_mat(tex: String, col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = MeshKit.tex(FXDIR + tex)
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func tracer(from: Vector3, to: Vector3, width := 1.0) -> void:
	var d := from.distance_to(to)
	if d < 2.0:
		return
	var t = _tracers[_tracer_i]
	_tracer_i = (_tracer_i + 1) % TRACER_MAX
	t[1] = from
	t[2] = to
	t[3] = 0.0
	t[4] = minf(d * 0.5, 4.5)   # streak length
	t[5] = 380.0
	var n: MeshInstance3D = t[0]
	n.visible = true
	n.scale = Vector3(width, 1, width)


func impact(pos: Vector3, normal: Vector3, surface: String, dir := Vector3.ZERO) -> void:
	var refl := (dir - 2.0 * dir.dot(normal) * normal).normalized() if dir != Vector3.ZERO else normal
	var spray := (normal * 0.7 + refl * 0.3).normalized()
	match surface:
		"metal":
			_emit("sparks", pos + normal * 0.01, spray)
			_emit("flash", pos + normal * 0.03, normal)
			_decal(pos, normal, "metal", randf_range(0.05, 0.07))
			Audio.play3d("impact_metal", pos, -4.0, 0.1, 5.0)
			if randf() < 0.3:
				Audio.play3d("ricochet", pos, -8.0, 0.1, 6.0)
			_flash_light(pos + normal * 0.1, 1.5, 2.5, 0.05)
		"dirt":
			_emit("dust", pos, normal)
			_emit("debris", pos, spray)
			_decal(pos, normal, "concrete", randf_range(0.06, 0.09))
			Audio.play3d("impact_dirt", pos, -4.0, 0.1, 5.0)
		"wood":
			_emit("dust", pos, normal)
			_emit("debris", pos, spray)
			_decal(pos, normal, "concrete", randf_range(0.05, 0.07))
			Audio.play3d("impact_wood", pos, -4.0, 0.1, 5.0)
		"glass":
			_emit("sparks", pos, spray)
			Audio.play3d("impact_metal", pos, -6.0, 0.2, 5.0)
		_:
			_emit("dust", pos, normal)
			_emit("debris", pos, spray)
			if quality >= 1:
				_emit("flash", pos + normal * 0.02, normal)
			_decal(pos, normal, "concrete", randf_range(0.07, 0.1))
			Audio.play3d("impact_concrete", pos, -4.0, 0.1, 5.0)


func blood(pos: Vector3, normal: Vector3, dir: Vector3) -> void:
	_emit("blood", pos, (-dir * 0.4 + dir * 0.0 + normal * 0.6).normalized())
	_emit("blood", pos, dir)
	Audio.play3d("impact_flesh", pos, -2.0, 0.1, 6.0)
	# splatter on the wall behind
	var space := _root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos, pos + dir * 2.5, Game.L_WORLD)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		_decal(r.position, r.normal, "blood", randf_range(0.25, 0.5))


func _decal(pos: Vector3, normal: Vector3, kind: String, size: float) -> void:
	var d := _decals[_decal_i]
	_decal_i = (_decal_i + 1) % DECAL_MAX
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	var b := Basis.looking_at(-normal, up)
	b = b * Basis(Vector3.FORWARD, randf() * TAU)
	d.global_transform = Transform3D(b.scaled_local(Vector3(size, size, size)), pos + normal * 0.004)
	d.material_override = _decal_mats[kind]
	d.visible = true


func shell(pos: Vector3, vel: Vector3, type := "rifle") -> void:
	if quality == 0:
		return
	var s = _shells[_shell_i]
	_shell_i = (_shell_i + 1) % SHELL_MAX
	var n: MeshInstance3D = s.node
	n.global_position = pos
	n.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	match type:
		"shotgun":
			n.mesh = MeshKit.cyl(0.0105, 0.06, 10)
			n.material_override = s.red
		"pistol":
			n.mesh = MeshKit.cyl(0.0048, 0.019, 8)
			n.material_override = s.brass
		_:
			n.mesh = MeshKit.cyl(0.0045, 0.035, 8)
			n.material_override = s.brass
	n.visible = true
	s.vel = vel
	s.spin = Vector3(randf_range(-30, 30), randf_range(-30, 30), randf_range(-30, 30))
	s.alive = true
	s.t = 0.0
	s.bounced = 0
	s.type = type


func explosion(pos: Vector3, radius := 6.0) -> void:
	_emit("fire", pos + Vector3.UP * 0.3)
	_emit("smoke_big", pos + Vector3.UP * 0.5)
	for i in 2:
		_emit("debris", pos + Vector3.UP * 0.2, Vector3(randf_range(-0.5, 0.5), 1, randf_range(-0.5, 0.5)).normalized())
	_emit("sparks", pos + Vector3.UP * 0.2, Vector3.UP)
	_emit("dust", pos, Vector3.UP)
	_flash_light(pos + Vector3.UP, 16.0, radius * 3.0, 0.45, Color(1.0, 0.6, 0.25))
	Audio.play3d("explosion", pos, 6.0, 0.08, 18.0, 300.0)
	_decal(pos + Vector3.UP * 0.05, Vector3.UP, "concrete", radius * 0.5)
	var p = Game.player
	if p and is_instance_valid(p):
		var dist: float = p.global_position.distance_to(pos)
		p.add_trauma(clampf(1.0 - dist / (radius * 5.0), 0.0, 0.9))


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	for t in _tracers:
		var n: MeshInstance3D = t[0]
		if not n.visible:
			continue
		t[3] += delta * t[5]
		var total: float = t[1].distance_to(t[2])
		var head: float = minf(t[3], total)
		var tail: float = maxf(0.0, t[3] - t[4])
		if tail >= total:
			n.visible = false
			continue
		var dir: Vector3 = (t[2] - t[1]) / total
		var a: Vector3 = t[1] + dir * tail
		var b: Vector3 = t[1] + dir * head
		var len := a.distance_to(b)
		if len < 0.01:
			continue
		var up := dir
		var x := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
		var z := x.cross(up)
		var w: float = n.scale.x if n.scale.x > 0.0 else 1.0
		n.global_transform = Transform3D(Basis(x * w, up * len, z * w), (a + b) * 0.5)
	var space: PhysicsDirectSpaceState3D = null
	for s in _shells:
		if not s.alive:
			continue
		s.t += delta
		var n2: MeshInstance3D = s.node
		if s.t > 5.0:
			s.alive = false
			n2.visible = false
			continue
		if s.bounced >= 3:
			continue
		s.vel.y -= 11.0 * delta
		var p0: Vector3 = n2.global_position
		var p1: Vector3 = p0 + s.vel * delta
		if space == null:
			space = _root.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(p0, p1, Game.L_WORLD | Game.L_PROPS)
		var r := space.intersect_ray(q)
		if not r.is_empty():
			var nrm: Vector3 = r.normal
			s.vel = (s.vel - 1.6 * s.vel.dot(nrm) * nrm) * 0.35
			s.spin *= 0.5
			p1 = r.position + nrm * 0.004
			s.bounced += 1
			if s.bounced == 1:
				var surf: String = r.collider.get_meta("surface", "concrete") if r.collider else "concrete"
				Audio.play3d("shell_casing_metal" if surf == "metal" else "shell_casing_concrete", p1, -14.0 if s.type != "shotgun" else -12.0, 0.15, 2.0, 25.0)
			if s.bounced >= 3 or s.vel.length() < 0.4:
				s.bounced = 3
				n2.rotation = Vector3(0, randf() * TAU, PI * 0.5)
				n2.global_position = r.position + nrm * 0.005
				continue
		n2.global_position = p1
		n2.rotation += s.spin * delta
