extends RefCounted
## DOCKYARD layout: ground surfaces, quay + water + moored ship, gantry cranes, the container yard with its
## stair/catwalk network, map boundaries (container wall, fences, perimeter wall, invisible walls), enemy spawns.

const WKit := preload("res://scripts/world/wkit.gd")
const C := preload("res://scripts/world/containers.gd")

const QUAY_X := -56.0
const WATER_Y := -1.9
const H := 2.59

# container yard columns (x centres) and rows (z centres)
const G1 := [-38.4, -35.9]
const G2 := [-28.6, -26.1, -23.6]
const G3 := [-15.0, -12.5]
const G4 := [-5.2, -2.7, -0.2]
const ROW_N := -42.0
const ROW_M1 := -22.0
const ROW_M2 := 6.0
const ROW_S := 28.0


static func build(kit: WKit, L) -> void:
	_ground(kit, L)
	_quay(kit, L)
	_water(kit, L)
	_ship(kit, L)
	crane(kit, L, -30.0, false, true)
	crane(kit, L, 36.0, true, true)
	_yard(kit, L)
	_boundaries(kit, L)
	_spawns(L)


# ------------------------------------------------------------------ ground
static func _rect(kit: WKit, mat: String, x0: float, x1: float, z0: float, z1: float, tile := 20.0) -> void:
	var x := x0
	while x < x1 - 0.001:
		var xe := minf(x + tile, x1)
		var z := z0
		while z < z1 - 0.001:
			var ze := minf(z + tile, z1)
			var c := Vector3((x + xe) * 0.5, 0.0, (z + ze) * 0.5)
			kit.quad4(kit.batch(mat, c), Vector3(x, 0, ze), Vector3(xe, 0, ze), Vector3(xe, 0, z), Vector3(x, 0, z), Color.WHITE)
			z = ze
		x = xe


static func _ground(kit: WKit, L) -> void:
	# one collision slab for all walkable land (top at y = 0)
	kit.solid(Vector3(122.0, 2.0, 132.0), Transform3D(Basis.IDENTITY, Vector3(QUAY_X + 61.0, -1.0, 0.0)), "concrete")
	_rect(kit, "quay", QUAY_X, -42.0, -66.0, 66.0)
	_rect(kit, "ground", -42.0, 8.0, -66.0, -12.0)
	_rect(kit, "asphalt", -42.0, 8.0, -12.0, -4.0)
	_rect(kit, "ground", -42.0, 8.0, -4.0, 48.0)
	_rect(kit, "asphalt", -42.0, 8.0, 48.0, 66.0)
	_rect(kit, "asphalt", 8.0, 18.0, -66.0, 66.0)
	_rect(kit, "ground", 18.0, 66.0, -66.0, -48.0)
	_rect(kit, "floor_in", 18.0, 60.0, -48.0, 6.0)
	_rect(kit, "ground", 60.0, 66.0, -48.0, 6.0)
	_rect(kit, "ground", 18.0, 66.0, 6.0, 48.0)
	_rect(kit, "asphalt", 18.0, 66.0, 48.0, 66.0)
	# expansion joints (multiplicative dark lines) on concrete zones
	var jc := Color(0.35, 0.33, 0.3, 0.8)
	for zone in [[QUAY_X, -42.0, -64.0, 64.0, 5.0], [-42.0, 8.0, -64.0, -12.0, 6.0], [-42.0, 8.0, -4.0, 48.0, 6.0], [18.0, 64.0, 6.0, 48.0, 6.0], [18.0, 60.0, -48.0, 6.0, 7.0]]:
		var x0: float = zone[0]
		var x1: float = zone[1]
		var z0: float = zone[2]
		var z1: float = zone[3]
		var s: float = zone[4]
		var x := x0 + s
		while x < x1 - 0.5:
			var z := z0
			while z < z1:
				var ze := minf(z + 20.0, z1)
				kit.ground_quad("blob", Vector3(x, 0.0, (z + ze) * 0.5), Vector2(0.07, ze - z), 0.0, jc, Vector2(0, 0.3))
				z = ze
			x += s
		var zz := z0 + s
		while zz < z1 - 0.5:
			var xx := x0
			while xx < x1:
				var xe := minf(xx + 20.0, x1)
				kit.ground_quad("blob", Vector3((xx + xe) * 0.5, 0.0, zz), Vector2(xe - xx, 0.07), 0.0, jc, Vector2(0, 0.3))
				xx = xe
			zz += s
	# backdrop land (outside the playable area) slightly below y=0 so it never z-fights
	var land := Color(0.24, 0.23, 0.22, 0.0)
	var bd := func(x0: float, x1: float, z0: float, z1: float) -> void:
		kit.quad4(kit.batch("backdrop", Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5), "far"), Vector3(x0, -0.03, z1), Vector3(x1, -0.03, z1), Vector3(x1, -0.03, z0), Vector3(x0, -0.03, z0), land)
	bd.call(66.0, 620.0, -620.0, 620.0)
	bd.call(QUAY_X, 66.0, 66.0, 620.0)
	bd.call(QUAY_X, 66.0, -620.0, -66.0)


