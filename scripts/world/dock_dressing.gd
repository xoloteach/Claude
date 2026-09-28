extends RefCounted
## DOCKYARD set dressing: ground markings, puddles/oil/dirt decals, prop clusters (glb via MultiMesh +
## procedural pallets, cable drums, vehicles), street lamps + floodlight masts, signage, atmosphere particles.

const WKit := preload("res://scripts/world/wkit.gd")
const Layout := preload("res://scripts/world/dock_layout.gd")
const Bld := preload("res://scripts/world/dock_buildings.gd")
const C := preload("res://scripts/world/containers.gd")

const WHITE_PAINT := Color(0.82, 0.8, 0.74)
const YELLOW_PAINT := Color(0.78, 0.58, 0.1)

const FONT_PATH := "res://assets/fonts/BarlowCondensed-Bold.ttf"


static func build(kit: WKit, L) -> void:
	_markings(kit, L)
	_decals(kit, L)
	_props(kit, L)
	_vehicles(kit, L)
	_lighting(kit, L)
	_signs(kit, L)
	_particles(kit, L)


# ------------------------------------------------------------------ helpers
static func P(kit: WKit, name: String, pos: Vector3, yaw := 0.0, surface := "metal", collide := "box", cover := false, blob := 1.0, extra := Basis.IDENTITY) -> void:
	var ab: AABB = kit.prop(name, pos, yaw, surface, collide, cover, extra)
	if blob > 0.0:
		var s := maxf(ab.size.x, ab.size.z) * 1.5 * blob
		kit.ground_quad("blob", Vector3(pos.x, 0.0, pos.z), Vector2(s, s), 0.0, Color(0.3, 0.28, 0.26, 0.85), Vector2(1, 0.7))


static func paint_line(kit: WKit, a: Vector3, b: Vector3, w: float, col: Color, dash := 0.0, gap := 0.0, pattern := 0.0) -> void:
	var d := b - a
	var length := d.length()
	var dn := d / length
	var yaw := rad_to_deg(atan2(dn.x, dn.z))
	if dash <= 0.0:
		var n := int(ceil(length / 12.0))
		for i in n:
			var s0 := length * i / n
			var s1 := length * (i + 1) / n
			kit.ground_quad("paint", a + dn * ((s0 + s1) * 0.5), Vector2(w, s1 - s0), yaw, col, Vector2(pattern, 0.0), "paint")
		return
	var s := 0.0
	while s < length:
		var e := minf(s + dash, length)
		kit.ground_quad("paint", a + dn * ((s + e) * 0.5), Vector2(w, e - s), yaw, col, Vector2(pattern, 0.0), "paint")
		s += dash + gap


static func hatch_zone(kit: WKit, c: Vector3, size: Vector2, yaw := 0.0, col := YELLOW_PAINT) -> void:
	kit.ground_quad("paint", c, size, yaw, col, Vector2(1.0, -0.05), "paint")
	var bs := Basis(Vector3.UP, deg_to_rad(yaw))
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var corners := [bs * Vector3(-hx, 0, -hz), bs * Vector3(hx, 0, -hz), bs * Vector3(hx, 0, hz), bs * Vector3(-hx, 0, hz)]
	for i in 4:
		paint_line(kit, c + corners[i], c + corners[(i + 1) % 4], 0.15, col)


static func flat_text(L, text: String, pos: Vector3, yaw: float, px := 0.01, col := WHITE_PAINT) -> void:
	var lab := Label3D.new()
	lab.text = text
	lab.font = load(FONT_PATH)
	lab.font_size = 192
	lab.pixel_size = px
	lab.modulate = Color(col.r, col.g, col.b, 0.78)
	lab.shaded = true
	lab.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	lab.position = pos + Vector3(0, 0.025, 0)
	lab.rotation_degrees = Vector3(-90, yaw, 0)
	L.geo.add_child(lab)


# ------------------------------------------------------------------ ground markings
static func _markings(kit: WKit, L) -> void:
	# main road: yellow dashed centre line, white edges, zebra crossing near the office
	paint_line(kit, Vector3(13.0, 0, -62.0), Vector3(13.0, 0, 62.0), 0.14, YELLOW_PAINT, 3.0, 3.0)
	paint_line(kit, Vector3(8.35, 0, -62.0), Vector3(8.35, 0, 62.0), 0.14, WHITE_PAINT)
	paint_line(kit, Vector3(17.65, 0, -62.0), Vector3(17.65, 0, 62.0), 0.14, WHITE_PAINT)
	for i in 7:
		kit.ground_quad("paint", Vector3(9.3 + i * 1.3, 0, 31.0), Vector2(0.6, 3.0), 0.0, WHITE_PAINT, Vector2(0, 0.02), "paint")
	# cross road through the yard
	paint_line(kit, Vector3(-41.0, 0, -8.0), Vector3(8.0, 0, -8.0), 0.13, WHITE_PAINT, 2.5, 3.5)
	kit.ground_quad("paint", Vector3(7.0, 0, -8.0), Vector2(0.4, 7.5), 0.0, WHITE_PAINT, Vector2(0, 0.05), "paint")
	flat_text(L, "STOP", Vector3(5.8, 0, -10.0), -90.0, 0.009)
	# container bay outlines + row letters
	var rows := [[Layout.ROW_N, "A"], [Layout.ROW_M1, "B"], [Layout.ROW_M2, "C"], [Layout.ROW_S, "D"]]
	for r in rows:
		var zc: float = r[0]
		for grp in [Layout.G1, Layout.G2, Layout.G3, Layout.G4]:
			var x0: float = grp[0] - 1.22 - 0.35
			var x1: float = grp[grp.size() - 1] + 1.22 + 0.35
			paint_line(kit, Vector3(x0, 0, zc - 6.5), Vector3(x0, 0, zc + 6.5), 0.1, WHITE_PAINT)
			paint_line(kit, Vector3(x1, 0, zc - 6.5), Vector3(x1, 0, zc + 6.5), 0.1, WHITE_PAINT)
		for gi in 4:
			var grp: Array = [Layout.G1, Layout.G2, Layout.G3, Layout.G4][gi]
			var gx: float = (grp[0] + grp[grp.size() - 1]) * 0.5
			flat_text(L, "%s-%02d" % [r[1], gi + 1], Vector3(gx, 0, zc + 7.6), 0.0, 0.0065)
	# hatch zones: crane travel/keep-clear, warehouse doors, tanks, gate
	hatch_zone(kit, Vector3(-48.5, 0, -30.0), Vector2(12.5, 17.0))
	hatch_zone(kit, Vector3(-48.5, 0, 36.0), Vector2(12.5, 17.0))
	hatch_zone(kit, Vector3(15.8, 0, -36.0), Vector2(3.6, 7.0))
	hatch_zone(kit, Vector3(15.8, 0, -8.0), Vector2(3.6, 7.0))
	hatch_zone(kit, Vector3(28.0, 0, 8.4), Vector2(7.0, 4.0))
	hatch_zone(kit, Vector3(39.0, 0, -50.5), Vector2(7.0, 4.0))
	hatch_zone(kit, Vector3(34.0, 0, -56.0), Vector2(9.0, 8.0))
	flat_text(L, "KEEP CLEAR", Vector3(14.9, 0, -22.0), 90.0, 0.0075, YELLOW_PAINT)
	# truck parking bays
	for i in 7:
		var x := -40.0 + i * 4.2
		paint_line(kit, Vector3(x, 0, 50.0), Vector3(x, 0, 59.0), 0.12, WHITE_PAINT)
	paint_line(kit, Vector3(-40.0, 0, 50.0), Vector3(-14.8, 0, 50.0), 0.12, WHITE_PAINT)
	# quay walkway line + 'NO PARKING'
	flat_text(L, "NO PARKING", Vector3(-44.0, 0, 50.0), 90.0, 0.008, YELLOW_PAINT)
	# pedestrian path from the office to the gate (green) — dashed
	paint_line(kit, Vector3(21.0, 0, 48.5), Vector3(-2.0, 0, 48.5), 0.12, Color(0.3, 0.55, 0.3), 1.0, 1.0)


