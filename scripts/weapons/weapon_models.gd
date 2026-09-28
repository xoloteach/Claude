class_name WeaponModels
extends RefCounted
## Builds first-person weapon models. All models face -Z (barrel forward), +Y up, meters.
## Each model contains Marker3D children: Muzzle, Eject, Sight, GripR, GripL, MagWell and a "Mag" node (animated on reload).
## Optional: "Pump" (shotgun), "Bolt"/"Slide".

static var _reticles := {}


static func build(id: String, third_person := false) -> Node3D:
	match id:
		"ar": return _ar(third_person)
		"smg": return _smg()
		"shotgun": return _shotgun()
		"pistol": return _pistol()
		"sniper": return _sniper()
	return _ar(third_person)


static func _marker(parent: Node3D, n: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = n
	m.position = pos
	parent.add_child(m)
	return m


static func _mats() -> Dictionary:
	return {
		"metal": MeshKit.pbr("gun_metal", Color(0.42, 0.42, 0.45), 9.0, false, {"normal_scale": 0.6}),
		"metal_dark": MeshKit.pbr("gun_metal", Color(0.22, 0.22, 0.24), 9.0, false, {"normal_scale": 0.5}),
		"poly": MeshKit.pbr("polymer", Color(0.42, 0.42, 0.44), 10.0, false, {"normal_scale": 0.8}),
		"poly_dark": MeshKit.pbr("polymer", Color(0.24, 0.24, 0.25), 10.0, false, {"normal_scale": 0.8}),
		"fde": MeshKit.pbr("polymer", Color(0.86, 0.72, 0.52), 10.0, false, {"normal_scale": 0.8}),
		"ranger": MeshKit.pbr("polymer", Color(0.52, 0.56, 0.45), 10.0, false, {"normal_scale": 0.8}),
		"hole": MeshKit.flat(Color(0.015, 0.015, 0.015), 0.7),
		"brass": MeshKit.flat(Color(0.78, 0.58, 0.28), 0.3, 1.0),
		"rubber": MeshKit.flat(Color(0.05, 0.05, 0.05), 0.95),
		"glass": _glass(),
	}


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.75, 0.9, 0.12)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Emissive reticle texture generated in code. kind: "holo" (ring+dot), "dot".
static func reticle_material(kind: String) -> StandardMaterial3D:
	if _reticles.has(kind):
		return _reticles[kind]
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := Vector2(sz, sz) * 0.5
	for y in sz:
		for x in sz:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := 0.0
			if kind == "holo":
				a = maxf(a, clampf(1.6 - absf(d - 44.0), 0.0, 1.0))
				a = maxf(a, clampf(3.2 - d, 0.0, 1.0))
				# tick marks
				if absf(x + 0.5 - c.x) < 1.3 and d > 44.0 and d < 54.0 and y > c.y:
					a = 1.0
			else:
				a = clampf(3.0 - d, 0.0, 1.0) + clampf(1.0 - d / 9.0, 0.0, 1.0) * 0.25
			img.set_pixel(x, y, Color(1.0, 0.18, 0.12, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = Color(2.0, 1.6, 1.6, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 10
	m.no_depth_test = true
	_reticles[kind] = m
	return m


static func _rail(root: Node3D, mat: Material, y: float, z0: float, z1: float, width := 0.022) -> void:
	var length := absf(z1 - z0)
	MeshKit.box(root, Vector3(width, 0.008, length), mat, Vector3(0, y, (z0 + z1) * 0.5), Vector3.ZERO, 0.002)
	var n := int(length / 0.01)
	for i in range(0, n, 2):
		MeshKit.box(root, Vector3(width + 0.003, 0.004, 0.0055), mat, Vector3(0, y + 0.005, z0 + (i + 0.5) * 0.01 * signf(z1 - z0)), Vector3.ZERO, 0.001)


static func _holo_sight(root: Node3D, M: Dictionary, base_y: float, z: float) -> Vector3:
	# EOTech-style holographic sight. Returns sight point.
	MeshKit.box(root, Vector3(0.036, 0.018, 0.085), M.metal_dark, Vector3(0, base_y + 0.009, z), Vector3.ZERO, 0.004)
	MeshKit.box(root, Vector3(0.03, 0.014, 0.05), M.metal_dark, Vector3(0, base_y + 0.024, z + 0.01), Vector3.ZERO, 0.003)
	var wy := base_y + 0.052
	var hw := 0.021
	MeshKit.box(root, Vector3(0.006, 0.046, 0.07), M.metal_dark, Vector3(-hw - 0.003, wy, z), Vector3.ZERO, 0.002)
	MeshKit.box(root, Vector3(0.006, 0.046, 0.07), M.metal_dark, Vector3(hw + 0.003, wy, z), Vector3.ZERO, 0.002)
	MeshKit.box(root, Vector3(0.05, 0.006, 0.07), M.metal_dark, Vector3(0, wy + 0.026, z), Vector3.ZERO, 0.002)
	MeshKit.box(root, Vector3(0.012, 0.012, 0.03), M.metal_dark, Vector3(hw + 0.01, wy - 0.012, z + 0.02), Vector3.ZERO, 0.002)
	# glass panes
	var q := QuadMesh.new()
	q.size = Vector2(0.042, 0.042)
	MeshKit.part(root, q, M.glass, Vector3(0, wy, z - 0.03))
	MeshKit.part(root, q, M.glass, Vector3(0, wy, z + 0.03))
	var rq := QuadMesh.new()
	rq.size = Vector2(0.03, 0.03)
	var r := MeshKit.part(root, rq, reticle_material("holo"), Vector3(0, wy, z - 0.029), Vector3.ZERO, "Reticle")
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return Vector3(0, wy, z)


static func _mini_dot(root: Node3D, M: Dictionary, base_y: float, z: float) -> Vector3:
	MeshKit.box(root, Vector3(0.03, 0.01, 0.045), M.metal_dark, Vector3(0, base_y + 0.005, z), Vector3.ZERO, 0.003)
	var wy := base_y + 0.03
	MeshKit.box(root, Vector3(0.005, 0.036, 0.03), M.metal_dark, Vector3(-0.018, wy, z), Vector3.ZERO, 0.002)
	MeshKit.box(root, Vector3(0.005, 0.036, 0.03), M.metal_dark, Vector3(0.018, wy, z), Vector3.ZERO, 0.002)
	MeshKit.box(root, Vector3(0.041, 0.005, 0.03), M.metal_dark, Vector3(0, wy + 0.018, z), Vector3.ZERO, 0.002)
	var q := QuadMesh.new()
	q.size = Vector2(0.032, 0.032)
	MeshKit.part(root, q, M.glass, Vector3(0, wy, z - 0.01))
	var rq := QuadMesh.new()
	rq.size = Vector2(0.02, 0.02)
	var r := MeshKit.part(root, rq, reticle_material("dot"), Vector3(0, wy, z - 0.009), Vector3.ZERO, "Reticle")
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return Vector3(0, wy, z)


# ---------------------------------------------------------------------------------------- AR
static func _ar(third_person := false) -> Node3D:
	var M := _mats()
	var root := Node3D.new()
	root.name = "AR"
	var bore := 0.042
	# lower receiver
	MeshKit.box(root, Vector3(0.032, 0.046, 0.19), M.metal, Vector3(0, -0.004, 0.015), Vector3.ZERO, 0.004)
	MeshKit.box(root, Vector3(0.036, 0.05, 0.075), M.metal, Vector3(0, -0.038, -0.04), Vector3.ZERO, 0.005)
	# upper receiver
	MeshKit.box(root, Vector3(0.036, 0.04, 0.22), M.metal, Vector3(0, 0.04, 0.01), Vector3.ZERO, 0.005)
	MeshKit.box(root, Vector3(0.002, 0.016, 0.05), M.hole, Vector3(0.0181, 0.04, 0.02))  # ejection port
	MeshKit.box(root, Vector3(0.006, 0.012, 0.012), M.metal_dark, Vector3(0.02, 0.028, 0.06), Vector3.ZERO, 0.002)  # forward assist
	_rail(root, M.metal_dark, 0.064, 0.12, -0.10)
	# charging handle
	MeshKit.box(root, Vector3(0.016, 0.008, 0.03), M.metal_dark, Vector3(0, 0.062, 0.13), Vector3.ZERO, 0.002)
	MeshKit.box(root, Vector3(0.05, 0.008, 0.012), M.metal_dark, Vector3(0, 0.062, 0.142), Vector3.ZERO, 0.003)
	# handguard (FDE, M-LOK)
	MeshKit.box(root, Vector3(0.046, 0.05, 0.31), M.fde, Vector3(0, 0.038, -0.255), Vector3.ZERO, 0.009)
	_rail(root, M.fde, 0.067, -0.11, -0.40, 0.02)
	for side in [-1.0, 1.0]:
		for i in 5:
			MeshKit.box(root, Vector3(0.002, 0.011, 0.028), M.hole, Vector3(side * 0.0232, 0.036, -0.15 - i * 0.05))
	for i in 5:
		MeshKit.box(root, Vector3(0.011, 0.002, 0.028), M.hole, Vector3(0, 0.0128, -0.15 - i * 0.05))
	# barrel + gas block + muzzle brake
	MeshKit.tube(root, 0.0085, 0.2, M.metal_dark, Vector3(0, bore, -0.49))
	MeshKit.tube(root, 0.0145, 0.06, M.metal_dark, Vector3(0, bore, -0.615), 12)
	for i in 3:
		MeshKit.box(root, Vector3(0.03, 0.004, 0.008), M.hole, Vector3(0, bore + 0.009, -0.598 - i * 0.015))
	# mag well lip + magazine (PMAG style, curved)
	var mag := Node3D.new()
	mag.name = "Mag"
	mag.position = Vector3(0, -0.062, -0.04)
	root.add_child(mag)
	MeshKit.box(mag, Vector3(0.026, 0.07, 0.064), M.poly_dark, Vector3(0, -0.02, 0), Vector3(5, 0, 0), 0.004)
	MeshKit.box(mag, Vector3(0.026, 0.07, 0.062), M.poly_dark, Vector3(0, -0.083, -0.009), Vector3(14, 0, 0), 0.004)
	MeshKit.box(mag, Vector3(0.03, 0.012, 0.07), M.poly_dark, Vector3(0, -0.121, -0.02), Vector3(18, 0, 0), 0.004)
	for i in 3:
		MeshKit.box(mag, Vector3(0.0275, 0.004, 0.05), M.poly, Vector3(0, -0.03 - i * 0.02, 0.0), Vector3(5 + i * 3, 0, 0), 0.001)
	_marker(root, "MagWell", mag.position)
	# pistol grip + trigger
	MeshKit.box(root, Vector3(0.03, 0.10, 0.042), M.poly_dark, Vector3(0, -0.068, 0.078), Vector3(-18, 0, 0), 0.008)
	MeshKit.box(root, Vector3(0.006, 0.004, 0.058), M.metal_dark, Vector3(0, -0.04, 0.035))
	MeshKit.box(root, Vector3(0.004, 0.02, 0.006), M.metal_dark, Vector3(0, -0.028, 0.03), Vector3(-12, 0, 0))
	# buffer tube + stock
	MeshKit.tube(root, 0.015, 0.2, M.metal_dark, Vector3(0, 0.036, 0.215))
	MeshKit.box(root, Vector3(0.04, 0.072, 0.15), M.fde, Vector3(0, 0.02, 0.29), Vector3(0, 0, 0), 0.01)
	MeshKit.box(root, Vector3(0.036, 0.022, 0.1), M.fde, Vector3(0, 0.06, 0.28), Vector3.ZERO, 0.008)
	MeshKit.box(root, Vector3(0.043, 0.1, 0.02), M.rubber, Vector3(0, 0.012, 0.37), Vector3.ZERO, 0.006)
	# foregrip
	MeshKit.part(root, MeshKit.cyl(0.015, 0.075, 12, 0.013), M.poly_dark, Vector3(0, -0.02, -0.30))
	var sight := _holo_sight(root, M, 0.068, -0.02)
	_marker(root, "Sight", sight)
	_marker(root, "Muzzle", Vector3(0, bore, -0.65))
	_marker(root, "Eject", Vector3(0.022, 0.042, 0.02))
	_marker(root, "GripR", Vector3(0.0, -0.058, 0.07))
	_marker(root, "GripL", Vector3(-0.004, -0.005, -0.3))
	return root


# ---------------------------------------------------------------------------------------- SMG
static func _smg() -> Node3D:
	var M := _mats()
	var root := Node3D.new()
	root.name = "SMG"
	var bore := 0.045
	MeshKit.tube(root, 0.021, 0.30, M.metal, Vector3(0, bore, -0.03), 18)
	MeshKit.box(root, Vector3(0.036, 0.04, 0.22), M.metal, Vector3(0, 0.012, 0.0), Vector3.ZERO, 0.005)
	MeshKit.box(root, Vector3(0.002, 0.014, 0.04), M.hole, Vector3(0.0215, bore, 0.02))
	MeshKit.box(root, Vector3(0.05, 0.052, 0.13), M.ranger, Vector3(0, 0.038, -0.22), Vector3.ZERO, 0.012)
	for i in 4:
		MeshKit.box(root, Vector3(0.052, 0.004, 0.012), M.poly_dark, Vector3(0, 0.02, -0.18 - i * 0.025))
	# suppressor
	MeshKit.tube(root, 0.008, 0.06, M.metal_dark, Vector3(0, bore, -0.3))
	MeshKit.tube(root, 0.02, 0.17, M.metal_dark, Vector3(0, bore, -0.4), 20)
	MeshKit.tube(root, 0.0205, 0.012, M.metal, Vector3(0, bore, -0.325), 20)
	MeshKit.tube(root, 0.0205, 0.012, M.metal, Vector3(0, bore, -0.478), 20)
	# charging handle tube
	MeshKit.tube(root, 0.006, 0.08, M.metal_dark, Vector3(-0.02, 0.058, -0.13))
	MeshKit.box(root, Vector3(0.018, 0.008, 0.008), M.metal_dark, Vector3(-0.03, 0.062, -0.1), Vector3.ZERO, 0.002)
	_rail(root, M.metal_dark, 0.07, 0.1, -0.06, 0.02)
	var mag := Node3D.new()
	mag.name = "Mag"
	mag.position = Vector3(0, -0.012, -0.075)
	root.add_child(mag)
	MeshKit.box(mag, Vector3(0.022, 0.08, 0.036), M.metal_dark, Vector3(0, -0.04, 0), Vector3(6, 0, 0), 0.004)
	MeshKit.box(mag, Vector3(0.022, 0.07, 0.036), M.metal_dark, Vector3(0, -0.11, -0.01), Vector3(12, 0, 0), 0.004)
	MeshKit.box(mag, Vector3(0.026, 0.01, 0.042), M.poly_dark, Vector3(0, -0.148, -0.018), Vector3(12, 0, 0), 0.003)
	_marker(root, "MagWell", mag.position)
	MeshKit.box(root, Vector3(0.03, 0.095, 0.04), M.poly_dark, Vector3(0, -0.05, 0.075), Vector3(-14, 0, 0), 0.008)
	MeshKit.box(root, Vector3(0.006, 0.004, 0.05), M.metal_dark, Vector3(0, -0.016, 0.035))
	# collapsible stock
	for side in [-1.0, 1.0]:
		MeshKit.tube(root, 0.0045, 0.17, M.metal_dark, Vector3(side * 0.016, 0.03, 0.2), 8)
	MeshKit.box(root, Vector3(0.046, 0.085, 0.016), M.rubber, Vector3(0, 0.022, 0.29), Vector3.ZERO, 0.006)
	var sight := _mini_dot(root, M, 0.074, 0.03)
	_marker(root, "Sight", sight)
	_marker(root, "Muzzle", Vector3(0, bore, -0.49))
	_marker(root, "Eject", Vector3(0.024, bore, 0.02))
	_marker(root, "GripR", Vector3(0.0, -0.045, 0.07))
	_marker(root, "GripL", Vector3(-0.006, 0.02, -0.22))
	return root


# ---------------------------------------------------------------------------------------- SHOTGUN
static func _shotgun() -> Node3D:
	var M := _mats()
	var root := Node3D.new()
	root.name = "Shotgun"
	var bore := 0.042
	MeshKit.box(root, Vector3(0.04, 0.062, 0.22), M.metal, Vector3(0, 0.02, 0.0), Vector3.ZERO, 0.006)
	MeshKit.box(root, Vector3(0.002, 0.02, 0.06), M.hole, Vector3(0.0201, 0.03, 0.0))
	MeshKit.box(root, Vector3(0.016, 0.004, 0.07), M.hole, Vector3(0, -0.0115, -0.02))  # loading port
	MeshKit.tube(root, 0.0125, 0.5, M.metal_dark, Vector3(0, bore, -0.36), 16)
	MeshKit.tube(root, 0.0115, 0.40, M.metal_dark, Vector3(0, 0.012, -0.31), 16)
	MeshKit.box(root, Vector3(0.012, 0.03, 0.02), M.metal_dark, Vector3(0, 0.027, -0.54), Vector3.ZERO, 0.002)
	MeshKit.box(root, Vector3(0.004, 0.014, 0.004), M.metal, Vector3(0, 0.063, -0.585))  # front post
	MeshKit.part(root, MeshKit.cyl(0.0025, 0.003, 8), MeshKit.flat(Color(1.0, 0.5, 0.1), 0.4, 0.0, Color(1.0, 0.45, 0.1), 2.0), Vector3(0, 0.0705, -0.585), Vector3(90, 0, 0))
	# ghost ring rear sight
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0045
	ring.outer_radius = 0.008
	ring.rings = 16
	ring.ring_segments = 8
	MeshKit.part(root, ring, M.metal_dark, Vector3(0, 0.07, 0.07), Vector3(90, 0, 0))
	MeshKit.box(root, Vector3(0.024, 0.014, 0.012), M.metal_dark, Vector3(0, 0.056, 0.07), Vector3.ZERO, 0.003)
	# pump
	var pump := Node3D.new()
	pump.name = "Pump"
	pump.position = Vector3(0, 0.014, -0.24)
	root.add_child(pump)
	MeshKit.box(pump, Vector3(0.05, 0.048, 0.17), M.poly_dark, Vector3.ZERO, Vector3.ZERO, 0.012)
	for i in 6:
		MeshKit.box(pump, Vector3(0.052, 0.006, 0.008), M.poly, Vector3(0, -0.012, -0.06 + i * 0.024), Vector3.ZERO, 0.002)
	var mag := Node3D.new()   # shells are the "mag" for shotgun
	mag.name = "Mag"
	mag.position = Vector3(0, -0.02, -0.02)
	root.add_child(mag)
	var shell := Node3D.new()
	shell.name = "Shell"
	shell.visible = false
	mag.add_child(shell)
	MeshKit.tube(shell, 0.0095, 0.05, MeshKit.flat(Color(0.7, 0.08, 0.06), 0.5), Vector3(0, 0, -0.005), 12)
	MeshKit.tube(shell, 0.01, 0.014, M.brass, Vector3(0, 0, 0.026), 12)
	_marker(root, "MagWell", mag.position)
	# stock + grip
	MeshKit.box(root, Vector3(0.032, 0.09, 0.045), M.poly_dark, Vector3(0, -0.055, 0.1), Vector3(-22, 0, 0), 0.008)
	MeshKit.box(root, Vector3(0.036, 0.05, 0.2), M.poly_dark, Vector3(0, 0.012, 0.22), Vector3(4, 0, 0), 0.01)
	MeshKit.box(root, Vector3(0.036, 0.1, 0.07), M.poly_dark, Vector3(0, -0.005, 0.33), Vector3(-6, 0, 0), 0.01)
	MeshKit.box(root, Vector3(0.04, 0.125, 0.02), M.rubber, Vector3(0, -0.008, 0.375), Vector3(-6, 0, 0), 0.006)
	MeshKit.box(root, Vector3(0.006, 0.004, 0.06), M.metal_dark, Vector3(0, -0.018, 0.045))
	_marker(root, "Sight", Vector3(0, 0.07, 0.07))
	_marker(root, "Muzzle", Vector3(0, bore, -0.61))
	_marker(root, "Eject", Vector3(0.024, 0.03, 0.0))
	_marker(root, "GripR", Vector3(0.0, -0.05, 0.095))
	_marker(root, "GripL", Vector3(0.0, 0.0, -0.24))
	return root


# ---------------------------------------------------------------------------------------- GLB weapons
static func _load_glb(path: String, forward_x := true) -> Node3D:
	var root := Node3D.new()
	if not ResourceLoader.exists(path):
		return root
	var inst: Node3D = load(path).instantiate()
	if forward_x:
		inst.rotation_degrees = Vector3(0, 90, 0)   # +X -> -Z
	root.add_child(inst)
	return root


static func _pistol() -> Node3D:
	var root := _load_glb("res://assets/models/weapons/pistol.glb")
	root.name = "Pistol"
	# model is +X forward; after rotation, model x -> -z. Frame spans x -0.048..0.174, slide top y≈0.078.
	var inst := root.get_child(0) as Node3D
	var slide := inst.find_child("*slide*", true, false) as Node3D
	var mag_mesh := inst.find_child("*magazine*", true, false) as Node3D
	if slide:
		slide.set_meta("anim_axis", Vector3(1, 0, 0))  # local axis in model space (backwards is -X)
	# re-parent mag into a "Mag" node so reload anim can move it
	var mag := Node3D.new()
	mag.name = "Mag"
	root.add_child(mag)
	if mag_mesh:
		var xf := inst.transform * mag_mesh.transform
		mag_mesh.owner = null
		mag_mesh.get_parent().remove_child(mag_mesh)
		mag.add_child(mag_mesh)
		mag_mesh.transform = xf
	var slide_holder := Node3D.new()
	slide_holder.name = "Slide"
	root.add_child(slide_holder)
	if slide:
		var sxf := inst.transform * slide.transform
		slide.owner = null
		slide.get_parent().remove_child(slide)
		slide_holder.add_child(slide)
		slide.transform = sxf
	_marker(root, "MagWell", Vector3.ZERO)
	_marker(root, "Sight", Vector3(0, 0.083, 0.0))
	_marker(root, "Muzzle", Vector3(0, 0.062, -0.176))
	_marker(root, "Eject", Vector3(0.016, 0.07, -0.02))
	_marker(root, "GripR", Vector3(0, -0.02, 0.018))
	_marker(root, "GripL", Vector3(-0.01, -0.03, 0.02))
	return root


static func _sniper() -> Node3D:
	var root := _load_glb("res://assets/models/weapons/sniper.glb")
	root.name = "Sniper"
	var inst := root.get_child(0) as Node3D
	# grip/trigger at x≈-0.29 -> shift model so the trigger sits near origin
	inst.position = Vector3(0, 0, -0.29)  # model x=-0.29 maps to z=+0.29, shift forward
	var bolt := inst.find_child("*bolt_a*", true, false) as Node3D
	var bolt_holder := Node3D.new()
	bolt_holder.name = "Bolt"
	root.add_child(bolt_holder)
	if bolt:
		var bxf := inst.transform * bolt.transform
		bolt.owner = null
		bolt.get_parent().remove_child(bolt)
		bolt_holder.add_child(bolt)
		bolt.transform = bxf
	var mag := Node3D.new()
	mag.name = "Mag"
	mag.position = Vector3(0, -0.03, -0.07)
	root.add_child(mag)
	var M := _mats()
	var clip := Node3D.new()
	clip.name = "Clip"
	clip.visible = false
	mag.add_child(clip)
	for i in 5:
		MeshKit.tube(clip, 0.0045, 0.06, M.brass, Vector3(0, i * 0.009, 0), 8)
	_marker(root, "MagWell", mag.position)
	# scope spans model x -0.261..-0.153, y 0.046..0.096, z center -0.007 -> world: z = -x - 0.29 ; x = z_model
	_marker(root, "Sight", Vector3(-0.007, 0.0706, -0.03))
	_marker(root, "Muzzle", Vector3(0, 0.035, -0.89))
	_marker(root, "Eject", Vector3(0.02, 0.035, 0.02))
	_marker(root, "GripR", Vector3(0, -0.03, 0.03))
	_marker(root, "GripL", Vector3(0, -0.02, -0.28))
	return root