# ------------------------------------------------------------------ quay
static func _quay(kit: WKit, L) -> void:
	# quay wall face + coping
	kit.box_geo("concrete_dark", Vector3(0.6, 8.0, 136.0), Transform3D(Basis.IDENTITY, Vector3(QUAY_X - 0.3, -4.0, 0.0)), Color(0.8, 0.8, 0.78), 0.0)
	kit.block("concrete", Vector3(0.7, 0.22, 132.0), Vector3(QUAY_X + 0.15, 0.11, 0.0), Vector3.ZERO, "concrete", Color(0.85, 0.83, 0.8), 0.03)
	# yellow safety edge paint on the coping (top) as a paint strip
	for z0 in range(-64, 64, 16):
		kit.ground_quad("paint", Vector3(QUAY_X + 0.15, 0.225, z0 + 8.0), Vector2(0.55, 16.0), 0.0, Color(0.75, 0.58, 0.12), Vector2(0, -0.1), "paint")
	# crane rails (embedded)
	for rx: float in [-54.0, -43.0]:
		for z0 in range(-64, 64, 16):
			kit.box_geo("steel", Vector3(0.14, 0.03, 16.0), Transform3D(Basis.IDENTITY, Vector3(rx, 0.005, z0 + 8.0)), Color(0.35, 0.33, 0.3), 0.0, "detail")
			kit.ground_quad("blob", Vector3(rx, 0.0, z0 + 8.0), Vector2(0.9, 16.0), 0.0, Color(0.45, 0.42, 0.38, 0.9), Vector2(0, 0.6))
	# bollards + mooring lines + fenders
	for i in 11:
		var z := -60.0 + i * 12.0
		var p := Vector3(QUAY_X + 0.75, 0.0, z)
		kit.cyl_geo("rusty", 0.2, 0.55, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.275, 0)), Color(0.25, 0.24, 0.23), 12, "detail")
		kit.cyl_geo("rusty", 0.27, 0.08, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.58, 0)), Color(0.72, 0.56, 0.14), 12, "detail")
		kit.cyl_geo("concrete", 0.45, 0.06, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.03, 0)), Color(0.6, 0.58, 0.55), 12, "detail")
		kit.solid_cyl(0.24, 0.62, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.31, 0)), "metal")
		kit.ground_quad("blob", p + Vector3(0, 0, 0), Vector2(1.3, 1.3), 0.0, Color(0.3, 0.28, 0.26, 0.8), Vector2(1, 0.6))
		# D-fenders on the quay face
		var fz := z + 6.0
		kit.box_geo("rubber", Vector3(0.45, 1.6, 2.4), Transform3D(Basis.IDENTITY, Vector3(QUAY_X - 0.8, -1.1, fz)), Color(0.12, 0.12, 0.12), 0.08)
		# hanging tyres
		for tz: float in [-1.8, 1.8]:
			kit.prop("tire_01", Vector3(QUAY_X - 0.7, -0.55, fz + tz), 90.0, "dirt", "", false)
		if z < -18.0 and z > -130.0:
			# mooring line to the ship
			var a := p + Vector3(0, 0.45, 0)
			var b := Vector3(-61.8, 9.8, z + (8.0 if i % 2 == 0 else -8.0))
			var prev := a
			for s in range(1, 9):
				var t := s / 8.0
				var q := a.lerp(b, t)
				q.y -= sin(t * PI) * 1.4
				kit.pipe("rubber", prev, q, 0.035, Color(0.55, 0.5, 0.4), 5, "detail")
				prev = q
	# 'BERTH 7' painted on the apron + ground markings
	var lab := Label3D.new()
	lab.text = "BERTH 7"
	lab.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	lab.font_size = 256
	lab.pixel_size = 0.012
	lab.modulate = Color(0.85, 0.82, 0.74, 0.8)
	lab.shaded = true
	lab.double_sided = false
	lab.outline_size = 0
	lab.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	lab.position = Vector3(-47.5, 0.03, 8.0)
	lab.rotation_degrees = Vector3(-90, 90, 0)
	L.geo.add_child(lab)
	# lane line along the quay (walkway edge) and hatch zone under crane legs
	for z0 in range(-62, 62, 6):
		kit.ground_quad("paint", Vector3(-41.2, 0.0, z0 + 1.5), Vector2(0.15, 3.0), 0.0, Color(0.8, 0.78, 0.72), Vector2.ZERO, "paint")