# ------------------------------------------------------------------ decals
static func _decals(kit: WKit, L) -> void:
	var puddles := [
		[-30.0, -8.5, 3.5, 2.2], [-12.0, -6.8, 2.6, 1.6], [0.5, -9.8, 4.0, 2.4], [12.0, 5.0, 3.0, 5.0], [14.5, -30.0, 2.4, 3.6],
		[10.5, 38.0, 2.8, 2.0], [-20.0, 56.0, 5.0, 3.0], [-35.0, 51.0, 2.4, 2.0], [8.0, 58.0, 3.2, 2.0], [-50.0, -15.0, 3.0, 2.2],
		[-47.0, 30.0, 2.4, 3.4], [-52.0, 52.0, 3.8, 2.4], [-32.0, 20.0, 2.0, 2.8], [-9.0, -34.0, 2.2, 1.8], [-20.0, 40.0, 3.4, 2.6],
		[-20.0, -56.0, 4.0, 2.4], [10.0, -58.0, 3.0, 2.0], [41.0, -52.0, 2.5, 2.0], [30.0, -20.0, 1.8, 1.4], [46.5, -8.0, 2.4, 1.6],
		[-44.5, -52.0, 2.2, 3.0], [-19.5, -20.0, 2.5, 3.2],
	]
	for p in puddles:
		kit.ground_quad("puddle", Vector3(p[0], 0.0, p[1]), Vector2(p[2], p[3]), kit.rng.randf_range(0, 180), Color(0.055, 0.058, 0.06, 0.92))
		# damp dark rim
		kit.ground_quad("blob", Vector3(p[0], 0.0, p[1]), Vector2(p[2] * 1.5, p[3] * 1.5), 0.0, Color(0.55, 0.53, 0.5, 0.8), Vector2(1, 0.9))
	var oil := [[13.0, -20.0, 2.2], [15.5, 18.0, 3.0], [-33.0, 57.0, 2.5], [-50.0, -4.0, 1.8], [38.5, -3.5, 1.6], [-20.0, -8.0, 2.4],
		[-24.0, 54.0, 2.0], [31.0, -27.0, 1.5], [44.0, 40.0, 2.0], [-5.0, -54.0, 2.2], [-38.0, -30.0, 1.4], [3.5, 15.0, 1.6]]
	for o in oil:
		kit.ground_quad("blob", Vector3(o[0], 0.0, o[1]), Vector2(o[2], o[2] * 0.8), kit.rng.randf_range(0, 180), Color(0.12, 0.11, 0.1, 0.75), Vector2(1, 0.8))
	# dirt / gravel patches along edges and in low-traffic corners
	var zones := [[-40.0, 6.0, -60.0, -50.0], [20.0, 62.0, -62.0, -49.0], [60.3, 63.3, -48.0, 6.0], [-55.0, -42.0, -64.0, 62.0],
		[-41.0, -30.0, 36.0, 47.0], [40.0, 62.0, 8.0, 32.0], [-41.0, 7.0, -35.0, -29.0]]
	for z in zones:
		var n := int((z[1] - z[0]) * (z[3] - z[2]) / 60.0) + 2
		n = mini(n, 14)
		for i in n:
			var p := Vector3(kit.rng.randf_range(z[0], z[1]), 0.0, kit.rng.randf_range(z[2], z[3]))
			var s := kit.rng.randf_range(2.5, 6.5)
			kit.ground_quad("dirt_decal", p, Vector2(s, s * kit.rng.randf_range(0.6, 1.0)), kit.rng.randf_range(0, 180), Color(0.5, 0.47, 0.43, 0.6))
	# grime along wall bases (dark soft strips)
	for w in [[Vector3(17.7, 0, -21.0), Vector2(1.2, 54.0)], [Vector3(39.0, 0, 6.3), Vector2(42.0, 1.2)], [Vector3(60.3, 0, -21.0), Vector2(1.0, 54.0)], [Vector3(39.0, 0, -48.3), Vector2(42.0, 1.2)],
			[Vector3(63.3, 0, 0.0), Vector2(1.2, 126.0)], [Vector3(18.3, 0, -21.0), Vector2(1.0, 54.0)], [Vector3(39.0, 0, 5.7), Vector2(42.0, 1.0)], [Vector3(-3.0, 0, -62.0), Vector2(90.0, 1.4)]]:
		kit.ground_quad("blob", w[0], w[1], 0.0, Color(0.38, 0.36, 0.33, 0.9), Vector2(0, 0.9))
	# tyre skid marks on the road (dark, long, faint)
	for s in [[11.0, -10.0, 12.0], [15.0, 2.0, 18.0], [-20.0, 55.0, 9.0]]:
		for off: float in [-0.9, 0.9]:
			kit.ground_quad("blob", Vector3(s[0] + off, 0.0, s[1]), Vector2(0.28, s[2]), kit.rng.randf_range(-6, 6), Color(0.35, 0.33, 0.31, 0.55), Vector2(0, 0.6))


