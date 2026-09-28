extends Node3D
## Enemy frag grenade: ballistic arc with raycast bounces, 2.6 s fuse, FX.explosion, damage falloff with a
## line-of-sight check, and a HUD-style warning indicator (screen-edge arrow) when it lands near the player.

const Cfg := preload("res://scripts/ai/ai_config.gd")
const GRAV := 16.0

var vel := Vector3.ZERO
var fuse := Cfg.GRENADE_FUSE
var thrower: Node
var _mesh: Node3D
var _spin := Vector3.ZERO
var _rest := false
var _ind: Control
var _layer: CanvasLayer
var _bounced := 0


func launch(from: Vector3, target: Vector3, by: Node) -> void:
	thrower = by
	global_position = from
	var d := target - from
	var flat := Vector3(d.x, 0, d.z)
	var t := clampf(flat.length() / 13.0, 0.7, 1.7)
	vel = flat / t
	vel.y = (d.y + 0.5 * GRAV * t * t) / t
	_spin = Vector3(randf_range(-12, 12), randf_range(-6, 6), randf_range(-12, 12))
	Audio.play3d("grenade_throw", from, -4.0, 0.08, 5.0, 40.0)


func _ready() -> void:
	_mesh = Node3D.new()
	add_child(_mesh)
	var body := MeshKit.pbr("polymer", Color(0.25, 0.3, 0.18), 20.0, false)
	var metal := MeshKit.flat(Color(0.3, 0.3, 0.3), 0.4, 0.8)
	var sph := SphereMesh.new()
	sph.radius = 0.04
	sph.height = 0.1
	sph.radial_segments = 10
	sph.rings = 6
	MeshKit.part(_mesh, sph, body)
	MeshKit.part(_mesh, MeshKit.cyl(0.013, 0.03, 8), metal, Vector3(0, 0.055, 0))
	MeshKit.box(_mesh, Vector3(0.012, 0.06, 0.02), metal, Vector3(0.022, 0.03, 0), Vector3(0, 0, -12), 0.003)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_ind = Control.new()
	_ind.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ind.draw.connect(_draw_indicator)
	_layer.add_child(_ind)


func _physics_process(delta: float) -> void:
	fuse -= delta
	if fuse <= 0.0:
		_explode()
		return
	if not _rest:
		vel.y -= GRAV * delta
		var step := vel * delta
		var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step + step.normalized() * 0.04, Game.L_WORLD | Game.L_PROPS)
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if r.is_empty():
			global_position += step
		else:
			var n: Vector3 = r.normal
			global_position = r.position + n * 0.045
			vel = vel.bounce(n) * 0.38
			vel -= n * vel.dot(n) * 0.2
			_spin *= 0.5
			_bounced += 1
			if _bounced <= 3 and vel.length() > 1.5:
				Audio.play3d("grenade_bounce", global_position, -6.0, 0.1, 4.0, 30.0)
			if n.y > 0.7 and vel.length() < 0.8:
				_rest = true
		_mesh.rotation += _spin * delta
	_ind.queue_redraw()


func _draw_indicator() -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	var d: float = (p as Node3D).global_position.distance_to(global_position)
	if d > Cfg.GRENADE_RADIUS * 1.6 or fuse > Cfg.GRENADE_FUSE - 0.3:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vp := _ind.get_viewport_rect().size
	var c := vp * 0.5
	var local := cam.global_basis.inverse() * (global_position - cam.global_position)
	var ang := atan2(local.x, -local.z)   # 0 = straight ahead
	var r := minf(vp.x, vp.y) * 0.16
	var pos := c + Vector2(sin(ang), -cos(ang)) * r
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.02)
	var col := Color(1.0, 0.25, 0.15, 0.85 * pulse) if d < Cfg.GRENADE_RADIUS else Color(1.0, 0.8, 0.3, 0.7)
	_ind.draw_circle(pos, 22.0, Color(0, 0, 0, 0.45))
	_ind.draw_arc(pos, 22.0, 0, TAU, 28, col, 2.5, true)
	# grenade glyph
	_ind.draw_circle(pos + Vector2(0, 3), 8.0, col)
	_ind.draw_rect(Rect2(pos + Vector2(-3, -9), Vector2(6, 5)), col)
	# arrow towards the grenade
	var dir := Vector2(sin(ang), -cos(ang))
	var tip := pos + dir * 34.0
	var perp := Vector2(-dir.y, dir.x)
	_ind.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 10.0 + perp * 7.0, tip - dir * 10.0 - perp * 7.0]), col)


func _explode() -> void:
	var pos := global_position
	FX.explosion(pos, Cfg.GRENADE_RADIUS)
	var p = Game.player
	if p and is_instance_valid(p) and p.has_method("take_damage"):
		var chest: Vector3 = (p as Node3D).global_position + Vector3.UP * 1.0
		var d := pos.distance_to(chest)
		if d < Cfg.GRENADE_RADIUS:
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.25, chest, Game.L_WORLD | Game.L_PROPS)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				var k := pow(1.0 - d / Cfg.GRENADE_RADIUS, 1.3)
				p.take_damage(Cfg.GRENADE_DAMAGE * k, pos)
	queue_free()