# ------------------------------------------------------------------ water
static func _water(kit: WKit, L) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1300.0, 1400.0)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = kit.mats["water"]
	mi.position = Vector3(QUAY_X - 650.0, WATER_Y, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	L.geo.add_child(mi)
	# dark murk under the water plane so the quay wall bottom never shows
	kit.box_geo("black", Vector3(40.0, 0.2, 400.0), Transform3D(Basis.IDENTITY, Vector3(QUAY_X - 20.0, -7.9, 0.0)), Color.WHITE, 0.0, "far")


# ------------------------------------------------------------------ ship
static func _ship(kit: WKit, L) -> void:
	var x_side := -61.0
	var z_bow := -18.0
	var z_stern := -175.0
	var deck := 10.0
	var hull_top := Color(0.14, 0.17, 0.21)
	var hull_bot := Color(0.38, 0.13, 0.1)
	var width := 32.0
	var xc := x_side - width * 0.5
	var length := z_bow - 12.0 - z_stern
	var zc := (z_bow - 12.0 + z_stern) * 0.5
	# parallel mid-body: upper (dark blue) and boot-top (red) bands
	kit.box_geo("hull", Vector3(width, deck - 0.2, length), Transform3D(Basis.IDENTITY, Vector3(xc, 0.2 + (deck - 0.2) * 0.5, zc)), hull_top)
	kit.box_geo("hull", Vector3(width - 0.2, 4.0, length), Transform3D(Basis.IDENTITY, Vector3(xc, -1.8, zc)), hull_bot)
	# bow taper (few slabs narrowing toward the bow)
	for i in 6:
		var t := float(i) / 6.0
		var w := width * (1.0 - t * t * 0.9)
		var z0 := z_bow - 12.0 + i * 2.0
		kit.box_geo("hull", Vector3(w, deck + 1.0 + t * 1.5, 2.0), Transform3D(Basis.IDENTITY, Vector3(xc, (deck + 1.0 + t * 1.5) * 0.5 - 0.3 + 0.2, z0 + 1.0)), hull_top)
	# weld seams / strakes on the visible side
	for y: float in [1.5, 4.0, 6.5, 8.8]:
		kit.box_geo("hull", Vector3(0.06, 0.08, length), Transform3D(Basis.IDENTITY, Vector3(x_side + 0.03, y, zc)), hull_top * 0.8)
	for zi in range(int(z_stern), int(z_bow - 12.0), 8):
		kit.box_geo("hull", Vector3(0.05, deck, 0.06), Transform3D(Basis.IDENTITY, Vector3(x_side + 0.02, deck * 0.5, zi)), hull_top * 0.85)
	# bulwark rail + deck edge
	kit.box_geo("steel", Vector3(0.1, 1.1, length), Transform3D(Basis.IDENTITY, Vector3(x_side + 0.1, deck + 0.55, zc)), Color(0.55, 0.52, 0.48))
	# draught marks
	for k in 4:
		var lab := Label3D.new()
		lab.text = str(8 - k * 2) + "M"
		lab.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
		lab.font_size = 96
		lab.pixel_size = 0.01
		lab.modulate = Color(0.85, 0.83, 0.78)
		lab.shaded = true
		lab.position = Vector3(x_side + 0.08, 8.0 - k * 2.0 - 4.5, -24.0)
		lab.rotation_degrees = Vector3(0, 90, 0)
		L.geo.add_child(lab)
	var name_lab := Label3D.new()
	name_lab.text = "IRON MERIDIAN"
	name_lab.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	name_lab.font_size = 256
	name_lab.pixel_size = 0.018
	name_lab.modulate = Color(0.85, 0.82, 0.76)
	name_lab.shaded = true
	name_lab.position = Vector3(x_side + 0.08, 7.6, -34.0)
	name_lab.rotation_degrees = Vector3(0, 90, 0)
	L.geo.add_child(name_lab)
	# collision so bullets stop on the hull
	kit.solid(Vector3(2.0, 12.0, length), Transform3D(Basis.IDENTITY, Vector3(x_side - 1.0, 4.0, zc)), "metal")
	# deck cargo: LOD container stacks across the deck
	var cols := ["maersk", "rust", "cma", "green", "grey", "orange", "white", "teal", "brown"]
	var zz := z_bow - 16.0
	var bay := 0
	while zz > z_stern + 40.0:
		for row in 12:
			var x := x_side - 1.8 - row * 2.5
			var hmax := 3 + int(abs(sin(bay * 1.7 + row * 0.9)) * 4.0)
			if bay == 0:
				hmax = mini(hmax, 3)
			for lv in hmax:
				C.build_lod(kit, Transform3D(Basis.IDENTITY, Vector3(x, deck + lv * H, zz - 6.1)), C.L40, C.color(kit, cols[(bay * 7 + row * 3 + lv * 5) % cols.size()]), "far", bay < 2)
		# lashing bridge / hatch coaming between bays
		kit.box_geo("steel", Vector3(width - 1.0, 2.5, 0.6), Transform3D(Basis.IDENTITY, Vector3(xc, deck + 1.25, zz + 0.3)), Color(0.5, 0.48, 0.45), 0.0, "far")
		zz -= 13.0
		bay += 1
	# accommodation block near the stern
	var ax := xc
	var az := z_stern + 22.0
	var blk := func(size: Vector3, pos: Vector3, col: Color, win: float) -> void:
		var c2 := col
		c2.a = win
		kit.box_geo("backdrop", size, Transform3D(Basis.IDENTITY, pos), c2, 0.0, "far")
	blk.call(Vector3(width - 2.0, 18.0, 14.0), Vector3(ax, deck + 9.0, az), Color(0.72, 0.7, 0.66), 0.35)
	blk.call(Vector3(width + 6.0, 1.2, 8.0), Vector3(ax, deck + 18.6, az + 2.0), Color(0.72, 0.7, 0.66), 0.0)
	blk.call(Vector3(4.0, 10.0, 4.0), Vector3(ax - 2.0, deck + 23.0, az - 3.0), Color(0.16, 0.16, 0.18), 0.0)
	var mast_top := Vector3(ax + 4.0, deck + 27.0, az)
	kit.beam("steel", Vector3(ax + 4.0, deck + 19.0, az), mast_top, 0.3, Color(0.7, 0.68, 0.64), "far")
	var red := MeshInstance3D.new()
	red.mesh = MeshKit.cyl(0.25, 0.4, 8)
	red.material_override = kit.mats["emit_red"]
	red.position = mast_top + Vector3(0, 0.3, 0)
	L.geo.add_child(red)


# ------------------------------------------------------------------ gantry crane (ship-to-shore)
static func crane(kit: WKit, L, zc: float, boom_up: bool, with_collision: bool, xoff := 0.0, lod := false) -> void:
	var M := "steel"
	var body := Color(0.78, 0.76, 0.7)
	var accent := Color(0.72, 0.2, 0.12)
	var g := "far" if lod else ""
	var xw := -54.0 + xoff
	var xl := -43.0 + xoff
	var legs_z := [zc - 7.0, zc + 7.0]
	var portal_h := 20.0
	var girder_y := 32.0
	# legs, sill beams and bogies
	for x: float in [xw, xl]:
		for z in legs_z:
			kit.box_geo(M, Vector3(1.3, portal_h, 1.3), Transform3D(Basis.IDENTITY, Vector3(x, 1.2 + portal_h * 0.5, z)), body, 0.0, g)
			kit.box_geo(M, Vector3(1.4, 1.2, 4.0), Transform3D(Basis.IDENTITY, Vector3(x, 0.6, z)), accent, 0.0, g)
			if not lod:
				for wz: float in [-1.2, 0.0, 1.2]:
					kit.cyl_geo(M, 0.38, 0.3, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, 0.38, z + wz)), Color(0.2, 0.2, 0.2), 10, "detail")
			if with_collision:
				kit.solid(Vector3(1.4, 1.2, 4.0), Transform3D(Basis.IDENTITY, Vector3(x, 0.6, z)), "metal", true)
				kit.solid(Vector3(1.3, portal_h, 1.3), Transform3D(Basis.IDENTITY, Vector3(x, 1.2 + portal_h * 0.5, z)), "metal", true)
		kit.box_geo(M, Vector3(1.1, 1.8, 15.3), Transform3D(Basis.IDENTITY, Vector3(x, portal_h + 1.2, zc)), body, 0.0, g)
		# X-bracing between legs (along z)
		kit.beam(M, Vector3(x, 3.0, legs_z[0]), Vector3(x, portal_h, legs_z[1]), 0.45, body, g)
		kit.beam(M, Vector3(x, 3.0, legs_z[1]), Vector3(x, portal_h, legs_z[0]), 0.45, body, g)
	for z in legs_z:
		kit.box_geo(M, Vector3(12.3, 1.6, 1.1), Transform3D(Basis.IDENTITY, Vector3((xw + xl) * 0.5, portal_h + 1.0, z)), body, 0.0, g)
		# upper legs to the girder
		for x: float in [xw, xl]:
			kit.box_geo(M, Vector3(1.0, girder_y - portal_h - 1.0, 1.0), Transform3D(Basis.IDENTITY, Vector3(x, portal_h + 1.0 + (girder_y - portal_h - 1.0) * 0.5, z)), body, 0.0, g)
	# main girders: back-reach over the yard (+x) and boom over the water (-x)
	var back_x := -6.0 + xoff
	var out_x := -108.0 + xoff
	var hinge_x := xw - 3.0
	for gz in [zc - 2.6, zc + 2.6]:
		kit.box_geo(M, Vector3(back_x - hinge_x, 2.2, 1.2), Transform3D(Basis.IDENTITY, Vector3((back_x + hinge_x) * 0.5, girder_y + 1.1, gz)), body, 0.0, g)
		if boom_up:
			var blen := hinge_x - out_x
			var bb := Basis(Vector3.BACK, deg_to_rad(-78.0))
			var bc := Vector3(hinge_x, girder_y + 1.1, gz) + bb * Vector3(-blen * 0.5, 0, 0)
			kit.box_geo(M, Vector3(blen, 2.0, 1.1), Transform3D(bb, bc), body, 0.0, g)
		else:
			kit.box_geo(M, Vector3(hinge_x - out_x, 2.0, 1.1), Transform3D(Basis.IDENTITY, Vector3((hinge_x + out_x) * 0.5, girder_y + 1.1, gz)), body, 0.0, g)
		# girder lattice diagonals (visual rhythm under the sun)
		if not lod:
			var x := back_x
			while x > hinge_x + 4.0:
				kit.beam(M, Vector3(x, girder_y + 0.2, gz), Vector3(x - 4.0, girder_y + 2.0, gz), 0.25, body * 0.9, g)
				x -= 4.0
	for x in [back_x - 1.0, (back_x + hinge_x) * 0.5, hinge_x + 1.0]:
		kit.box_geo(M, Vector3(0.8, 0.8, 5.2), Transform3D(Basis.IDENTITY, Vector3(x, girder_y + 2.0, zc)), body, 0.0, g)
	# A-frame apex + stays
	var apex := Vector3((xw + xl) * 0.5 - 2.0, girder_y + 18.0, zc)
	for z in [zc - 2.6, zc + 2.6]:
		kit.beam(M, Vector3(xw, girder_y + 2.0, z), Vector3(apex.x, apex.y, z), 1.0, body, g)
		kit.beam(M, Vector3(xl, girder_y + 2.0, z), Vector3(apex.x, apex.y, z), 1.0, body, g)
		kit.beam(M, Vector3(apex.x, apex.y, z), Vector3(back_x + 2.0, girder_y + 2.2, z), 0.35, body * 0.9, g)
		if boom_up:
			kit.beam(M, Vector3(apex.x, apex.y, z), Vector3(hinge_x - 2.0, girder_y + 26.0, z), 0.35, body * 0.9, g)
		else:
			kit.beam(M, Vector3(apex.x, apex.y, z), Vector3(hinge_x - 25.0, girder_y + 2.2, z), 0.35, body * 0.9, g)
			kit.beam(M, Vector3(apex.x, apex.y, z), Vector3(out_x + 10.0, girder_y + 2.2, z), 0.3, body * 0.9, g)
	kit.box_geo(M, Vector3(3.0, 1.2, 6.6), Transform3D(Basis.IDENTITY, apex + Vector3(0, 0.3, 0)), body, 0.0, g)
	# machinery house on the back-reach
	kit.box_geo("cladding", Vector3(9.0, 4.0, 6.4), Transform3D(Basis.IDENTITY, Vector3(back_x + 5.5, girder_y + 4.2, zc)), Color(0.82, 0.8, 0.74), 0.0, g)
	# trolley + operator cab + hoist ropes + spreader
	var tx := -72.0 + xoff if not boom_up else back_x + 14.0
	if not boom_up:
		kit.box_geo(M, Vector3(4.0, 1.4, 6.0), Transform3D(Basis.IDENTITY, Vector3(tx, girder_y - 0.2, zc)), accent, 0.0, g)
		kit.box_geo(M, Vector3(2.6, 2.6, 2.6), Transform3D(Basis.IDENTITY, Vector3(tx + 1.5, girder_y - 2.4, zc - 3.6)), body, 0.0, g)
		kit.box_geo("glass", Vector3(2.7, 1.2, 2.7), Transform3D(Basis.IDENTITY, Vector3(tx + 1.5, girder_y - 2.8, zc - 3.6)), Color.WHITE, 0.0, g)
		var sp_y := 16.0
		for dz: float in [-1.8, 1.8]:
			for dx: float in [-1.0, 1.0]:
				kit.pipe(M, Vector3(tx + dx, girder_y - 0.9, zc + dz), Vector3(tx + dx * 0.8, sp_y + 0.4, zc + dz * 0.8), 0.04, Color(0.2, 0.2, 0.2), 4, g)
		kit.box_geo(M, Vector3(2.4, 0.6, 12.0), Transform3D(Basis.IDENTITY, Vector3(tx, sp_y, zc)), Color(0.72, 0.55, 0.12), 0.0, g)
	# aviation warning lights
	for p in [apex + Vector3(0, 1.2, 0), Vector3(back_x + 5.5, girder_y + 6.5, zc)]:
		var r := MeshInstance3D.new()
		r.mesh = MeshKit.cyl(0.25, 0.35, 8)
		r.material_override = kit.mats["emit_red"]
		r.position = p
		L.geo.add_child(r)
	if not lod:
		L.add_omni(apex + Vector3(0, 1.5, 0), Color(1.0, 0.15, 0.05), 3.0, 10.0, 2, "blink")
		# stair tower on one leg (visual)
		for s in 8:
			var y := 1.5 + s * 2.3
			kit.box_geo("grate", Vector3(1.6, 0.06, 1.6), Transform3D(Basis.IDENTITY, Vector3(xl + 1.5, y, legs_z[1])), Color.WHITE, 0.0, "detail")
			kit.pipe(M, Vector3(xl + 2.3, y, legs_z[1] - 0.8), Vector3(xl + 2.3, y + 1.0, legs_z[1] - 0.8), 0.03, accent, 4, "detail")
		kit.box_geo(M, Vector3(3.2, 2.2, 2.2), Transform3D(Basis.IDENTITY, Vector3(xl + 0.2, portal_h + 3.2, zc)), Color(0.75, 0.73, 0.66), 0.0, g)