# ------------------------------------------------------------------ props
static func barrier_line(kit: WKit, a: Vector3, count: int, yaw: float, tall := true) -> void:
	var dir := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3.RIGHT
	for i in count:
		var p := a + dir * (i * 1.58)
		P(kit, "concrete_barrier_02" if tall else "concrete_barrier_01", p, yaw + kit.rng.randf_range(-3, 3), "concrete", "box", true, 0.7)


static func cable_drum(kit: WKit, p: Vector3, yaw: float, r := 0.9, w := 1.0) -> void:
	var bs := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.BACK, PI * 0.5)
	var c := p + Vector3(0, r, 0)
	for s: float in [-0.5, 0.5]:
		kit.cyl_geo("wood", r, 0.06, Transform3D(bs, c + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(s * w, 0, 0)), Color(0.8, 0.7, 0.55), 16, "detail")
	kit.cyl_geo("rubber", r * 0.72, w - 0.06, Transform3D(bs, c), Color(0.18, 0.18, 0.18), 16, "detail")
	kit.solid_cyl(r, w, Transform3D(bs, c), "wood", true)
	kit.ground_quad("blob", Vector3(p.x, 0, p.z), Vector2(w + 1.0, r * 2.0), yaw + 90.0, Color(0.3, 0.28, 0.26, 0.8), Vector2(1, 0.6))


static func tire_stack(kit: WKit, p: Vector3, n: int) -> void:
	for i in n:
		kit.prop("tire_01", p + Vector3(kit.rng.randf_range(-0.04, 0.04), 0.083 + i * 0.165, kit.rng.randf_range(-0.04, 0.04)), kit.rng.randf_range(0, 360), "dirt", "", false, Basis(Vector3.RIGHT, PI * 0.5))
	kit.solid_cyl(0.3, n * 0.165, Transform3D(Basis.IDENTITY, p + Vector3(0, n * 0.165 * 0.5, 0)), "dirt", n >= 5)
	kit.ground_quad("blob", Vector3(p.x, 0, p.z), Vector2(1.0, 1.0), 0.0, Color(0.3, 0.28, 0.26, 0.8), Vector2(1, 0.6))


static func barrels(kit: WKit, c: Vector3, n: int, red_ratio := 0.3) -> void:
	var placed := []
	for i in n:
		var ang := kit.rng.randf() * TAU
		var r := 0.0 if i == 0 else kit.rng.randf_range(0.62, 0.62 + 0.25 * i)
		var p := c + Vector3(cos(ang) * r, 0, sin(ang) * r)
		var ok := true
		for q in placed:
			if (q as Vector3).distance_to(p) < 0.62:
				ok = false
		if not ok:
			continue
		placed.append(p)
		var red := kit.rng.randf() < red_ratio
		P(kit, "barrel_01" if red else "barrel_02", p, kit.rng.randf_range(0, 360), "metal", "cyl", false, 0.8)
	# one tipped-over barrel for storytelling
	var tp := c + Vector3(1.3, 0.3, 0.9)
	kit.prop("barrel_02", tp + Vector3(0, 0.02, 0), 30.0, "metal", "", false, Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, 0.4))
	kit.solid_cyl(0.32, 0.93, Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)) * Basis(Vector3.BACK, PI * 0.5), tp + Vector3(0, 0.02, 0)), "metal")
	kit.ground_quad("blob", Vector3(tp.x + 0.6, 0, tp.z), Vector2(1.8, 1.4), 30.0, Color(0.12, 0.11, 0.1, 0.7), Vector2(1, 0.8))


static func crate_step(kit: WKit, p: Vector3, yaw: float) -> void:
	Bld.loaded_pallet(kit, p, yaw, 3, 0.92, true)


