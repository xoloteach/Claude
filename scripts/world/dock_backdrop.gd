extends RefCounted
## DOCKYARD backdrop: cheap silhouettes beyond the playable area so the horizon is never empty — more STS
## cranes and a second ship along the north quay, container stacks beyond the fences, industrial sheds, tank
## farm, chimneys (smoke added by dressing), a lit city skyline to the east, a breakwater + lighthouse and
## low hills across the water. Everything uses the "bg" group (no shadows) and relies on the scene fog.

const WKit := preload("res://scripts/world/wkit.gd")
const Layout := preload("res://scripts/world/dock_layout.gd")
const C := preload("res://scripts/world/containers.gd")


static func _blk(kit: WKit, size: Vector3, pos: Vector3, col: Color, windows := 0.0, yaw := 0.0) -> void:
	var c := col
	c.a = windows
	kit.box_geo("backdrop", size, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos + Vector3(0, size.y * 0.5, 0)), c, 0.0, "bg")


static func build(kit: WKit, L) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var P := ["maersk", "rust", "cma", "green", "grey", "white", "teal", "brown", "orange"]
	# --- north quay continues: cranes + second ship
	Layout.crane(kit, L, -205.0, false, false, 0.0, true)
	Layout.crane(kit, L, -262.0, true, false, 0.0, true)
	Layout.crane(kit, L, -320.0, false, false, 0.0, true)
	var hull := Color(0.2, 0.22, 0.25)
	_blk(kit, Vector3(34.0, 14.0, 230.0), Vector3(-80.0, -3.0, -330.0), hull)
	for i in 14:
		for r in 10:
			var hgt := 2 + (i * 3 + r * 5) % 4
			_blk(kit, Vector3(2.44, hgt * 2.59, 12.2), Vector3(-65.0 - r * 2.6, 11.0, -240.0 - i * 13.0), C.color(kit, P[(i + r) % P.size()]) * 0.8)
	# --- container stacks beyond the north wall and south fence
	for k in 40:
		var x := rng.randf_range(-45.0, 70.0)
		var z := rng.randf_range(-150.0, -82.0)
		var h := rng.randi_range(1, 4)
		var yaw := 0.0 if rng.randf() < 0.7 else 90.0
		for l in h:
			C.build_lod(kit, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(x, l * 2.59, z)), C.L40, C.color(kit, P[rng.randi() % P.size()]), "bg")
	for k in 26:
		var x := rng.randf_range(-40.0, 60.0)
		var z := rng.randf_range(75.0, 130.0)
		var h := rng.randi_range(1, 4)
		for l in h:
			C.build_lod(kit, Transform3D(Basis(Vector3.UP, deg_to_rad(90.0 if k % 3 == 0 else 0.0)), Vector3(x, l * 2.59, z)), C.L40, C.color(kit, P[rng.randi() % P.size()]), "bg")
	# RTG yard cranes (portal frames) in the south stacks
	for rz: float in [95.0, 118.0]:
		var rx := rng.randf_range(-20.0, 30.0)
		var cc := Color(0.72, 0.62, 0.2)
		for sx: float in [-12.0, 12.0]:
			for sz: float in [-3.0, 3.0]:
				kit.box_geo("steel", Vector3(0.8, 18.0, 0.8), Transform3D(Basis.IDENTITY, Vector3(rx + sx, 9.0, rz + sz)), cc, 0.0, "bg")
		for sz: float in [-3.0, 3.0]:
			kit.box_geo("steel", Vector3(25.0, 1.4, 1.0), Transform3D(Basis.IDENTITY, Vector3(rx, 18.0, rz + sz)), cc, 0.0, "bg")
		kit.box_geo("steel", Vector3(3.0, 2.5, 7.0), Transform3D(Basis.IDENTITY, Vector3(rx + 4.0, 19.5, rz)), cc * 0.9, 0.0, "bg")
	# --- industrial belt east of the perimeter wall
	var shed := Color(0.34, 0.35, 0.36)
	for k in 9:
		_blk(kit, Vector3(rng.randf_range(20.0, 40.0), rng.randf_range(8.0, 15.0), rng.randf_range(25.0, 45.0)), Vector3(rng.randf_range(78.0, 120.0), 0, -110.0 + k * 30.0), shed * rng.randf_range(0.8, 1.1), 0.0)
	# tank farm (north-east)
	for k in 7:
		var tp := Vector3(110.0 + (k % 4) * 30.0, 0.0, -120.0 - (k / 4) * 32.0)
		kit.cyl_geo("backdrop", 12.0, 14.0, Transform3D(Basis.IDENTITY, tp + Vector3(0, 7.0, 0)), Color(0.62, 0.62, 0.6, 0.0), 20, "bg")
		kit.cyl_geo("backdrop", 12.3, 0.8, Transform3D(Basis.IDENTITY, tp + Vector3(0, 14.2, 0)), Color(0.45, 0.45, 0.44, 0.0), 20, "bg")
	# chimneys with red/white bands
	var chimneys := []
	for cp: Vector3 in [Vector3(185.0, 0, -170.0), Vector3(215.0, 0, -185.0), Vector3(330.0, 0, 140.0)]:
		var h := 72.0
		kit.cyl_geo("backdrop", 3.2, h, Transform3D(Basis.IDENTITY, cp + Vector3(0, h * 0.5, 0)), Color(0.55, 0.53, 0.5, 0.0), 14, "bg", true, 2.4)
		for b in 3:
			var by := h - 4.0 - b * 9.0
			kit.cyl_geo("backdrop", 2.5 + (by / h) * 0.2 + 0.25, 3.0, Transform3D(Basis.IDENTITY, cp + Vector3(0, by, 0)), Color(0.6, 0.12, 0.08, 0.0) if b % 2 == 0 else Color(0.8, 0.78, 0.74, 0.0), 14, "bg")
		chimneys.append(cp + Vector3(0, h + 1.0, 0))
		var red := MeshInstance3D.new()
		red.mesh = MeshKit.cyl(0.6, 0.6, 6)
		red.material_override = kit.mats["emit_red"]
		red.position = cp + Vector3(0, h + 0.3, 0)
		L.geo.add_child(red)
	L.set_meta("chimneys", chimneys)
	# power-line pylons toward the east
	for k in 4:
		var pp := Vector3(150.0 + k * 90.0, 0, 40.0 + k * 25.0)
		for s: float in [-1.0, 1.0]:
			kit.beam("steel", pp + Vector3(s * 5.0, 0, 0), pp + Vector3(s * 1.0, 34.0, 0), 0.6, Color(0.45, 0.45, 0.45), "bg")
		kit.box_geo("steel", Vector3(16.0, 0.6, 0.6), Transform3D(Basis.IDENTITY, pp + Vector3(0, 28.0, 0)), Color(0.45, 0.45, 0.45), 0.0, "bg")
	# city skyline (east / south-east), lit windows at dusk
	for k in 70:
		var ang := rng.randf_range(-1.35, 1.1)
		var dist := rng.randf_range(260.0, 520.0)
		var pos := Vector3(cos(ang) * dist + 60.0, 0.0, sin(ang) * dist)
		if pos.x < 150.0:
			continue
		var h := rng.randf_range(14.0, 60.0)
		if rng.randf() < 0.12:
			h = rng.randf_range(80.0, 130.0)
		var w := rng.randf_range(16.0, 40.0)
		var col := Color(0.3, 0.31, 0.34) * rng.randf_range(0.75, 1.15)
		_blk(kit, Vector3(w, h, rng.randf_range(16.0, 36.0)), pos, col, rng.randf_range(0.15, 0.4), rng.randf_range(-20, 20))
	# hills behind the city and across the water (low, hazy)
	var hill := func(center: Vector3, radius: float, height: float, segs: int, col: Color) -> void:
		var b: Dictionary = kit.batch("backdrop", center, "bg")
		var ring := []
		for i in segs:
			var a := TAU * i / segs
			var r := radius * rng.randf_range(0.75, 1.15)
			ring.append(center + Vector3(cos(a) * r, -2.0, sin(a) * r))
		var mid := []
		for i in segs:
			var a := TAU * (i + 0.5) / segs
			var r := radius * rng.randf_range(0.35, 0.55)
			mid.append(center + Vector3(cos(a) * r, height * rng.randf_range(0.55, 0.8), sin(a) * r))
		var top: Vector3 = center + Vector3(rng.randf_range(-radius, radius) * 0.1, height, 0)
		var c2 := col
		c2.a = 0.0
		for i in segs:
			var j := (i + 1) % segs
			kit.tri(b, ring[i], mid[i], ring[j], c2)
			kit.tri(b, mid[i], mid[j], ring[j], c2)
			kit.tri(b, mid[i], top, mid[j], c2)
	for hp in [[Vector3(560.0, 0, -350.0), 260.0, 90.0], [Vector3(580.0, 0, 120.0), 300.0, 120.0], [Vector3(420.0, 0, 420.0), 200.0, 70.0],
			[Vector3(-520.0, 0, -380.0), 220.0, 55.0], [Vector3(-560.0, 0, 380.0), 240.0, 40.0]]:
		hill.call(hp[0], hp[1], hp[2], 9, Color(0.26, 0.26, 0.27))
	# breakwater + lighthouse to the south-west (in front of the sunset)
	_blk(kit, Vector3(10.0, 3.2, 180.0), Vector3(-240.0, -2.2, 170.0), Color(0.42, 0.41, 0.4), 0.0, 35.0)
	var lh := Vector3(-292.0, 0.0, 244.0)
	kit.cyl_geo("backdrop", 2.2, 18.0, Transform3D(Basis.IDENTITY, lh + Vector3(0, 9.0, 0)), Color(0.85, 0.84, 0.8, 0.0), 12, "bg", true, 1.6)
	kit.cyl_geo("backdrop", 2.3, 3.0, Transform3D(Basis.IDENTITY, lh + Vector3(0, 7.0, 0)), Color(0.7, 0.15, 0.1, 0.0), 12, "bg")
	var lamp := MeshInstance3D.new()
	lamp.mesh = MeshKit.cyl(1.2, 1.4, 10)
	lamp.material_override = kit.mats["emit_warm"]
	lamp.position = lh + Vector3(0, 18.8, 0)
	L.geo.add_child(lamp)
	# a far ship on the water
	_blk(kit, Vector3(26.0, 12.0, 160.0), Vector3(-420.0, -2.0, -40.0), Color(0.18, 0.19, 0.21), 0.0, 12.0)
	_blk(kit, Vector3(20.0, 16.0, 14.0), Vector3(-435.0, 10.0, 25.0), Color(0.75, 0.73, 0.7), 0.3, 12.0)
	for i in 8:
		_blk(kit, Vector3(22.0, rng.randf_range(5.0, 12.0), 13.0), Vector3(-420.0 + sin(deg_to_rad(12.0)) * (i * 14.0 - 60.0), 10.0, -40.0 + cos(deg_to_rad(12.0)) * (i * 14.0 - 60.0) - 20.0), C.color(kit, P[i % P.size()]) * 0.75, 0.0, 12.0)