# ------------------------------------------------------------------ container yard
static func _stack(kit: WKit, L, x: float, zc: float, levels: int, colors: Array, flags := {}) -> void:
	var len: float = flags.get("len", C.L40)
	var flip: bool = flags.get("flip", false)
	var nl: int = flags.get("nl", 0)   # levels of the touching neighbour on world -X
	var nr: int = flags.get("nr", 0)   # ... on world +X
	for lv in levels:
		var yaw: float = flags.get("yaw", 0.0) + (kit.rng.randf_range(-0.5, 0.5) if lv > 0 and nl <= lv and nr <= lv else 0.0)
		var off := Vector3(0, 0, kit.rng.randf_range(-0.08, 0.08)) if lv > 0 else Vector3.ZERO
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(x, lv * H, zc) + off)
		if flip:
			xf.basis = xf.basis * Basis(Vector3.UP, PI)
		var f := {"open": flags.get("open", false)}
		var hide_wl := nl > lv
		var hide_wr := nr > lv
		f["skip_l"] = hide_wr if flip else hide_wl
		f["skip_r"] = hide_wl if flip else hide_wr
		C.place(kit, xf, len, C.color(kit, colors[lv % colors.size()]), f)
	# contact shadow under the stack
	var sz := Vector2(C.W + 0.6, len + 0.6)
	var r: float = flags.get("yaw", 0.0)
	kit.ground_quad("blob", Vector3(x, 0.0, zc), sz, r, Color(0.35, 0.33, 0.3, 0.9), Vector2(0, 0.35))