static func _props(kit: WKit, L) -> void:
	var rng = kit.rng
	# --- quay (west lane): sparse, readable cover along the long sightline
	barrier_line(kit, Vector3(-51.5, 0, -44.0), 3, 20.0)
	barrier_line(kit, Vector3(-46.0, 0, -12.0), 2, -70.0)
	barrier_line(kit, Vector3(-52.0, 0, 4.0), 3, 5.0, false)
	barrier_line(kit, Vector3(-45.5, 0, 42.0), 2, 80.0)
	cable_drum(kit, Vector3(-50.5, 0, -24.0), 10.0, 1.0, 1.1)
	cable_drum(kit, Vector3(-44.5, 0, -2.0), 80.0, 0.8, 0.9)
	barrels(kit, Vector3(-47.0, 0, -6.5), 6, 0.35)
	tire_stack(kit, Vector3(-53.0, 0, 16.0), 5)
	tire_stack(kit, Vector3(-52.3, 0, 16.5), 3)
	Bld.loaded_pallet(kit, Vector3(-44.0, 0, 18.0), 12.0, 1, 1.15, true)
	Bld.loaded_pallet(kit, Vector3(-44.2, 0, 19.3), 8.0, 0, 1.0, true)
	P(kit, "utility_box_01", Vector3(-42.4, 0, 12.0), 90.0, "metal", "box", false)
	# lashing gear / twist-lock bins near crane 1
	for i in 3:
		kit.block("steel", Vector3(1.2, 0.8, 1.0), Vector3(-44.2, 0.4, -36.5 + i * 1.25), Vector3(0, rng.randf_range(-4, 4), 0), "metal", Color(0.2, 0.3, 0.45), 0.02, true)
	for i in 6:
		kit.pipe("steel", Vector3(-45.3, 0.05 + i * 0.07, -40.0), Vector3(-45.3 + 0.2, 0.05 + i * 0.07, -43.8), 0.03, Color(0.4, 0.38, 0.35), 5, "detail")
	# life-ring post on the quay edge
	for z: float in [-54.0, 28.0]:
		kit.box_geo("steel", Vector3(0.08, 1.5, 0.08), Transform3D(Basis.IDENTITY, Vector3(-55.0, 0.75, z)), Color(0.8, 0.8, 0.78))
		kit.cyl_geo("rubber", 0.33, 0.1, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-54.93, 1.2, z)), Color(0.85, 0.3, 0.1), 12, "detail")
	# --- container yard
	# mantle routes: pallet+crates beside 1-high containers
	crate_step(kit, Vector3(-35.9, 0, Layout.ROW_M2 + 6.7), 0.0)      # C-01 east container
	crate_step(kit, Vector3(-28.6, 0, Layout.ROW_M1 + 6.75), 0.0)     # B-02 west container
	crate_step(kit, Vector3(-23.6, 0, Layout.ROW_M1 - 6.75), 0.0)     # B-02 east container (north end)
	crate_step(kit, Vector3(-38.4, 0, Layout.ROW_S - 6.75), 0.0)      # D-01
	crate_step(kit, Vector3(-5.2, 0, Layout.ROW_M2 - 6.75), 0.0)      # C-04 west
	crate_step(kit, Vector3(-15.0, 0, Layout.ROW_S + 6.75), 0.0)      # D-03
	crate_step(kit, Vector3(-15.0, 0, Layout.ROW_N + 6.75), 0.0)      # A-03 west
	crate_step(kit, Vector3(-47.5, 0, -44.3), 0.0)                    # quay 20ft
	# centre lane cover: barriers + pallet stacks, burning barrel camp
	barrier_line(kit, Vector3(-20.5, 0, -10.8), 2, 0.0)
	barrier_line(kit, Vector3(-18.8, 0, 2.5), 2, 90.0 + 10.0, false)
	barrier_line(kit, Vector3(-8.5, 0, -36.0), 2, 5.0)
	barrier_line(kit, Vector3(-33.5, 0, -10.5), 3, -8.0)
	barrier_line(kit, Vector3(2.5, 0, -30.5), 2, 90.0)
	Bld.loaded_pallet(kit, Vector3(-18.0, 0, 38.5), 5.0, 0, 1.25, true)
	Bld.loaded_pallet(kit, Vector3(-19.4, 0, 38.8), -4.0, 1, 1.3, true)
	Bld.loaded_pallet(kit, Vector3(-9.0, 0, -26.0), 0.0, 1, 1.2, true)
	Bld.loaded_pallet(kit, Vector3(-32.4, 0, -24.0), 90.0, 0, 1.0, true)
	Bld.loaded_pallet(kit, Vector3(-32.0, 0, -22.6), 88.0, 3, 1.0, true)
	cable_drum(kit, Vector3(-9.0, 0, 20.0), 30.0)
	cable_drum(kit, Vector3(-26.0, 0, -32.5), 75.0, 0.7, 0.8)
	tire_stack(kit, Vector3(-31.8, 0, 36.5), 6)
	tire_stack(kit, Vector3(-31.2, 0, 37.1), 4)
	barrels(kit, Vector3(-8.8, 0, 38.0), 5, 0.4)
	# burning-barrel camp (fire FX added in _particles)
	var camp := Vector3(-19.5, 0, 16.5)
	P(kit, "barrel_02", camp, 0.0, "metal", "cyl", false, 1.2)
	P(kit, "military_crate_01", camp + Vector3(1.4, 0, 0.4), 70.0, "wood", "box", false, 0.8)
	P(kit, "wooden_crate_01", camp + Vector3(-1.2, 0, -0.6), 20.0, "wood", "box", false, 0.8)
	P(kit, "plastic_crate_01", camp + Vector3(-1.0, 0, 1.0), -30.0, "wood", "box", false, 0.8)
	P(kit, "jerrycan_01", camp + Vector3(1.9, 0, -0.9), 40.0, "metal", "box", false, 0.0)
	P(kit, "cardboard_box_01", camp + Vector3(0.6, 0, 1.6), 15.0, "wood", "box", false, 0.0)
	kit.ground_quad("blob", camp, Vector2(3.2, 3.2), 0.0, Color(0.16, 0.14, 0.12, 0.8), Vector2(1, 0.8))
	# gas cylinders cage near the office
	var cage := Vector3(40.5, 0, 36.0)
	for i in 7:
		P(kit, "gas_cylinder_01", cage + Vector3(-1.0 + (i % 4) * 0.4, 0, -0.3 + (i / 4) * 0.4), rng.randf_range(0, 360), "metal", "", false, 0.0)
	kit.box_geo("fence", Vector3(2.0, 1.3, 1.2), Transform3D(Basis.IDENTITY, cage + Vector3(-0.4, 0.65, 0)), Color.WHITE, 0.0, "detail")
	kit.box_geo("steel", Vector3(2.1, 0.06, 1.3), Transform3D(Basis.IDENTITY, cage + Vector3(-0.4, 1.33, 0)), Color(0.4, 0.4, 0.38))
	kit.solid(Vector3(2.0, 1.3, 1.2), Transform3D(Basis.IDENTITY, cage + Vector3(-0.4, 0.65, 0)), "metal", true)
	# --- warehouse exterior: utility boxes + conduit, extinguishers, dumpsters
	for z: float in [-30.0, -27.5, -15.0]:
		P(kit, "utility_box_01", Vector3(17.55, 0, z), -90.0, "metal", "box", false, 0.6)
	kit.pipe("steel", Vector3(17.7, 1.1, -30.0), Vector3(17.7, 4.6, -30.0), 0.05, Color(0.5, 0.5, 0.48), 6)
	kit.pipe("steel", Vector3(17.7, 4.6, -30.0), Vector3(17.7, 4.6, -12.0), 0.05, Color(0.5, 0.5, 0.48), 6)
	for fx: Vector3 in [Vector3(17.6, 1.0, -40.2), Vector3(29.3, 1.0, 6.5), Vector3(59.6, 1.0, -17.5), Vector3(21.7, 1.0, -21.0)]:
		kit.prop("fire_extinguisher_01", fx - Vector3(0, 1.0, 0) + Vector3(0, 0.9, 0), 90.0, "metal", "", false)
	for dp in [[Vector3(36.0, 0, 8.3), 0.0, Color(0.18, 0.35, 0.22)], [Vector3(61.8, 0, -40.0), 90.0, Color(0.2, 0.28, 0.45)], [Vector3(22.0, 0, -50.2), 0.0, Color(0.18, 0.35, 0.22)]]:
		_dumpster(kit, dp[0], dp[1], dp[2])
	# --- east alley: cardboard piles, pallets, tyres
	for i in 5:
		P(kit, "cardboard_box_01", Vector3(61.5 + rng.randf_range(-0.6, 0.6), rng.randi() % 2 * 0.34, -8.0 + rng.randf_range(-1.0, 1.0)), rng.randf_range(0, 360), "wood", "box", false, 0.0)
	Bld.loaded_pallet(kit, Vector3(61.9, 0, 18.0), 90.0, 1, 1.1, true)
	tire_stack(kit, Vector3(62.3, 0, -24.0), 4)
	# --- north service road (enemy side): barricades + debris
	barrier_line(kit, Vector3(-38.0, 0, -54.5), 4, 8.0)
	barrier_line(kit, Vector3(-14.0, 0, -53.0), 3, -12.0)
	barrier_line(kit, Vector3(0.0, 0, -56.5), 2, 30.0, false)
	barrels(kit, Vector3(-24.5, 0, -58.5), 5, 0.5)
	Bld.loaded_pallet(kit, Vector3(6.0, 0, -52.0), 20.0, 0, 1.2, true)
	cable_drum(kit, Vector3(24.0, 0, -58.0), 0.0)
	P(kit, "jerrycan_01", Vector3(47.0, 0, -52.5), 20.0, "metal", "box", false, 0.0)
	P(kit, "jerrycan_01", Vector3(47.4, 0, -52.3), 80.0, "metal", "box", false, 0.0)
	# --- truck yard (spawn): barriers funnel, pallets
	barrier_line(kit, Vector3(-14.0, 0, 46.0), 3, 0.0)
	barrier_line(kit, Vector3(3.0, 0, 45.5), 2, 0.0, false)
	Bld.loaded_pallet(kit, Vector3(-12.0, 0, 60.5), 0.0, 0, 1.0, true)
	Bld.loaded_pallet(kit, Vector3(-13.4, 0, 60.6), 3.0, 1, 1.2, true)
	barrels(kit, Vector3(-38.0, 0, 44.0), 4, 0.2)
	# --- office surroundings
	for bp: Vector3 in [Vector3(21.0, 0, 48.0), Vector3(39.5, 0, 48.0)]:
		kit.block("wood", Vector3(1.8, 0.08, 0.45), bp + Vector3(0, 0.45, 0), Vector3.ZERO, "wood", Color(0.7, 0.6, 0.5), 0.01)
		kit.box_geo("steel", Vector3(1.7, 0.42, 0.06), Transform3D(Basis.IDENTITY, bp + Vector3(0, 0.21, 0)), Color(0.2, 0.2, 0.2), 0.0, "detail")
	# warehouse loading dock pallets outside the south doors
	Bld.loaded_pallet(kit, Vector3(24.0, 0, 9.5), 0.0, 0, 1.2, true)
	Bld.loaded_pallet(kit, Vector3(25.4, 0, 9.7), 5.0, 2, 1.0, true)
	Bld.loaded_pallet(kit, Vector3(46.5, 0, 9.2), -3.0, 1, 1.3, true)