## A row of touching container columns: xs = x centres, levels per column, colours per column.
static func _row(kit: WKit, L, zc: float, xs: Array, levels: Array, cols: Array, flags := {}) -> void:
	for i in xs.size():
		if levels[i] <= 0:
			continue
		var f := flags.duplicate()
		f["nl"] = levels[i - 1] if i > 0 else 0
		f["nr"] = levels[i + 1] if i < xs.size() - 1 else 0
		f["flip"] = (i + absi(int(zc))) % 2 == 0
		var c: Array = cols[i] if cols[i] is Array else [cols[i]]
		_stack(kit, L, xs[i], zc, levels[i], c, f)


static func _yard(kit: WKit, L) -> void:
	var P := ["maersk", "rust", "cma", "green", "orange", "grey", "white", "teal", "brown", "yellow"]
	var pick := func(n: int) -> Array:
		var a := []
		for i in n:
			a.append(P[kit.rng.randi() % P.size()])
		return a
	# Row N (z -48..-36)
	_row(kit, L, ROW_N, G1, [3, 2], [pick.call(3), pick.call(2)])
	_row(kit, L, ROW_N, G2, [2, 1, 2], [pick.call(2), ["rust"], pick.call(2)])
	_row(kit, L, ROW_N, G3, [1, 2], [["maersk"], pick.call(2)])
	_row(kit, L, ROW_N, G4, [3, 3, 2], [pick.call(3), pick.call(3), pick.call(2)])
	# Row M1 (z -28..-16) — G3/G4 form the elevated platform with stair + catwalks
	_row(kit, L, ROW_M1, G1, [1, 2], [["green"], pick.call(2)])
	_row(kit, L, ROW_M1, G2, [1, 2, 1], [["grey"], pick.call(2), ["orange"]])
	_row(kit, L, ROW_M1, G3, [2, 2], [pick.call(2), pick.call(2)])
	_row(kit, L, ROW_M1, G4, [2, 2, 2], [pick.call(2), pick.call(2), pick.call(2)])
	# Row M2 (z 0..12)
	_row(kit, L, ROW_M2, G1, [2, 1], [pick.call(2), ["cma"]])
	_row(kit, L, ROW_M2, G2, [1, 1, 2], [["maersk"], ["rust"], pick.call(2)])
	_row(kit, L, ROW_M2, [-15.0], [1], [["green"]], {"len": C.L20})
	_stack(kit, L, -15.0, ROW_M2 + 3.3, 1, ["yellow"], {"len": C.L20, "open": true})
	_row(kit, L, ROW_M2, [-12.5], [2], [pick.call(2)])
	_row(kit, L, ROW_M2, G4, [1, 2, 1], [["white"], pick.call(2), ["teal"]])
	# Row S (z 22..34)
	_row(kit, L, ROW_S, G1, [1, 1], [["rust"], ["maersk"]])
	_row(kit, L, ROW_S, G2, [2, 3, 1], [pick.call(2), pick.call(3), ["grey"]])
	_row(kit, L, ROW_S, [-15.0], [1], [["orange"]])
	_row(kit, L, ROW_S, G4, [1, 2, 2], [["cma"], pick.call(2), pick.call(2)])
	# 20ft pieces across gaps / aisles to break long sightlines
	_stack(kit, L, -19.6, -32.0, 1, ["rust"], {"len": C.L20, "yaw": 90.0 + 4.0})
	_stack(kit, L, -32.2, 17.2, 2, ["cma", "grey"], {"len": C.L20, "yaw": 90.0})
	_stack(kit, L, -8.2, 16.5, 1, ["green"], {"len": C.L20, "yaw": 83.0})
	_stack(kit, L, 4.6, -44.0, 1, ["teal"], {"len": C.L20, "yaw": 3.0})
	_stack(kit, L, -32.3, -52.0, 1, ["orange"], {"len": C.L20, "yaw": 90.0})
	_stack(kit, L, 4.4, 26.0, 1, ["rust"], {"len": C.L20, "yaw": -4.0})
	# quay-side single containers (cover along the sniper lane)
	_stack(kit, L, -47.5, -48.0, 1, ["maersk"], {"len": C.L20, "yaw": 2.0})
	_stack(kit, L, -49.0, 22.0, 2, ["rust", "white"], {"len": C.L20, "yaw": 90.0})
	_stack(kit, L, -46.8, 50.0, 1, ["green"], {"len": C.L40, "yaw": -2.0})
	_stairs_and_catwalks(kit, L)


## Steel stair: straight flight from `base` (ground level at the low end) rising to `top_y` toward `dir`.
static func stair(kit: WKit, L, base: Vector3, dir: Vector3, top_y: float, width := 1.2, rail_sides := [1.0], surface := "metal") -> Vector3:
	var rise := top_y - base.y
	var steps := int(ceil(rise / 0.19))
	var step_h := rise / steps
	var run := step_h / tan(deg_to_rad(33.0))
	var d := dir.normalized()
	var side := Vector3.UP.cross(d).normalized()
	var length := run * steps
	var top := base + d * length + Vector3(0, rise, 0)
	var bs := Basis(side, Vector3.UP, -d)
	var sc := Color(0.33, 0.35, 0.36)
	for i in steps:
		var p := base + d * (run * (i + 0.5)) + Vector3(0, step_h * (i + 1) - 0.025, 0)
		kit.box_geo("plate", Vector3(width, 0.05, run + 0.04), Transform3D(bs, p), Color(0.8, 0.8, 0.8), 0.0, "detail")
	# stringers
	for s: float in [-1.0, 1.0]:
		var o := side * (width * 0.5 + 0.04) * s
		kit.beam("steel", base + o + Vector3(0, -0.05, 0), top + o + Vector3(0, -0.15, 0), 0.08, sc, "", 0.3)
	# handrails + posts
	for s in rail_sides:
		var o: Vector3 = side * (width * 0.5 + 0.06) * s
		kit.pipe("steel", base + o + Vector3(0, 1.0, 0), top + o + Vector3(0, 1.0, 0), 0.025, Color(0.75, 0.6, 0.12), 6)
		var n := int(length / 1.6) + 1
		for k in n + 1:
			var t := float(k) / n
			var pp: Vector3 = base.lerp(top, t) + o
			kit.pipe("steel", pp, pp + Vector3(0, 1.0, 0), 0.02, Color(0.75, 0.6, 0.12), 5)
		# rail collision (keeps players on the stair)
		var mid: Vector3 = (base + top) * 0.5 + o + Vector3(0, 0.5, 0)
		var lz := (top - base).length()
		var bz := (top - base).normalized()
		var bx := Vector3.UP.cross(bz).normalized()
		kit.solid(Vector3(0.06, 1.0, lz), Transform3D(Basis(bx, bz.cross(bx), bz), mid), "metal")
	# support legs every ~2.5 m
	var nl := int(length / 2.5)
	for k in range(1, nl + 1):
		var t := float(k) / (nl + 1)
		var pp := base.lerp(top, t)
		for s: float in [-1.0, 1.0]:
			var o := side * (width * 0.5 + 0.04) * s
			kit.box_geo("steel", Vector3(0.1, pp.y - base.y, 0.1), Transform3D(bs, Vector3(pp.x, base.y + (pp.y - base.y) * 0.5, pp.z) + o), sc)
	kit.ramp_collision(base - d * 0.1, top, width, surface)
	return top