static func _dumpster(kit: WKit, p: Vector3, yaw: float, col: Color) -> void:
	var bs := Basis(Vector3.UP, deg_to_rad(yaw))
	var xf := Transform3D(bs, p)
	kit.box_geo("steel", Vector3(1.9, 1.2, 1.2), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0)), col, 0.03)
	kit.box_geo("steel", Vector3(1.95, 0.06, 1.3), xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0, 1.35, 0.05)), col * 0.8, 0.0)
	for sx: float in [-0.8, 0.8]:
		for sz: float in [-0.45, 0.45]:
			kit.cyl_geo("rubber", 0.07, 0.06, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx, 0.07, sz)), Color(0.1, 0.1, 0.1), 8, "detail")
	kit.solid(Vector3(1.9, 1.4, 1.2), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0)), "metal", true)
	kit.ground_quad("blob", p, Vector2(2.6, 1.9), yaw, Color(0.25, 0.24, 0.22, 0.85), Vector2(0, 0.5))


# ------------------------------------------------------------------ vehicles
static func truck(kit: WKit, L, p: Vector3, yaw: float, cont_col: Color, cab_col: Color) -> void:
	var bs := Basis(Vector3.UP, deg_to_rad(yaw))
	var xf := Transform3D(bs, p)
	var dk := Color(0.1, 0.1, 0.1)
	# trailer chassis + container (length along local z; cab at -z)
	kit.box_geo("steel", Vector3(1.0, 0.3, 12.0), xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.05, 1.5)), Color(0.2, 0.2, 0.2))
	C.build(kit, xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.22, 1.6)), C.L40, cont_col)
	kit.solid(Vector3(C.W, C.H, C.L40), xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.22 + C.H * 0.5, 1.6)), "metal", true)
	kit.solid(Vector3(2.4, 1.22, 3.0), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.61, 6.0)), "metal")
	for az: float in [5.2, 6.5]:
		for sx: float in [-1.0, 1.0]:
			kit.cyl_geo("rubber", 0.5, 0.55, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 0.95, 0.5, az)), dk, 14)
	for sx: float in [-0.9, 0.9]:
		kit.box_geo("steel", Vector3(0.15, 1.0, 0.15), xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.55, -2.5)), Color(0.3, 0.3, 0.3))
	# tractor unit
	var cab := xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, -6.4))
	kit.box_geo("steel", Vector3(2.45, 2.0, 2.2), cab * Transform3D(Basis.IDENTITY, Vector3(0, 2.1, -0.4)), cab_col, 0.06)
	kit.box_geo("glass", Vector3(2.3, 0.85, 0.05), cab * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8.0)), Vector3(0, 2.55, -1.52)), Color.WHITE)
	for sx: float in [-1.0, 1.0]:
		kit.box_geo("glass", Vector3(0.05, 0.7, 0.9), cab * Transform3D(Basis.IDENTITY, Vector3(sx * 1.23, 2.5, -0.9)), Color.WHITE)
		kit.box_geo("steel", Vector3(0.08, 0.35, 0.2), cab * Transform3D(Basis.IDENTITY, Vector3(sx * 1.35, 2.5, -1.4)), dk)
		kit.cyl_geo("rubber", 0.5, 0.5, cab * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.0, 0.5, -0.8)), dk, 14)
		kit.cyl_geo("rubber", 0.5, 0.5, cab * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.0, 0.5, 2.3)), dk, 14)
	kit.box_geo("steel", Vector3(2.4, 0.9, 1.3), cab * Transform3D(Basis.IDENTITY, Vector3(0, 0.95, -0.9)), cab_col * 0.8, 0.05)
	kit.box_geo("steel", Vector3(2.3, 0.35, 0.2), cab * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, -1.6)), Color(0.55, 0.55, 0.55))
	kit.box_geo("steel", Vector3(1.0, 0.3, 3.8), cab * Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 1.2)), Color(0.18, 0.18, 0.18))
	kit.pipe("steel", cab * Vector3(1.05, 1.2, 0.8), cab * Vector3(1.05, 3.6, 0.8), 0.08, Color(0.6, 0.6, 0.6), 8)
	kit.solid(Vector3(2.5, 3.1, 4.9), cab * Transform3D(Basis.IDENTITY, Vector3(0, 1.55, 0.3)), "metal", true)
	kit.ground_quad("blob", p + bs * Vector3(0, 0, -1.0), Vector2(3.4, 17.5), yaw, Color(0.3, 0.29, 0.27, 0.85), Vector2(0, 0.4))
	kit.ground_quad("blob", p + bs * Vector3(0.3, 0, -5.5), Vector2(2.0, 2.4), yaw, Color(0.12, 0.11, 0.1, 0.6), Vector2(1, 0.8))