static func catwalk(kit: WKit, L, a: Vector3, b: Vector3, width := 1.3) -> void:
	var d := (b - a)
	d.y = 0.0
	var length := d.length()
	d = d.normalized()
	var side := Vector3.UP.cross(d).normalized()
	var bs := Basis(side, Vector3.UP, -d)
	var mid := (a + b) * 0.5
	kit.box_geo("grate", Vector3(width, 0.06, length), Transform3D(bs, mid + Vector3(0, -0.03, 0)), Color.WHITE)
	kit.solid(Vector3(width, 0.12, length), Transform3D(bs, mid + Vector3(0, -0.06, 0)), "metal")
	for s: float in [-1.0, 1.0]:
		var o := side * (width * 0.5) * s
		kit.beam("steel", a + o + Vector3(0, -0.12, 0), b + o + Vector3(0, -0.12, 0), 0.12, Color(0.3, 0.32, 0.33), "", 0.2)
		kit.pipe("steel", a + o + Vector3(0, 1.05, 0), b + o + Vector3(0, 1.05, 0), 0.025, Color(0.75, 0.6, 0.12), 6)
		kit.pipe("steel", a + o + Vector3(0, 0.55, 0), b + o + Vector3(0, 0.55, 0), 0.018, Color(0.75, 0.6, 0.12), 5)
		var n := int(length / 1.5) + 1
		for k in n + 1:
			var p := a.lerp(b, float(k) / n) + o
			kit.pipe("steel", p, p + Vector3(0, 1.05, 0), 0.022, Color(0.75, 0.6, 0.12), 5)
		kit.solid(Vector3(0.06, 1.05, length), Transform3D(bs, mid + o + Vector3(0, 0.52, 0)), "metal")
	kit.ground_quad("blob", Vector3(mid.x, 0.0, mid.z), Vector2(width + 0.8, length), rad_to_deg(atan2(d.x, d.z)), Color(0.55, 0.53, 0.5, 0.6), Vector2(0, 0.8))


static func _stairs_and_catwalks(kit: WKit, L) -> void:
	var top_y := 2.0 * H
	# stair on the east side of the M1/G4 platform, rising north from the cross road
	var st := stair(kit, L, Vector3(1.75, 0.0, -12.3), Vector3(0, 0, -1), top_y, 1.2, [1.0])
	# landing joins the container roof (x < 1.02)
	var land_c := Vector3(1.75, top_y, st.z - 1.1)
	kit.box_geo("grate", Vector3(1.4, 0.06, 2.2), Transform3D(Basis.IDENTITY, land_c + Vector3(0, -0.03, 0)), Color.WHITE)
	kit.solid(Vector3(1.4, 0.12, 2.2), Transform3D(Basis.IDENTITY, land_c + Vector3(0, -0.06, 0)), "metal")
	kit.solid(Vector3(0.06, 1.05, 2.2), Transform3D(Basis.IDENTITY, land_c + Vector3(0.72, 0.52, 0)), "metal")
	kit.pipe("steel", land_c + Vector3(0.72, 1.05, -1.1), land_c + Vector3(0.72, 1.05, 1.1), 0.025, Color(0.75, 0.6, 0.12), 6)
	for zz: float in [-1.1, 1.1]:
		kit.box_geo("steel", Vector3(0.1, top_y, 0.1), Transform3D(Basis.IDENTITY, Vector3(land_c.x + 0.6, top_y * 0.5, land_c.z + zz)), Color(0.33, 0.35, 0.36))
		kit.pipe("steel", land_c + Vector3(0.72, 0, zz), land_c + Vector3(0.72, 1.05, zz), 0.022, Color(0.75, 0.6, 0.12), 5)
	# catwalk bridges at 5.18 m: G4 -> G3 and G3 -> G2 (over the central lane)
	catwalk(kit, L, Vector3(-6.42, top_y, ROW_M1 - 2.0), Vector3(-11.28, top_y, ROW_M1 - 2.0))
	catwalk(kit, L, Vector3(-16.22, top_y, ROW_M1 + 1.5), Vector3(-24.88, top_y, ROW_M1 + 1.5))


# ------------------------------------------------------------------ boundaries
static func _invisible(kit: WKit, size: Vector3, pos: Vector3) -> void:
	kit.solid(size, Transform3D(Basis.IDENTITY, pos), "concrete")


static func fence(kit: WKit, L, a: Vector3, b: Vector3, h := 3.2, collide := true) -> void:
	var d := b - a
	var length := d.length()
	var dn := d / length
	var side := Vector3.UP.cross(dn).normalized()
	var bs := Basis(side, Vector3.UP, -dn)
	var mid := (a + b) * 0.5
	kit.box_geo("fence", Vector3(0.02, h, length), Transform3D(Basis(dn.cross(Vector3.UP).normalized(), Vector3.UP, dn), mid + Vector3(0, h * 0.5, 0)), Color(0.9, 0.9, 0.88), 0.0, "detail")
	var n := int(length / 3.0)
	var pc := Color(0.5, 0.5, 0.48)
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		kit.cyl_geo("steel", 0.04, h + 0.4, Transform3D(Basis.IDENTITY, p + Vector3(0, (h + 0.4) * 0.5, 0)), pc, 6)
		kit.beam("steel", p + Vector3(0, h + 0.4, 0), p + Vector3(0, h + 0.8, 0) + side * 0.35, 0.03, pc)
	kit.pipe("steel", a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.025, pc, 5)
	kit.pipe("steel", a + Vector3(0, 0.08, 0), b + Vector3(0, 0.08, 0), 0.02, pc, 5)
	for w in 3:
		var o := side * (0.12 * (w + 1)) + Vector3(0, h + 0.45 + w * 0.12, 0)
		kit.pipe("steel", a + o, b + o, 0.008, Color(0.4, 0.4, 0.4), 3, "detail")
	if collide:
		kit.solid(Vector3(0.1, h, length), Transform3D(Basis(dn.cross(Vector3.UP).normalized(), Vector3.UP, dn), mid + Vector3(0, h * 0.5, 0)), "metal")
	kit.ground_quad("blob", mid, Vector2(0.8, length), rad_to_deg(atan2(dn.x, dn.z)), Color(0.5, 0.48, 0.45, 0.6), Vector2(0, 0.8))


static func _boundaries(kit: WKit, L) -> void:
	# invisible walls (tall — can't be mantled)
	_invisible(kit, Vector3(0.5, 30.0, 140.0), Vector3(QUAY_X + 0.05, 15.0, 0.0))
	_invisible(kit, Vector3(0.5, 30.0, 140.0), Vector3(63.6, 15.0, 0.0))
	_invisible(kit, Vector3(130.0, 30.0, 0.5), Vector3(4.0, 15.0, 63.4))
	_invisible(kit, Vector3(130.0, 30.0, 0.5), Vector3(4.0, 15.0, -62.3))
	# north: wall of 3-high containers lying east-west (yard), 2-high on the quay
	var P := ["maersk", "rust", "cma", "green", "grey", "white", "teal", "brown", "orange"]
	var x := -41.5
	var i := 0
	while x < 8.0:
		var lv := 3 if i % 3 != 1 else 4
		for l in lv:
			var xf := Transform3D(Basis(Vector3.UP, PI * 0.5 + deg_to_rad(kit.rng.randf_range(-0.8, 0.8))), Vector3(x + 6.1, l * H, -63.6 + kit.rng.randf_range(-0.1, 0.1)))
			C.build(kit, xf, C.L40, C.color(kit, P[(i * 5 + l * 3) % P.size()]), {"group": ""})
		kit.solid(Vector3(12.2, lv * H, C.W), Transform3D(Basis.IDENTITY, Vector3(x + 6.1, lv * H * 0.5, -63.6)), "metal")
		x += 12.4
		i += 1
	for qz: float in [-63.6]:
		for l in 2:
			C.build(kit, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-49.0, l * H, qz)), C.L40, C.color(kit, P[(l + 4) % P.size()]))
		kit.solid(Vector3(12.2, 2 * H, C.W), Transform3D(Basis.IDENTITY, Vector3(-49.0, H, qz)), "metal")
	# behind the wall: more stacks (seen over the top from the yard)
	for k in 10:
		var bx := -44.0 + k * 6.5
		var hl := 2 + (k * 7) % 3
		for l in hl:
			C.build_lod(kit, Transform3D(Basis.IDENTITY, Vector3(bx, l * H, -74.0 - (k % 2) * 3.0)), C.L40, C.color(kit, P[(k + l * 2) % P.size()]))
	# north-east storage fence + east perimeter wall + south fence
	fence(kit, L, Vector3(9.0, 0, -62.6), Vector3(63.0, 0, -62.6), 3.2)
	for z0 in range(-62, 63, 12):
		var zlen := minf(12.0, 63.0 - z0)
		kit.block("concrete", Vector3(0.4, 4.2, zlen), Vector3(63.8, 2.1, z0 + zlen * 0.5), Vector3.ZERO, "concrete", Color(0.8, 0.78, 0.74))
		kit.box_geo("concrete", Vector3(0.6, 0.15, zlen), Transform3D(Basis.IDENTITY, Vector3(63.8, 4.27, z0 + zlen * 0.5)), Color(0.7, 0.68, 0.64))
		kit.box_geo("concrete", Vector3(0.5, 4.2, 0.35), Transform3D(Basis.IDENTITY, Vector3(63.5, 2.1, z0)), Color(0.72, 0.7, 0.66))
	fence(kit, L, Vector3(QUAY_X + 0.4, 0, 63.0), Vector3(-10.0, 0, 63.0), 3.2)
	fence(kit, L, Vector3(4.0, 0, 63.0), Vector3(63.4, 0, 63.0), 3.2)
	# sliding gate (closed) between x -10..4
	var gc := Color(0.62, 0.6, 0.55)
	kit.box_geo("fence", Vector3(14.0, 2.6, 0.02), Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.45, 63.1)), Color.WHITE, 0.0, "detail")
	for gy: float in [0.15, 2.75]:
		kit.box_geo("steel", Vector3(14.0, 0.08, 0.08), Transform3D(Basis.IDENTITY, Vector3(-3.0, gy, 63.1)), gc)
	for gx in range(-10, 5, 2):
		kit.box_geo("steel", Vector3(0.06, 2.6, 0.06), Transform3D(Basis.IDENTITY, Vector3(gx, 1.45, 63.1)), gc)
	kit.solid(Vector3(14.0, 2.8, 0.2), Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.4, 63.1)), "metal")
	# quay-end blocker (south): stacked concrete blocks
	for bz: float in [61.0]:
		for bxi in 5:
			kit.block("concrete", Vector3(1.6, 0.8, 1.6), Vector3(-54.8 + bxi * 1.65, 0.4, bz), Vector3(0, 0, 0), "concrete", Color(0.75, 0.73, 0.7), 0.04, true)
			if bxi % 2 == 0:
				kit.block("concrete", Vector3(1.6, 0.8, 1.6), Vector3(-54.8 + bxi * 1.65, 1.2, bz), Vector3(0, 7, 0), "concrete", Color(0.72, 0.7, 0.66), 0.04)


static func _spawns(L) -> void:
	for p in [
		Vector3(-50.0, 0, -58.0), Vector3(-30.0, 0, -56.0), Vector3(-10.0, 0, -56.0), Vector3(13.0, 0, -57.0),
		Vector3(30.0, 0, -57.0), Vector3(52.0, 0, -57.0), Vector3(61.8, 0, -30.0), Vector3(61.8, 0, 2.0),
		Vector3(40.0, 0, -30.0), Vector3(-50.0, 0, -18.0), Vector3(-37.0, 0, -8.0), Vector3(55.0, 0, 28.0),
		Vector3(-50.0, 0, 38.0), Vector3(4.5, 0, -8.0), Vector3(30.0, 0, -8.0), Vector3(-19.0, 0, -45.0),
	]:
		L.add_spawn(p)