static func car(kit: WKit, p: Vector3, yaw: float, col: Color) -> void:
	var bs := Basis(Vector3.UP, deg_to_rad(yaw))
	var xf := Transform3D(bs, p)
	kit.box_geo("steel", Vector3(1.8, 0.62, 4.5), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.62, 0)), col, 0.08)
	kit.box_geo("steel", Vector3(1.6, 0.55, 2.3), xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0.2)), col * 0.95, 0.12)
	kit.box_geo("glass", Vector3(1.62, 0.42, 2.1), xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.22, 0.2)), Color.WHITE)
	for sx: float in [-0.82, 0.82]:
		for sz: float in [-1.4, 1.45]:
			kit.cyl_geo("rubber", 0.33, 0.24, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx, 0.33, sz)), Color(0.08, 0.08, 0.08), 12, "detail")
	kit.box_geo("emit_red", Vector3(1.5, 0.08, 0.03), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 2.26)), Color.WHITE, 0.0, "detail")
	kit.solid(Vector3(1.8, 1.45, 4.5), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.73, 0)), "metal", true)
	kit.ground_quad("blob", p, Vector2(2.4, 5.2), yaw, Color(0.25, 0.24, 0.22, 0.85), Vector2(0, 0.5))


static func _vehicles(kit: WKit, L) -> void:
	truck(kit, L, Vector3(15.6, 0, 16.0), 180.0 + 1.5, C.color(kit, "maersk"), Color(0.62, 0.12, 0.1))
	truck(kit, L, Vector3(-30.0, 0, 55.5), 90.0, C.color(kit, "rust"), Color(0.8, 0.78, 0.74))
	Bld.forklift(kit, L, Vector3(11.5, 0, -22.0), -80.0, 0.6)
	car(kit, Vector3(44.0, 0, 41.0), 3.0, Color(0.32, 0.34, 0.36))
	car(kit, Vector3(47.0, 0, 41.3), -2.0, Color(0.55, 0.52, 0.48))
	car(kit, Vector3(55.0, 0, 52.0), 88.0, Color(0.12, 0.16, 0.22))


# ------------------------------------------------------------------ lighting
static func floodmast(kit: WKit, L, p: Vector3, aim_yaw: float, min_q := 1) -> void:
	var h := 16.0
	kit.cyl_geo("steel", 0.22, h, Transform3D(Basis.IDENTITY, p + Vector3(0, h * 0.5, 0)), Color(0.6, 0.6, 0.58), 10, "", false, 0.14)
	kit.cyl_geo("concrete", 0.5, 0.5, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.25, 0)), Color(0.7, 0.68, 0.65), 12)
	kit.solid_cyl(0.5, 0.5, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.25, 0)), "concrete")
	kit.solid_cyl(0.22, h, Transform3D(Basis.IDENTITY, p + Vector3(0, h * 0.5, 0)), "metal")
	var bs := Basis(Vector3.UP, deg_to_rad(aim_yaw))
	kit.box_geo("steel", Vector3(3.2, 0.12, 0.12), Transform3D(bs, p + Vector3(0, h, 0)), Color(0.4, 0.4, 0.4))
	kit.box_geo("steel", Vector3(3.2, 0.12, 0.12), Transform3D(bs, p + Vector3(0, h + 0.9, 0)), Color(0.4, 0.4, 0.4))
	for i in 4:
		var hp := p + Vector3(0, h + 0.45, 0) + bs * Vector3(-1.2 + i * 0.8, 0, 0.25)
		var hb := bs * Basis(Vector3.RIGHT, deg_to_rad(-35.0))
		kit.box_geo("steel", Vector3(0.6, 0.45, 0.25), Transform3D(hb, hp), Color(0.3, 0.3, 0.3))
		kit.box_geo("emit_warm", Vector3(0.5, 0.36, 0.02), Transform3D(hb, hp + hb * Vector3(0, 0, 0.13)), Color.WHITE, 0.0, "noshadow")
	var aim := bs * Vector3(0, -0.8, 1.0)
	L.add_spot(p + Vector3(0, h + 0.2, 0) + bs * Vector3(0, 0, 0.6), aim, Color(1.0, 0.8, 0.55), 5.0, 38.0, 52.0, min_q)


static func _lighting(kit: WKit, L) -> void:
	# street lamps along the road (dusk: on) + office path
	var lamp := kit.load_prop("street_lamp_01")
	if not lamp.has("lit"):
		var mesh: Mesh = lamp.parts[0][0].duplicate()
		var bulb := StandardMaterial3D.new()
		bulb.albedo_color = Color(1.0, 0.85, 0.6)
		bulb.emission_enabled = true
		bulb.emission = Color(1.0, 0.72, 0.4)
		bulb.emission_energy_multiplier = 8.0
		mesh.surface_set_material(2, bulb)
		var gm := mesh.surface_get_material(1)
		if gm is BaseMaterial3D:
			var g2: BaseMaterial3D = gm.duplicate()
			g2.emission_enabled = true
			g2.emission = Color(1.0, 0.7, 0.4)
			g2.emission_energy_multiplier = 1.5
			mesh.surface_set_material(1, g2)
		lamp.parts[0][0] = mesh
		lamp["lit"] = true
	var warm := Color(1.0, 0.7, 0.42)
	var zs := [-40.0, -24.0, -8.0, 8.0, 24.0, 40.0]
	for i in zs.size():
		var p := Vector3(8.9, 0, zs[i])
		P(kit, "street_lamp_01", p, 0.0, "metal", "cyl", false, 0.5)
		L.add_omni(p + Vector3(0, 3.1, 0), warm, 1.6, 11.0, 1 if i % 2 == 0 else 2)
	for p: Vector3 in [Vector3(21.0, 0, 32.5), Vector3(39.2, 0, 32.5), Vector3(39.2, 0, 47.5), Vector3(-2.0, 0, 50.0)]:
		P(kit, "street_lamp_01", p, 0.0, "metal", "cyl", false, 0.5)
		L.add_omni(p + Vector3(0, 3.1, 0), warm, 1.4, 10.0, 2)
	# floodlight masts
	floodmast(kit, L, Vector3(-43.5, 0, -8.0), 90.0 + 180.0, 1)
	floodmast(kit, L, Vector3(-43.5, 0, 47.0), 90.0 + 180.0, 2)
	floodmast(kit, L, Vector3(-32.25, 0, -32.0), 0.0, 2)
	floodmast(kit, L, Vector3(5.5, 0, 44.0), 180.0 + 20.0, 1)
	floodmast(kit, L, Vector3(40.0, 0, -61.0), 180.0, 2)
	# wall packs over warehouse doors (warm sodium)
	for wp in [[Vector3(17.6, 5.8, -8.0), Vector3(-1, -1, 0)], [Vector3(17.6, 5.8, -36.0), Vector3(-1, -1, 0)], [Vector3(28.0, 6.3, 6.4), Vector3(0, -1, 1)], [Vector3(39.0, 6.3, -48.4), Vector3(0, -1, -1)]]:
		kit.box_geo("steel", Vector3(0.45, 0.3, 0.3), Transform3D(Basis.IDENTITY, wp[0]), Color(0.25, 0.25, 0.25))
		kit.box_geo("emit_warm", Vector3(0.36, 0.04, 0.2), Transform3D(Basis.IDENTITY, wp[0] + Vector3(0, -0.16, 0)), Color.WHITE, 0.0, "noshadow")
		L.add_spot(wp[0] + Vector3(0, -0.2, 0), wp[1], Color(1.0, 0.68, 0.38), 3.0, 12.0, 60.0, 2)


# ------------------------------------------------------------------ signage
static func sign_board(kit: WKit, L, pos: Vector3, yaw: float, text: String, bg: Color, fg: Color, size := Vector2(1.2, 0.6), post := true, font_px := 0.0045) -> void:
	var bs := Basis(Vector3.UP, deg_to_rad(yaw))
	kit.box_geo("steel", Vector3(size.x, size.y, 0.03), Transform3D(bs, pos), bg)
	if post:
		kit.box_geo("steel", Vector3(0.07, pos.y, 0.07), Transform3D(bs, Vector3(pos.x, pos.y * 0.5, pos.z) + bs * Vector3(0, 0, -0.05)), Color(0.5, 0.5, 0.5))
	var lab := Label3D.new()
	lab.text = text
	lab.font = load(FONT_PATH)
	lab.font_size = 72
	lab.pixel_size = font_px
	lab.modulate = fg
	lab.shaded = true
	lab.double_sided = false
	lab.position = pos + bs * Vector3(0, 0, 0.02)
	lab.rotation_degrees = Vector3(0, yaw, 0)
	L.geo.add_child(lab)


static func _signs(kit: WKit, L) -> void:
	var yel := Color(0.85, 0.66, 0.1)
	var blk := Color(0.06, 0.06, 0.06)
	sign_board(kit, L, Vector3(-42.6, 2.6, -2.0), 90.0, "BERTH 7\nQUAY LIMIT 40 t/m²", Color(0.1, 0.22, 0.42), Color(0.92, 0.92, 0.9), Vector2(1.8, 1.0))
	sign_board(kit, L, Vector3(8.5, 2.2, 45.0), 90.0, "SPEED\nLIMIT 10", Color(0.9, 0.9, 0.88), blk, Vector2(0.8, 0.9))
	sign_board(kit, L, Vector3(30.0, 1.8, -52.8), 0.0, "NO SMOKING\nFLAMMABLE", yel, blk, Vector2(1.2, 0.7))
	sign_board(kit, L, Vector3(-42.6, 2.2, -30.0), 90.0, "DANGER\nCRANE OPERATING", yel, blk, Vector2(1.3, 0.7))
	sign_board(kit, L, Vector3(-7.0, 2.4, 61.5), 180.0, "GATE 2\nALL VISITORS REPORT", Color(0.1, 0.22, 0.42), Color(0.92, 0.92, 0.9), Vector2(1.6, 0.8))
	sign_board(kit, L, Vector3(18.0 - 0.21, 3.5, -22.3), -90.0, "AUTHORISED\nPERSONNEL ONLY", Color(0.75, 0.12, 0.1), Color(0.95, 0.95, 0.92), Vector2(1.1, 0.6), false)
	sign_board(kit, L, Vector3(40.0, 1.6, 36.8), 180.0, "COMPRESSED GAS", yel, blk, Vector2(1.0, 0.4), false, 0.0035)


# ------------------------------------------------------------------ particles / atmosphere
static func _billboard_mat(tex_path: String, additive: bool, col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	if tex_path != "":
		m.albedo_texture = load(tex_path)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


static func smoke_plume(L, p: Vector3, scale: float, col: Color, amount := 36, min_q := 1, life := 16.0) -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	qm.material = _billboard_mat("res://assets/textures/fx/smoke.png", false, Color.WHITE)
	ps.mesh = qm
	ps.amount = amount
	ps.lifetime = life
	ps.preprocess = life
	ps.local_coords = false
	ps.position = p
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = 1.2 * scale
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 12.0
	ps.initial_velocity_min = 1.6 * scale
	ps.initial_velocity_max = 2.4 * scale
	ps.gravity = Vector3(0.5 * scale, 0.15 * scale, -0.12 * scale)
	ps.damping_min = 0.05
	ps.damping_max = 0.12
	ps.angle_min = 0.0
	ps.angle_max = 360.0
	ps.angular_velocity_min = -8.0
	ps.angular_velocity_max = 8.0
	ps.scale_amount_min = 3.0 * scale
	ps.scale_amount_max = 4.5 * scale
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 2.6))
	ps.scale_amount_curve = sc
	var gr := Gradient.new()
	gr.set_color(0, Color(col.r, col.g, col.b, 0.0))
	gr.set_color(1, Color(col.r * 1.2, col.g * 1.2, col.b * 1.2, 0.0))
	gr.add_point(0.12, Color(col.r, col.g, col.b, col.a))
	gr.add_point(0.6, Color(col.r * 1.1, col.g * 1.1, col.b * 1.1, col.a * 0.55))
	ps.color_ramp = gr
	L.geo.add_child(ps)
	L.tier(ps, min_q)
	return ps


static func _particles(kit: WKit, L) -> void:
	# ambient dust motes that follow the camera
	var d := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.025)
	qm.material = _billboard_mat("res://assets/textures/fx/smoke_02.png", true, Color(1.0, 0.85, 0.65))
	d.mesh = qm
	d.amount = 140
	d.lifetime = 9.0
	d.preprocess = 9.0
	d.local_coords = false
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	d.emission_box_extents = Vector3(12, 4, 12)
	d.direction = Vector3(1, 0.1, 0)
	d.spread = 180.0
	d.initial_velocity_min = 0.05
	d.initial_velocity_max = 0.25
	d.gravity = Vector3(0.05, -0.01, 0.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.5, Color(1, 0.9, 0.75, 0.5))
	d.color_ramp = gr
	d.scale_amount_min = 0.6
	d.scale_amount_max = 1.6
	L.geo.add_child(d)
	L.dust = d
	# burning barrel: flames + smoke + flicker light
	var camp := Vector3(-19.5, 0.93, 16.5)
	var f := CPUParticles3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(0.55, 0.8)
	fm.material = _billboard_mat("res://assets/textures/fx/flame_kenney.png", true, Color(1.0, 0.55, 0.2) * 2.2)
	f.mesh = fm
	f.amount = 16
	f.lifetime = 0.7
	f.local_coords = false
	f.position = camp
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = 0.18
	f.direction = Vector3(0, 1, 0)
	f.spread = 10.0
	f.initial_velocity_min = 0.6
	f.initial_velocity_max = 1.2
	f.gravity = Vector3(0, 0.6, 0)
	f.scale_amount_min = 0.6
	f.scale_amount_max = 1.1
	var fg := Gradient.new()
	fg.set_color(0, Color(1, 0.8, 0.5, 0.0))
	fg.set_color(1, Color(0.6, 0.2, 0.05, 0.0))
	fg.add_point(0.2, Color(1, 0.7, 0.35, 1.0))
	f.color_ramp = fg
	L.geo.add_child(f)
	L.tier(f, 0)
	smoke_plume(L, camp + Vector3(0, 0.8, 0), 0.25, Color(0.18, 0.17, 0.16, 0.5), 18, 1, 7.0)
	L.add_omni(camp + Vector3(0, 0.7, 0), Color(1.0, 0.55, 0.22), 2.2, 7.5, 1, "fire")
	# big dark smoke column beyond the north wall (burning ship / warehouse) + industrial chimneys far away
	smoke_plume(L, Vector3(-18.0, 4.0, -118.0), 3.2, Color(0.08, 0.075, 0.07, 0.75), 40, 1, 22.0)
	smoke_plume(L, Vector3(-6.0, 2.0, -112.0), 2.2, Color(0.1, 0.09, 0.085, 0.6), 24, 2, 18.0)
	for ch in L.get_meta("chimneys", []):
		smoke_plume(L, ch, 3.0, Color(0.62, 0.58, 0.55, 0.45), 24, 1, 20.0)
	# sparks from a broken cable on the warehouse west wall
	var sp_pos := Vector3(17.55, 4.4, -26.0)
	kit.pipe("rubber", Vector3(17.7, 4.6, -26.8), sp_pos, 0.03, Color(0.1, 0.1, 0.1), 5)
	kit.pipe("rubber", sp_pos, sp_pos + Vector3(-0.2, -0.6, 0.2), 0.03, Color(0.1, 0.1, 0.1), 5)
	var s := CPUParticles3D.new()
	var sm := QuadMesh.new()
	sm.size = Vector2(0.12, 0.03)
	var smat := _billboard_mat("res://assets/textures/fx/spark.png", true, Color(1.0, 0.8, 0.45) * 3.0)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.material = smat
	s.mesh = sm
	s.amount = 28
	s.lifetime = 0.9
	s.one_shot = true
	s.explosiveness = 0.92
	s.emitting = false
	s.local_coords = false
	s.position = sp_pos + Vector3(-0.2, -0.6, 0.2)
	s.direction = Vector3(-1, 0.4, 0)
	s.spread = 70.0
	s.initial_velocity_min = 1.5
	s.initial_velocity_max = 4.5
	s.gravity = Vector3(0, -9.8, 0)
	s.scale_amount_min = 0.6
	s.scale_amount_max = 1.4
	L.geo.add_child(s)
	L.tier(s, 1)
	var sl := OmniLight3D.new()
	sl.position = sp_pos + Vector3(-0.5, -0.5, 0.2)
	sl.light_color = Color(0.7, 0.8, 1.0)
	sl.light_energy = 0.0
	sl.omni_range = 5.0
	L.geo.add_child(sl)
	L.tier(sl, 2)
	L.sparks.append([s, sl])
