extends RefCounted
## DOCKYARD buildings: warehouse (CQB interior with racking, clerestory sun shafts, trusses, portacabin),
## two-storey office/control building (interior + exterior stair), gate booth. Walls are built from boxes
## around openings, each with collision and surface meta.

const WKit := preload("res://scripts/world/wkit.gd")
const Layout := preload("res://scripts/world/dock_layout.gd")

# ------------------------------------------------------------------ walls with openings
## Wall from a to b (ground points), `outside` = direction of the exterior face. openings = [[u0, u1, v0, v1, kind(, arg)]]
## in metres along the wall from a (u) and above base.y (v). kind: "open", "door", "win", "shutter" (arg = bottom of shutter).
## mats = [outer_lo, outer_hi, inner_lo, inner_hi], split = height of the lo/hi material change.
static func wall(kit: WKit, a: Vector3, b: Vector3, h: float, t: float, openings: Array, mats: Array, split: float, surf := ["concrete", "metal"], outside := Vector3.ZERO, col := Color.WHITE) -> void:
	var d := b - a
	d.y = 0.0
	var length := d.length()
	var dn := d / length
	var nrm := dn.cross(Vector3.UP)
	if outside != Vector3.ZERO and nrm.dot(outside) < 0.0:
		nrm = -nrm
	var bs := Basis(dn, Vector3.UP, dn.cross(Vector3.UP))
	var cuts := [0.0, length]
	for o in openings:
		cuts.append(clampf(o[0], 0.0, length))
		cuts.append(clampf(o[1], 0.0, length))
	cuts.sort()
	var t_out := t * 0.62
	var t_in := t - t_out
	for i in cuts.size() - 1:
		var u0: float = cuts[i]
		var u1: float = cuts[i + 1]
		if u1 - u0 < 0.005:
			continue
		var um := (u0 + u1) * 0.5
		var holes := []
		for o in openings:
			if um > o[0] and um < o[1]:
				holes.append([o[2], o[3]])
		holes.sort_custom(func(x, y): return x[0] < y[0])
		var pieces := []
		var v := 0.0
		for hh in holes:
			if hh[0] > v + 0.005:
				pieces.append([v, hh[0]])
			v = maxf(v, hh[1])
		if v < h - 0.005:
			pieces.append([v, h])
		for pc in pieces:
			var ranges := []
			if pc[0] < split and pc[1] > split:
				ranges = [[pc[0], split, 0], [split, pc[1], 1]]
			else:
				ranges = [[pc[0], pc[1], 0 if pc[1] <= split + 0.001 else 1]]
			for r in ranges:
				var hgt: float = r[1] - r[0]
				var center: Vector3 = a + dn * um + Vector3(0, a.y + r[0] + hgt * 0.5, 0)
				center.y = a.y + r[0] + hgt * 0.5
				var lo_hi: int = r[2]
				var mo: String = mats[lo_hi]
				var mi: String = mats[2 + lo_hi] if mats.size() > 2 + lo_hi else mo
				kit.box_geo(mo, Vector3(u1 - u0, hgt, t_out), Transform3D(bs, center + nrm * (t * 0.5 - t_out * 0.5)), col)
				kit.box_geo(mi, Vector3(u1 - u0, hgt, t_in), Transform3D(bs, center - nrm * (t * 0.5 - t_in * 0.5)), Color.WHITE)
				kit.solid(Vector3(u1 - u0, hgt, t), Transform3D(bs, center), surf[lo_hi])
	# opening trims: frames, mullions, shutters (positions relative to the flattened start point)
	var base_y := a.y
	a = Vector3(a.x, 0.0, a.z)
	for o in openings:
		var u0: float = o[0]
		var u1: float = o[1]
		var v0: float = o[2]
		var v1: float = o[3]
		var kind: String = o[4]
		var w := u1 - u0
		var c := a + dn * ((u0 + u1) * 0.5)
		var fc := Color(0.3, 0.31, 0.32)
		if kind == "win":
			kit.box_geo("steel", Vector3(w + 0.1, 0.08, t + 0.12), Transform3D(bs, c + Vector3(0, base_y + v0 - 0.04, 0) + nrm * 0.04), Color(0.55, 0.55, 0.52), 0.0, "detail")
			var n := maxi(1, int(round(w / 1.2)))
			for k in range(1, n):
				var p := a + dn * (u0 + w * k / n) + Vector3(0, base_y + (v0 + v1) * 0.5, 0)
				kit.box_geo("steel", Vector3(0.06, v1 - v0, 0.08), Transform3D(bs, p + nrm * (t * 0.3)), fc, 0.0, "detail")
			kit.box_geo("steel", Vector3(w, 0.05, 0.06), Transform3D(bs, c + Vector3(0, base_y + (v0 + v1) * 0.5, 0) + nrm * (t * 0.3)), fc, 0.0, "detail")
		elif kind == "door" or kind == "open" or kind == "shutter":
			for s: float in [0.0, 1.0]:
				var p := a + dn * (u0 + (w if s > 0.5 else 0.0)) + Vector3(0, base_y + (v1) * 0.5, 0)
				kit.box_geo("steel", Vector3(0.12, v1, t + 0.1), Transform3D(bs, p), Color(0.62, 0.5, 0.14) if kind != "door" else fc, 0.0)
			kit.box_geo("steel", Vector3(w + 0.24, 0.14, t + 0.1), Transform3D(bs, c + Vector3(0, base_y + v1 + 0.07, 0)), fc)
			if kind == "shutter":
				var bot: float = o[5]
				var sh := v1 - bot
				var sc := c + Vector3(0, base_y + bot + sh * 0.5, 0) + nrm * (t * 0.5 + 0.03)
				kit.box_geo("cladding", Vector3(w, sh, 0.05), Transform3D(bs, sc), Color(0.72, 0.7, 0.62))
				kit.box_geo("steel", Vector3(w, 0.12, 0.08), Transform3D(bs, c + Vector3(0, base_y + bot + 0.06, 0) + nrm * (t * 0.5 + 0.05)), Color(0.25, 0.25, 0.25))
				kit.solid(Vector3(w, sh, 0.1), Transform3D(bs, sc), "metal")
				kit.box_geo("steel", Vector3(w + 0.4, 0.6, 0.6), Transform3D(bs, c + Vector3(0, base_y + v1 + 0.45, 0) + nrm * (t * 0.5 + 0.3)), Color(0.5, 0.5, 0.48))


static func _tri2(kit: WKit, mat: String, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var bt: Dictionary = kit.batch(mat, (a + b + c) / 3.0)
	kit.tri(bt, a, b, c, col)
	kit.tri(bt, a, c, b, col)


static func build(kit: WKit, L) -> void:
	_warehouse(kit, L)
	_office(kit, L)
	_booth(kit, L)
	_pump_house(kit, L)


# ------------------------------------------------------------------ warehouse
const WX0 := 18.0
const WX1 := 60.0
const WZ0 := -48.0
const WZ1 := 6.0
const WH := 10.0
const RIDGE := 12.2


static func _warehouse(kit: WKit, L) -> void:
	var mats := ["brick", "cladding", "concrete_dark", "cladding_dark"]
	var t := 0.36
	var split := 3.0
	var win_v := [6.6, 8.6]
	# west wall (faces the yard + the setting sun): clerestory glazing lets the sun in
	var west_open := [[11.0, 17.0, 0.0, 5.0, "shutter", 2.7], [27.8, 29.0, 0.0, 2.2, "door"], [39.0, 45.0, 0.0, 5.0, "open"]]
	for k in 9:
		west_open.append([1.3 + k * 6.0, 4.7 + k * 6.0, win_v[0], win_v[1], "win"])
	wall(kit, Vector3(WX0, 0, WZ1), Vector3(WX0, 0, WZ0), WH, t, west_open, mats, split, ["concrete", "metal"], Vector3.LEFT)
	var south_open := [[7.0, 13.0, 0.0, 5.5, "open"], [26.0, 32.0, 0.0, 5.5, "shutter", 3.2]]
	for u in [[1.0, 5.0], [15.0, 24.0], [34.0, 41.0]]:
		south_open.append([u[0], u[1], win_v[0], win_v[1], "win"])
	wall(kit, Vector3(WX0, 0, WZ1), Vector3(WX1, 0, WZ1), WH, t, south_open, mats, split, ["concrete", "metal"], Vector3.BACK)
	wall(kit, Vector3(WX1, 0, WZ1), Vector3(WX1, 0, WZ0), WH, t, [[24.8, 26.0, 0.0, 2.2, "door"], [36.0, 44.0, win_v[0], win_v[1], "win"]], mats, split, ["concrete", "metal"], Vector3.RIGHT)
	wall(kit, Vector3(WX1, 0, WZ0), Vector3(WX0, 0, WZ0), WH, t, [[18.0, 24.0, 0.0, 5.5, "open"], [4.0, 12.0, win_v[0], win_v[1], "win"], [30.0, 38.0, win_v[0], win_v[1], "win"]], mats, split, ["concrete", "metal"], Vector3.FORWARD)
	# gables
	var xm := (WX0 + WX1) * 0.5
	for z: float in [WZ1, WZ0]:
		var zo := z + (0.0 if z > 0 else 0.0)
		_tri2(kit, "cladding", Vector3(WX0, WH, zo), Vector3(WX1, WH, zo), Vector3(xm, RIDGE, zo), Color.WHITE)
	# roof slabs (+ overhang) and ridge cap
	var run := xm - WX0 + 0.6
	var ang := atan2(RIDGE - WH, xm - WX0)
	var slen := run / cos(ang)
	for s: float in [-1.0, 1.0]:
		var bs := Basis(Vector3.BACK, -s * ang)
		var cx := xm + s * (run * 0.5)
		var cy := RIDGE - tan(ang) * run * 0.5 + 0.12
		kit.box_geo("cladding_dark", Vector3(slen, 0.22, WZ1 - WZ0 + 1.0), Transform3D(bs, Vector3(cx, cy, (WZ0 + WZ1) * 0.5)), Color(0.9, 0.9, 0.9))
		kit.solid(Vector3(slen, 0.22, WZ1 - WZ0 + 1.0), Transform3D(bs, Vector3(cx, cy, (WZ0 + WZ1) * 0.5)), "metal")
		# gutter
		kit.box_geo("steel", Vector3(0.25, 0.25, WZ1 - WZ0 + 1.0), Transform3D(Basis.IDENTITY, Vector3(xm + s * (run + 0.05), WH - 0.02, (WZ0 + WZ1) * 0.5)), Color(0.45, 0.45, 0.43))
		# skylight strip seen from inside
		kit.box_geo("emit_sky", Vector3(1.6, 0.04, WZ1 - WZ0 - 6.0), Transform3D(bs, Vector3(xm + s * 10.5, RIDGE - tan(ang) * 10.5 - 0.02, (WZ0 + WZ1) * 0.5)), Color.WHITE, 0.0, "noshadow")
	kit.box_geo("steel", Vector3(0.6, 0.2, WZ1 - WZ0 + 1.0), Transform3D(Basis.IDENTITY, Vector3(xm, RIDGE + 0.18, (WZ0 + WZ1) * 0.5)), Color(0.4, 0.4, 0.4))
	# columns + roof trusses every 6 m
	var tc := Color(0.28, 0.3, 0.32)
	var z := WZ1 - 6.0
	while z > WZ0 + 1.0:
		for x in [WX0 + 0.35, WX1 - 0.35]:
			kit.box_geo("steel", Vector3(0.3, WH, 0.3), Transform3D(Basis.IDENTITY, Vector3(x, WH * 0.5, z)), tc)
			kit.solid(Vector3(0.3, WH, 0.3), Transform3D(Basis.IDENTITY, Vector3(x, WH * 0.5, z)), "metal")
		var y0 := WH - 0.6
		kit.beam("steel", Vector3(WX0 + 0.3, y0, z), Vector3(WX1 - 0.3, y0, z), 0.16, tc)
		kit.beam("steel", Vector3(WX0 + 0.3, WH - 0.1, z), Vector3(xm, RIDGE - 0.15, z), 0.18, tc)
		kit.beam("steel", Vector3(WX1 - 0.3, WH - 0.1, z), Vector3(xm, RIDGE - 0.15, z), 0.18, tc)
		for k in range(1, 7):
			var xa := WX0 + 0.3 + (xm - WX0 - 0.3) * k / 7.0
			var ya := WH - 0.1 + (RIDGE - 0.15 - WH + 0.1) * k / 7.0
			kit.beam("steel", Vector3(xa, y0, z), Vector3(xa, ya, z), 0.08, tc, "detail")
			var xb := WX1 - 0.3 - (WX1 - 0.3 - xm) * k / 7.0
			kit.beam("steel", Vector3(xb, y0, z), Vector3(xb, ya, z), 0.08, tc, "detail")
		z -= 6.0
	# big painted identifiers
	for pz in [[WX0 - 0.19, -24.0, -90.0], [(WX0 + WX1) * 0.5, WZ1 + 0.19, 0.0]]:
		var lab := Label3D.new()
		lab.text = "W-3" if pz[2] < 0.0 else "IRONLINE  LOGISTICS  —  W-3"
		lab.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
		lab.font_size = 256
		lab.pixel_size = 0.03 if pz[2] < 0.0 else 0.011
		lab.modulate = Color(0.86, 0.84, 0.8, 0.9)
		lab.shaded = true
		lab.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		lab.position = Vector3(pz[0], 7.6 if pz[2] < 0.0 else 9.3, pz[1])
		lab.rotation_degrees = Vector3(0, pz[2], 0)
		L.geo.add_child(lab)
	_racks(kit, L)
	_warehouse_interior(kit, L)
	_sun_shafts(kit, L)


static func _pallet(kit: WKit, p: Vector3, yaw := 0.0, col := Color(0.8, 0.72, 0.6), detail := false) -> void:
	var bs := Basis(Vector3.UP, deg_to_rad(yaw))
	var xf := Transform3D(bs, p)
	if detail:
		for i in 5:
			kit.box_geo("wood", Vector3(1.2, 0.022, 0.1), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.133, -0.45 + i * 0.225)), col, 0.0, "detail")
		for i in 3:
			kit.box_geo("wood", Vector3(1.2, 0.022, 0.1), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.011, -0.45 + i * 0.45)), col * 0.9, 0.0, "detail")
			for j in 3:
				kit.box_geo("wood", Vector3(0.1, 0.1, 0.12), xf * Transform3D(Basis.IDENTITY, Vector3(-0.55 + j * 0.55, 0.072, -0.45 + i * 0.45)), col * 0.85, 0.0, "detail")
		return
	kit.box_geo("wood", Vector3(1.2, 0.024, 1.0), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.132, 0)), col, 0.0, "detail")
	for i in 3:
		kit.box_geo("wood", Vector3(1.2, 0.12, 0.1), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.06, -0.45 + i * 0.45)), col * 0.85, 0.0, "detail")


## Pallet with goods. kind: 0 cardboard stack, 1 wrapped, 2 drums, 3 crates. Returns total height.
static func loaded_pallet(kit: WKit, p: Vector3, yaw: float, kind: int, gh: float, collide := true) -> float:
	_pallet(kit, p, yaw)
	var bs := Basis(Vector3.UP, deg_to_rad(yaw))
	var top := p + Vector3(0, 0.144, 0)
	match kind:
		0:
			var rows := maxi(1, int(gh / 0.33))
			for r in rows:
				for cx in 2:
					for cz in 2:
						var v := kit.rng.randf_range(0.85, 1.05)
						var off := Vector3(-0.29 + cx * 0.58 + kit.rng.randf_range(-0.02, 0.02), 0.165 + r * 0.33, -0.24 + cz * 0.48)
						kit.box_geo("cardboard", Vector3(0.56, 0.32, 0.46), Transform3D(bs * Basis(Vector3.UP, kit.rng.randf_range(-0.04, 0.04)), top + bs * off), Color(v, v, v), 0.0, "detail")
			gh = rows * 0.33
		1:
			kit.box_geo("tarp", Vector3(1.16, gh, 0.98), Transform3D(bs, top + Vector3(0, gh * 0.5, 0)), Color(0.9, 0.92, 0.95), 0.06, "detail")
		2:
			for cx in 2:
				for cz in 2:
					kit.prop("barrel_02", top + bs * Vector3(-0.3 + cx * 0.6, 0, -0.25 + cz * 0.5) * 0.92, kit.rng.randf_range(0, 360), "metal", "", false)
			gh = 0.93
		3:
			kit.prop("military_crate_01", top, yaw + (90.0 if kit.rng.randf() < 0.5 else 0.0) * 0.0, "wood", "", false)
			kit.prop("military_crate_01", top + Vector3(0, 0.46, 0), yaw + kit.rng.randf_range(-8, 8), "wood", "", false)
			gh = 0.92
	if collide:
		kit.solid(Vector3(1.2, gh + 0.144, 1.0), Transform3D(bs, p + Vector3(0, (gh + 0.144) * 0.5, 0)), "wood", true)
	return gh + 0.144


static func rack_row(kit: WKit, L, x0: float, z0: float, bays: int, double := true) -> void:
	var bay := 2.75
	var depth := 1.1
	var levels := [0.0, 1.9, 3.7, 5.5]
	var up_col := Color(0.16, 0.26, 0.48)
	var beam_col := Color(0.85, 0.36, 0.08)
	var faces := [x0, x0 + depth] if not double else [x0, x0 + depth, x0 + depth + 0.2, x0 + 2.0 * depth + 0.2]
	var zlen := bays * bay
	var zc := z0 + zlen * 0.5
	# uprights
	for x in faces:
		for i in bays + 1:
			var z := z0 + i * bay
			kit.box_geo("steel", Vector3(0.09, 6.3, 0.07), Transform3D(Basis.IDENTITY, Vector3(x, 3.15, z)), up_col)
			kit.solid(Vector3(0.09, 6.3, 0.07), Transform3D(Basis.IDENTITY, Vector3(x, 3.15, z)), "metal")
	# frame bracing (per upright frame)
	var sides := [[x0, x0 + depth]] if not double else [[x0, x0 + depth], [x0 + depth + 0.2, x0 + 2.0 * depth + 0.2]]
	for sd in sides:
		for i in bays + 1:
			var z := z0 + i * bay
			for k in 4:
				var ya := 0.3 + k * 1.5
				kit.beam("steel", Vector3(sd[0], ya, z), Vector3(sd[1], ya + 1.5, z), 0.035, up_col, "detail")
		# beams at every level on both faces + goods
		for lv in levels.size():
			var y: float = levels[lv]
			if lv > 0:
				for x in sd:
					kit.box_geo("steel", Vector3(0.05, 0.12, zlen), Transform3D(Basis.IDENTITY, Vector3(x, y, zc)), beam_col)
				kit.box_geo("grate", Vector3(depth, 0.03, zlen), Transform3D(Basis.IDENTITY, Vector3((sd[0] + sd[1]) * 0.5, y + 0.06, zc)), Color.WHITE, 0.0, "detail")
				kit.solid(Vector3(depth, 0.14, zlen), Transform3D(Basis.IDENTITY, Vector3((sd[0] + sd[1]) * 0.5, y, zc)), "metal")
			for i in bays:
				var zb := z0 + (i + 0.5) * bay
				for slot in 2:
					var r := kit.rng.randf()
					if (lv == 0 and r < 0.18) or (lv > 0 and r < 0.3):
						continue
					var zp := zb + (slot - 0.5) * 1.3
					var kind := kit.rng.randi() % 4
					if lv > 1 and kind == 2:
						kind = 1
					var gh := kit.rng.randf_range(0.9, 1.3) if lv == 0 else kit.rng.randf_range(0.7, 1.45)
					loaded_pallet(kit, Vector3((sd[0] + sd[1]) * 0.5, y + (0.07 if lv > 0 else 0.0), zp), 90.0, kind, gh, true)
	kit.ground_quad("blob", Vector3((faces[0] + faces[faces.size() - 1]) * 0.5, 0.0, zc), Vector2(faces[faces.size() - 1] - faces[0] + 0.8, zlen + 0.6), 0.0, Color(0.4, 0.38, 0.36, 0.7), Vector2(0, 0.4))
	# end-of-row guard (yellow)
	for zz in [z0 - 0.35, z0 + zlen + 0.35]:
		kit.block("steel", Vector3(faces[faces.size() - 1] - faces[0] + 0.1, 0.4, 0.2), Vector3((faces[0] + faces[faces.size() - 1]) * 0.5, 0.2, zz), Vector3.ZERO, "metal", Color(0.8, 0.62, 0.1))


static func _racks(kit: WKit, L) -> void:
	rack_row(kit, L, 25.0, -44.0, 10)
	rack_row(kit, L, 33.0, -44.0, 5)
	rack_row(kit, L, 33.0, -24.5, 4)
	rack_row(kit, L, 41.0, -41.25, 10)
	rack_row(kit, L, 58.3, -44.0, 6, false)


static func forklift(kit: WKit, L, p: Vector3, yaw: float, fork_h := 0.1) -> void:
	var bs := Basis(Vector3.UP, deg_to_rad(yaw))
	var xf := Transform3D(bs, p)
	var yel := Color(0.85, 0.62, 0.1)
	var dk := Color(0.12, 0.12, 0.12)
	kit.box_geo("steel", Vector3(1.1, 0.9, 2.0), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0.1)), yel, 0.05)
	kit.box_geo("steel", Vector3(1.12, 0.7, 0.55), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0.95)), yel * 0.8, 0.08)
	kit.box_geo("rubber", Vector3(0.5, 0.35, 0.5), xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.35, 0.35)), dk, 0.04)
	kit.box_geo("rubber", Vector3(0.5, 0.5, 0.1), xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0.62)), dk, 0.03)
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.55, 0.75]:
			kit.beam("steel", xf * Vector3(sx, 1.2, sz), xf * Vector3(sx * 0.95, 2.15, sz * 0.9), 0.06, dk)
		kit.cyl_geo("rubber", 0.3, 0.25, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.05, 0.3, -0.55)), dk, 12)
		kit.cyl_geo("rubber", 0.25, 0.22, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.0, 0.25, 0.75)), dk, 12)
		kit.box_geo("steel", Vector3(0.1, 2.3, 0.12), xf * Transform3D(Basis.IDENTITY, Vector3(sx * 0.7, 1.2, -0.95)), dk)
		kit.box_geo("steel", Vector3(0.12, 0.05, 1.1), xf * Transform3D(Basis.IDENTITY, Vector3(sx * 0.4, fork_h + 0.03, -1.6)), dk)
		kit.box_geo("steel", Vector3(0.12, 0.6, 0.05), xf * Transform3D(Basis.IDENTITY, Vector3(sx * 0.4, fork_h + 0.3, -1.05)), dk)
	for gx in 5:
		kit.box_geo("steel", Vector3(0.03, 0.04, 1.35), xf * Transform3D(Basis.IDENTITY, Vector3(-0.44 + gx * 0.22, 2.17, 0.1)), dk)
	kit.box_geo("steel", Vector3(1.4, 0.1, 0.1), xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.3, -0.95)), dk)
	kit.box_geo("emit_red", Vector3(0.1, 0.08, 0.1), xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.22, 0.75)), Color.WHITE)
	kit.solid(Vector3(1.2, 2.2, 2.6), xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0.1)), "metal", true)
	kit.ground_quad("blob", p, Vector2(1.8, 3.4), yaw, Color(0.25, 0.24, 0.22, 0.85), Vector2(0, 0.5))


static func _warehouse_interior(kit: WKit, L) -> void:
	# staging area: pallets, crates, forklift, portacabin office
	forklift(kit, L, Vector3(38.5, 0, -3.5), 20.0, 0.1)
	forklift(kit, L, Vector3(30.2, 0, -27.0), 180.0 + 5.0, 1.9)
	var clusters := [
		[Vector3(24.0, 0, -3.0), 0, 1.2], [Vector3(25.4, 0, -3.0), 0, 1.1], [Vector3(24.0, 0, -1.6), 1, 1.3],
		[Vector3(31.5, 0, -8.5), 3, 1.0], [Vector3(32.8, 0, -8.6), 0, 0.7],
		[Vector3(44.0, 0, 0.5), 1, 1.2], [Vector3(45.3, 0, 0.8), 1, 1.0], [Vector3(44.2, 0, -0.9), 2, 1.0],
		[Vector3(49.5, 0, -18.0), 0, 1.2], [Vector3(50.8, 0, -18.2), 0, 1.3], [Vector3(49.6, 0, -19.4), 3, 1.0],
		[Vector3(51.0, 0, -32.0), 1, 1.1], [Vector3(52.3, 0, -32.2), 2, 1.0], [Vector3(51.2, 0, -30.6), 0, 1.0],
		[Vector3(22.0, 0, -45.0), 0, 1.1], [Vector3(29.5, 0, -46.5), 1, 1.2],
		[Vector3(38.0, 0, -11.0), 0, 1.1], [Vector3(55.0, 0, -12.0), 2, 1.0],
	]
	for c in clusters:
		loaded_pallet(kit, c[0], kit.rng.randf_range(-6, 6) + (90.0 if int(c[0].x) % 2 == 0 else 0.0), c[1], c[2], true)
	# empty pallet stacks
	for ps: Vector3 in [Vector3(21.5, 0, -8.0), Vector3(21.5, 0, -9.4), Vector3(56.5, 0, 3.5)]:
		var n := 4 + kit.rng.randi() % 5
		for i in n:
			_pallet(kit, ps + Vector3(kit.rng.randf_range(-0.04, 0.04), i * 0.145, 0), kit.rng.randf_range(-3, 3), Color(0.8, 0.72, 0.6), true)
		kit.solid(Vector3(1.2, n * 0.145, 1.0), Transform3D(Basis.IDENTITY, ps + Vector3(0, n * 0.145 * 0.5, 0)), "wood", true)
	# portacabin (site office) in the SE corner
	var pc := Vector3(54.5, 0, -4.0)
	kit.block("cladding", Vector3(6.06, 2.7, 2.6), pc + Vector3(0, 1.45, 0), Vector3.ZERO, "metal", Color(0.85, 0.84, 0.8), 0.0, true)
	kit.box_geo("steel", Vector3(6.2, 0.2, 2.7), Transform3D(Basis.IDENTITY, pc + Vector3(0, 0.1, 0)), Color(0.3, 0.3, 0.3))
	for wx: float in [-1.8, 0.6]:
		kit.box_geo("emit_window", Vector3(1.4, 0.9, 0.04), Transform3D(Basis.IDENTITY, pc + Vector3(wx, 1.8, -1.32)), Color.WHITE)
	kit.box_geo("steel", Vector3(0.9, 2.0, 0.05), Transform3D(Basis.IDENTITY, pc + Vector3(2.2, 1.2, -1.32)), Color(0.4, 0.42, 0.44))
	# hanging high-bay lamps + a few interior lights
	for lx: float in [22.0, 30.2, 38.2, 50.0]:
		for lz: float in [-40.0, -28.0, -16.0, -4.0]:
			kit.pipe("steel", Vector3(lx, 9.4, lz), Vector3(lx, 8.1, lz), 0.012, Color(0.2, 0.2, 0.2), 3, "detail")
			kit.cyl_geo("steel", 0.12, 0.5, Transform3D(Basis.IDENTITY, Vector3(lx, 8.0, lz)), Color(0.3, 0.3, 0.3), 8, "", false, 0.12)
			kit.cyl_geo("steel", 0.42, 0.35, Transform3D(Basis.IDENTITY, Vector3(lx, 7.65, lz)), Color(0.35, 0.36, 0.36), 12, "", false, 0.14)
			kit.cyl_geo("emit_cool", 0.36, 0.02, Transform3D(Basis.IDENTITY, Vector3(lx, 7.47, lz)), Color.WHITE, 12, "noshadow")
	var icol := Color(0.8, 0.88, 1.0)
	L.add_omni(Vector3(30.2, 7.0, -34.0), icol, 1.6, 17.0, 1)
	L.add_omni(Vector3(38.2, 7.0, -10.0), icol, 1.6, 17.0, 1)
	L.add_omni(Vector3(50.0, 7.0, -28.0), icol, 1.4, 17.0, 2)
	L.add_omni(Vector3(22.0, 7.0, -20.0), icol, 1.2, 15.0, 2)
	# flickering fluorescent tube near the portacabin
	var tube := MeshInstance3D.new()
	tube.mesh = MeshKit.bevel_box(Vector3(1.4, 0.06, 0.12), 0.01)
	tube.material_override = kit.mats["emit_cool"]
	tube.position = Vector3(50.5, 3.6, -6.0)
	L.geo.add_child(tube)
	kit.box_geo("steel", Vector3(1.5, 0.05, 0.2), Transform3D(Basis.IDENTITY, Vector3(50.5, 3.66, -6.0)), Color(0.3, 0.3, 0.3))
	L.add_omni(Vector3(50.5, 3.3, -6.0), Color(0.8, 0.92, 1.0), 1.4, 8.0, 1, "fluoro")
	L.flickers[L.flickers.size() - 1].append(tube)
	# exit signs over doors (inside)
	for es in [[Vector3(WX0 + 0.25, 5.9, -36.0), 90.0], [Vector3(28.0, 6.4, WZ1 - 0.25), 180.0], [Vector3(39.0, 6.4, WZ0 + 0.25), 0.0]]:
		kit.box_geo("emit_green", Vector3(0.6, 0.22, 0.05), Transform3D(Basis(Vector3.UP, deg_to_rad(es[1])), es[0]), Color.WHITE, 0.0, "noshadow")
	# interior ambient override: darker, cooler inside the shed
	var probe := ReflectionProbe.new()
	probe.position = Vector3((WX0 + WX1) * 0.5, 5.0, (WZ0 + WZ1) * 0.5)
	probe.size = Vector3(WX1 - WX0 - 0.4, 10.4, WZ1 - WZ0 - 0.4)
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.36, 0.4, 0.46)
	probe.ambient_color_energy = 0.55
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.max_distance = 60.0
	probe.blend_distance = 1.5
	L.geo.add_child(probe)


## Fake volumetric sunbeams through the west clerestory windows and the open west door.
static func _sun_shafts(kit: WKit, L) -> void:
	var dir: Vector3 = -L.sun_dir   # light travel direction
	var col := Color(1.0, 0.72, 0.45, 0.07)
	var windows := []
	for k in 9:
		var zc := WZ1 - (3.0 + k * 6.0)
		windows.append([Vector3(WX0, 7.6, zc), 3.4, 2.0])
	windows.append([Vector3(WX0, 2.5, WZ1 - 42.0), 6.0, 5.0])
	for w in windows:
		var o: Vector3 = w[0]
		var hw: float = w[1] * 0.5
		var hh: float = w[2] * 0.5
		# length until the ray reaches the floor
		var length := (o.y - 0.0) / maxf(-dir.y, 0.05)
		length = minf(length, 40.0)
		var b: Dictionary = kit.batch("shaft", o, "noshadow")
		# plane 1: spans window width (z) along the ray
		var e := dir * length
		var zv := Vector3(0, 0, hw)
		var yv := Vector3(0, hh, 0)
		for pl in [[zv, 0.8], [yv, 0.6]]:
			var s: Vector3 = pl[0]
			var c2 := col
			c2.a *= pl[1]
			var p0 := o - s
			var p1 := o + s
			var p2 := o + s + e
			var p3 := o - s + e
			var n := s.cross(e).normalized()
			kit._push(b, p0, n, c2, Vector2(0, 0))
			kit._push(b, p1, n, c2, Vector2(1, 0))
			kit._push(b, p2, n, c2, Vector2(1, 1))
			kit._push(b, p0, n, c2, Vector2(0, 0))
			kit._push(b, p2, n, c2, Vector2(1, 1))
			kit._push(b, p3, n, c2, Vector2(0, 1))


# ------------------------------------------------------------------ office / control building
const OX0 := 22.0
const OX1 := 38.0
const OZ0 := 34.0
const OZ1 := 46.0
const F2 := 3.5
const ROOF := 7.0


static func _office(kit: WKit, L) -> void:
	var t := 0.26
	var m1 := ["concrete", "plaster", "plaster_in", "plaster_in"]
	var m2 := ["plaster", "plaster", "plaster_in", "plaster_in"]
	var sf := ["concrete", "concrete"]
	# ground floor walls
	wall(kit, Vector3(OX0, 0, OZ0), Vector3(OX1, 0, OZ0), F2, t, [[6.0, 7.4, 0.0, 2.3, "door"], [1.0, 4.0, 1.0, 2.3, "win"], [9.0, 12.0, 1.0, 2.3, "win"], [13.5, 15.0, 1.0, 2.3, "win"]], m1, 0.6, sf, Vector3.FORWARD)
	wall(kit, Vector3(OX0, 0, OZ1), Vector3(OX0, 0, OZ0), F2, t, [[8.1, 9.5, 0.0, 2.3, "door"], [2.0, 5.0, 1.0, 2.3, "win"]], m1, 0.6, sf, Vector3.LEFT)
	wall(kit, Vector3(OX1, 0, OZ1), Vector3(OX0, 0, OZ1), F2, t, [[3.6, 5.0, 0.0, 2.3, "door"], [7.0, 10.0, 1.0, 2.3, "win"], [11.5, 14.5, 1.0, 2.3, "win"]], m1, 0.6, sf, Vector3.BACK)
	wall(kit, Vector3(OX1, 0, OZ0), Vector3(OX1, 0, OZ1), F2, t, [[3.0, 6.0, 1.0, 2.3, "win"]], m1, 0.6, sf, Vector3.RIGHT)
	# upper floor walls (+ parapet)
	var hh := ROOF - F2 + 0.6
	wall(kit, Vector3(OX0, F2, OZ0), Vector3(OX1, F2, OZ0), hh, t, [[1.0, 5.0, 0.9, 2.5, "win"], [7.0, 11.0, 0.9, 2.5, "win"], [12.0, 15.0, 0.9, 2.5, "win"]], m2, 9.0, sf, Vector3.FORWARD)
	wall(kit, Vector3(OX0, F2, OZ1), Vector3(OX0, F2, OZ0), hh, t, [[6.2, 7.5, 0.0, 2.3, "door"], [1.5, 4.5, 0.9, 2.5, "win"], [9.0, 11.0, 0.9, 2.5, "win"]], m2, 9.0, sf, Vector3.LEFT)
	wall(kit, Vector3(OX1, F2, OZ1), Vector3(OX0, F2, OZ1), hh, t, [[1.0, 4.0, 0.9, 2.5, "win"], [6.0, 9.0, 0.9, 2.5, "win"], [11.0, 14.0, 0.9, 2.5, "win"]], m2, 9.0, sf, Vector3.BACK)
	wall(kit, Vector3(OX1, F2, OZ0), Vector3(OX1, F2, OZ1), hh, t, [[1.0, 4.0, 0.9, 2.5, "win"], [7.0, 9.5, 0.9, 2.5, "win"]], m2, 9.0, sf, Vector3.RIGHT)
	# floor band / cornice lines
	for y in [F2 - 0.05, ROOF + 0.6]:
		kit.box_geo("concrete", Vector3(OX1 - OX0 + 0.3, 0.2, 0.1), Transform3D(Basis.IDENTITY, Vector3((OX0 + OX1) * 0.5, y, OZ0 - 0.16)), Color(0.7, 0.68, 0.64))
		kit.box_geo("concrete", Vector3(OX1 - OX0 + 0.3, 0.2, 0.1), Transform3D(Basis.IDENTITY, Vector3((OX0 + OX1) * 0.5, y, OZ1 + 0.16)), Color(0.7, 0.68, 0.64))
	# slabs: first floor with stair hole (x 36.2..37.75, z 39.8..45.75), roof
	var sx0 := OX0 + 0.13
	var sx1 := OX1 - 0.13
	var sz0 := OZ0 + 0.13
	var sz1 := OZ1 - 0.13
	var hx0 := 36.2
	var hz0 := 39.8
	var slab := func(x0: float, x1: float, z0: float, z1: float, y: float) -> void:
		kit.box_geo("floor_in", Vector3(x1 - x0, 0.25, z1 - z0), Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, y - 0.125, (z0 + z1) * 0.5)), Color(0.95, 0.93, 0.9))
		kit.solid(Vector3(x1 - x0, 0.25, z1 - z0), Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, y - 0.125, (z0 + z1) * 0.5)), "concrete")
	slab.call(sx0, hx0, sz0, sz1, F2)
	slab.call(hx0, sx1, sz0, hz0, F2)
	slab.call(sx0, sx1, sz0, sz1, ROOF)
	kit.box_geo("concrete_dark", Vector3(OX1 - OX0 + 0.1, 0.06, OZ1 - OZ0 + 0.1), Transform3D(Basis.IDENTITY, Vector3((OX0 + OX1) * 0.5, ROOF + 0.03, (OZ0 + OZ1) * 0.5)), Color(0.8, 0.8, 0.8))
	# interior partitions
	wall(kit, Vector3(30.0, 0, sz0), Vector3(30.0, 0, sz1), F2 - 0.25, 0.12, [[4.8, 6.0, 0.0, 2.2, "door"]], ["plaster_in", "plaster_in"], 9.0, sf)
	wall(kit, Vector3(sx0, F2, 41.0), Vector3(33.0, F2, 41.0), ROOF - F2 - 0.25, 0.12, [[5.0, 6.2, 0.0, 2.2, "door"]], ["plaster_in", "plaster_in"], 9.0, sf)
	# internal stair (east side, rising north) + rail around the hole
	Layout.stair(kit, L, Vector3(36.95, 0.0, 45.45), Vector3(0, 0, -1), F2, 1.15, [1.0], "concrete")
	kit.solid(Vector3(0.06, 1.0, sz1 - hz0), Transform3D(Basis.IDENTITY, Vector3(hx0 - 0.03, F2 + 0.5, (hz0 + sz1) * 0.5)), "metal")
	kit.pipe("steel", Vector3(hx0 - 0.03, F2 + 1.0, hz0), Vector3(hx0 - 0.03, F2 + 1.0, sz1), 0.025, Color(0.3, 0.3, 0.3), 6)
	for z: float in [hz0, (hz0 + sz1) * 0.5, sz1]:
		kit.pipe("steel", Vector3(hx0 - 0.03, F2, z), Vector3(hx0 - 0.03, F2 + 1.0, z), 0.02, Color(0.3, 0.3, 0.3), 5)
	# external steel stair on the west façade to the upper door
	Layout.stair(kit, L, Vector3(21.2, 0.0, 45.7), Vector3(0, 0, -1), F2, 1.15, [1.0])
	var lc := Vector3(21.15, F2, 39.05)
	kit.box_geo("plate", Vector3(1.45, 0.08, 2.3), Transform3D(Basis.IDENTITY, lc + Vector3(0, -0.04, 0)), Color(0.8, 0.8, 0.8))
	kit.solid(Vector3(1.45, 0.14, 2.3), Transform3D(Basis.IDENTITY, lc + Vector3(0, -0.07, 0)), "metal")
	kit.solid(Vector3(0.06, 1.05, 2.3), Transform3D(Basis.IDENTITY, lc + Vector3(-0.72, 0.52, 0)), "metal")
	kit.solid(Vector3(1.45, 1.05, 0.06), Transform3D(Basis.IDENTITY, lc + Vector3(0, 0.52, -1.15)), "metal")
	kit.pipe("steel", lc + Vector3(-0.72, 1.05, -1.15), lc + Vector3(-0.72, 1.05, 1.15), 0.025, Color(0.75, 0.6, 0.12), 6)
	kit.pipe("steel", lc + Vector3(-0.72, 1.05, -1.15), lc + Vector3(0.72, 1.05, -1.15), 0.025, Color(0.75, 0.6, 0.12), 6)
	for p in [lc + Vector3(-0.65, 0, -1.1), lc + Vector3(-0.65, 0, 1.1)]:
		kit.box_geo("steel", Vector3(0.1, F2, 0.1), Transform3D(Basis.IDENTITY, Vector3(p.x, F2 * 0.5, p.z)), Color(0.33, 0.35, 0.36))
		kit.pipe("steel", p + Vector3(-0.07, 0, 0), p + Vector3(-0.07, 1.05, 0), 0.022, Color(0.75, 0.6, 0.12), 5)
	# entrance canopy on the north door
	kit.box_geo("steel", Vector3(2.4, 0.12, 1.4), Transform3D(Basis.IDENTITY, Vector3(28.7, 2.7, OZ0 - 0.7)), Color(0.35, 0.36, 0.37))
	# furniture
	_office_furniture(kit, L)
	# rooftop: sign, AC units, vent
	var sign_c := Vector3(30.0, ROOF + 1.9, OZ0 + 0.35)
	for sx: float in [-5.0, 5.0]:
		kit.box_geo("steel", Vector3(0.12, 1.9, 0.12), Transform3D(Basis.IDENTITY, Vector3(sign_c.x + sx, ROOF + 0.95, sign_c.z + 0.3)), Color(0.25, 0.25, 0.25))
	kit.box_geo("steel", Vector3(11.0, 1.3, 0.25), Transform3D(Basis.IDENTITY, sign_c), Color(0.1, 0.1, 0.11))
	var sign := Label3D.new()
	sign.text = "IRONLINE LOGISTICS"
	sign.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	sign.font_size = 200
	sign.pixel_size = 0.0055
	sign.modulate = Color(1.0, 0.55, 0.25)
	sign.shaded = false
	sign.double_sided = false
	sign.position = sign_c + Vector3(0, 0, -0.14)
	sign.rotation_degrees = Vector3(0, 180, 0)
	L.geo.add_child(sign)
	L.add_omni(sign_c + Vector3(0, 0.0, -1.2), Color(1.0, 0.5, 0.25), 1.2, 6.0, 2)
	for ac: Vector3 in [Vector3(25.0, ROOF, 42.0), Vector3(27.5, ROOF, 42.0), Vector3(34.0, ROOF, 37.0)]:
		kit.box_geo("steel", Vector3(1.8, 1.1, 1.2), Transform3D(Basis.IDENTITY, ac + Vector3(0, 0.6, 0)), Color(0.72, 0.72, 0.7), 0.03)
		kit.cyl_geo("black", 0.4, 0.04, Transform3D(Basis.IDENTITY, ac + Vector3(0, 1.17, 0)), Color.WHITE, 12)
	kit.pipe("steel", Vector3(37.0, ROOF, 44.5), Vector3(37.0, ROOF + 2.2, 44.5), 0.12, Color(0.55, 0.55, 0.52), 8)
	# interior lights (warm) visible through the windows
	L.add_omni(Vector3(26.0, 2.8, 40.0), Color(1.0, 0.78, 0.55), 1.3, 9.0, 1)
	L.add_omni(Vector3(29.0, F2 + 2.7, 37.5), Color(1.0, 0.82, 0.6), 1.3, 10.0, 1)
	L.add_omni(Vector3(34.0, 2.8, 42.0), Color(1.0, 0.78, 0.55), 1.0, 8.0, 2)
	for lp: Vector3 in [Vector3(26.0, F2 - 0.27, 38.0), Vector3(26.0, F2 - 0.27, 43.0), Vector3(34.0, F2 - 0.27, 38.0), Vector3(26.0, ROOF - 0.27, 37.5), Vector3(31.5, ROOF - 0.27, 37.5), Vector3(26.0, ROOF - 0.27, 43.5)]:
		kit.box_geo("emit_warm", Vector3(1.2, 0.03, 0.6), Transform3D(Basis.IDENTITY, lp), Color.WHITE, 0.0, "noshadow")
	var probe := ReflectionProbe.new()
	probe.position = Vector3((OX0 + OX1) * 0.5, ROOF * 0.5, (OZ0 + OZ1) * 0.5)
	probe.size = Vector3(OX1 - OX0 - 0.3, ROOF - 0.2, OZ1 - OZ0 - 0.3)
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.5, 0.45, 0.4)
	probe.ambient_color_energy = 0.5
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	L.geo.add_child(probe)
	kit.ground_quad("blob", Vector3((OX0 + OX1) * 0.5, 0, (OZ0 + OZ1) * 0.5), Vector2(OX1 - OX0 + 1.4, OZ1 - OZ0 + 1.4), 0.0, Color(0.4, 0.38, 0.36, 0.8), Vector2(0, 0.12))


static func desk(kit: WKit, p: Vector3, yaw: float, with_pc := true) -> void:
	var bs := Basis(Vector3.UP, deg_to_rad(yaw))
	var xf := Transform3D(bs, p)
	kit.box_geo("wood", Vector3(1.5, 0.04, 0.75), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.74, 0)), Color(0.75, 0.7, 0.62), 0.01, "detail")
	for sx: float in [-0.72, 0.72]:
		kit.box_geo("steel", Vector3(0.04, 0.72, 0.7), xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.36, 0)), Color(0.35, 0.36, 0.38), 0.0, "detail")
	kit.box_geo("steel", Vector3(1.4, 0.4, 0.02), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0.33)), Color(0.35, 0.36, 0.38), 0.0, "detail")
	if with_pc:
		kit.box_geo("black", Vector3(0.55, 0.34, 0.03), xf * Transform3D(Basis.IDENTITY, Vector3(0.1, 1.0, 0.18)), Color.WHITE, 0.0, "detail")
		kit.box_geo("emit_cool", Vector3(0.5, 0.29, 0.005), xf * Transform3D(Basis.IDENTITY, Vector3(0.1, 1.0, 0.162)), Color.WHITE, 0.0, "detail")
		kit.box_geo("black", Vector3(0.06, 0.2, 0.06), xf * Transform3D(Basis.IDENTITY, Vector3(0.1, 0.84, 0.2)), Color.WHITE, 0.0, "detail")
	# chair
	kit.box_geo("rubber", Vector3(0.48, 0.08, 0.46), xf * Transform3D(Basis.IDENTITY, Vector3(-0.1, 0.46, -0.55)), Color(0.25, 0.25, 0.27), 0.02, "detail")
	kit.box_geo("rubber", Vector3(0.46, 0.5, 0.06), xf * Transform3D(Basis.IDENTITY, Vector3(-0.1, 0.8, -0.8)), Color(0.25, 0.25, 0.27), 0.02, "detail")
	kit.cyl_geo("steel", 0.03, 0.42, xf * Transform3D(Basis.IDENTITY, Vector3(-0.1, 0.22, -0.55)), Color(0.2, 0.2, 0.2), 6, "detail")
	kit.solid(Vector3(1.5, 0.78, 0.75), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.39, 0)), "wood", true)


static func _office_furniture(kit: WKit, L) -> void:
	# ground floor: reception / dispatch
	desk(kit, Vector3(25.0, 0, 36.2), 180.0)
	desk(kit, Vector3(27.2, 0, 36.2), 180.0)
	desk(kit, Vector3(25.5, 0, 43.8), 0.0)
	for fc: Vector3 in [Vector3(22.55, 0, 40.5), Vector3(22.55, 0, 41.1), Vector3(29.55, 0, 44.9)]:
		kit.block("steel", Vector3(0.6, 1.32, 0.55), fc + Vector3(0, 0.66, 0), Vector3(0, 90, 0), "metal", Color(0.5, 0.52, 0.5), 0.01)
	desk(kit, Vector3(33.0, 0, 36.0), 180.0)
	kit.block("steel", Vector3(2.0, 1.9, 0.45), Vector3(33.5, 0.95, 45.5), Vector3.ZERO, "metal", Color(0.4, 0.42, 0.45), 0.01, true)
	# upper floor: control room overlooking the yard
	for i in 4:
		desk(kit, Vector3(23.6 + i * 2.6, F2, 35.2), 180.0)
	desk(kit, Vector3(33.8, F2, 36.8), 90.0)
	desk(kit, Vector3(24.5, F2, 43.5), 0.0)
	kit.block("wood", Vector3(2.6, 0.76, 1.1), Vector3(27.5, F2 + 0.38, 44.0), Vector3.ZERO, "wood", Color(0.6, 0.5, 0.42), 0.02, true)
	for fc: Vector3 in [Vector3(32.4, F2, 45.5), Vector3(33.0, F2, 45.5)]:
		kit.block("steel", Vector3(0.55, 1.32, 0.6), fc + Vector3(0, 0.66, 0), Vector3.ZERO, "metal", Color(0.5, 0.52, 0.5), 0.01)
	# notice board / map on the wall
	kit.box_geo("cardboard", Vector3(1.8, 1.1, 0.03), Transform3D(Basis.IDENTITY, Vector3(34.5, F2 + 1.6, 40.95 + 0.0)), Color(0.9, 0.9, 0.85), 0.0, "detail")
	for fx: Vector3 in [Vector3(22.5, 0.0, 44.0), Vector3(35.6, F2, 38.2)]:
		kit.prop("fire_extinguisher_01", fx, 90.0, "metal", "", false)


# ------------------------------------------------------------------ gate booth
static func _booth(kit: WKit, L) -> void:
	var c := Vector3(-8.0, 0, 58.5)
	var m := ["concrete", "plaster", "plaster_in", "plaster_in"]
	var sf := ["concrete", "concrete"]
	var h := 2.8
	wall(kit, c + Vector3(-1.6, 0, -1.6), c + Vector3(1.6, 0, -1.6), h, 0.18, [[0.4, 2.8, 1.0, 2.2, "win"]], m, 0.9, sf, Vector3.FORWARD)
	wall(kit, c + Vector3(1.6, 0, -1.6), c + Vector3(1.6, 0, 1.6), h, 0.18, [[1.6, 2.6, 0.0, 2.1, "door"], [0.3, 1.3, 1.0, 2.2, "win"]], m, 0.9, sf, Vector3.RIGHT)
	wall(kit, c + Vector3(1.6, 0, 1.6), c + Vector3(-1.6, 0, 1.6), h, 0.18, [[0.4, 2.8, 1.0, 2.2, "win"]], m, 0.9, sf, Vector3.BACK)
	wall(kit, c + Vector3(-1.6, 0, 1.6), c + Vector3(-1.6, 0, -1.6), h, 0.18, [], m, 0.9, sf, Vector3.LEFT)
	kit.block("steel", Vector3(4.2, 0.18, 4.2), c + Vector3(0, h + 0.09, 0), Vector3.ZERO, "metal", Color(0.3, 0.32, 0.34))
	desk(kit, c + Vector3(-0.6, 0, -0.9), 180.0)
	kit.box_geo("emit_warm", Vector3(0.9, 0.03, 0.3), Transform3D(Basis.IDENTITY, c + Vector3(0, h - 0.03, 0)), Color.WHITE, 0.0, "noshadow")
	L.add_omni(c + Vector3(0, 2.3, 0), Color(1.0, 0.8, 0.55), 0.9, 6.0, 1)
	# barrier arm across the gate lane (raised slightly)
	var post := Vector3(-5.6, 0, 60.5)
	kit.block("steel", Vector3(0.35, 1.0, 0.35), post + Vector3(0, 0.5, 0), Vector3.ZERO, "metal", Color(0.8, 0.8, 0.78), 0.02)
	for k in 8:
		var col := Color(0.78, 0.1, 0.08) if k % 2 == 0 else Color(0.9, 0.9, 0.88)
		kit.box_geo("steel", Vector3(0.75, 0.1, 0.08), Transform3D(Basis(Vector3.BACK, deg_to_rad(8.0)), post + Vector3(0.6 + k * 0.74, 1.0 + (0.6 + k * 0.74) * 0.14, 0)), col, 0.0, "detail")
	# speed bumps
	for bz: float in [52.0]:
		for bx in range(-8, 6, 2):
			var col := Color(0.8, 0.62, 0.1) if (bx / 2) % 2 == 0 else Color(0.12, 0.12, 0.12)
			kit.box_geo("rubber", Vector3(2.0, 0.06, 0.35), Transform3D(Basis.IDENTITY, Vector3(bx + 1.0, 0.03, bz)), col, 0.02, "detail")


# ------------------------------------------------------------------ north storage: pump house + tanks
static func _pump_house(kit: WKit, L) -> void:
	var c := Vector3(50.0, 0, -56.0)
	kit.block("brick", Vector3(6.0, 3.4, 4.0), c + Vector3(0, 1.7, 0), Vector3.ZERO, "concrete", Color(0.85, 0.8, 0.78), 0.0, true)
	kit.box_geo("cladding_dark", Vector3(6.4, 0.2, 4.4), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(4.0)), c + Vector3(0, 3.5, 0)), Color.WHITE)
	kit.box_geo("steel", Vector3(1.0, 2.1, 0.05), Transform3D(Basis.IDENTITY, c + Vector3(-1.5, 1.05, 2.02)), Color(0.3, 0.38, 0.42))
	var lab := Label3D.new()
	lab.text = "DANGER\nHIGH VOLTAGE"
	lab.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	lab.font_size = 64
	lab.pixel_size = 0.004
	lab.modulate = Color(0.08, 0.08, 0.08)
	lab.shaded = true
	lab.position = c + Vector3(0.6, 1.7, 2.04)
	L.geo.add_child(lab)
	kit.box_geo("steel", Vector3(0.8, 0.55, 0.02), Transform3D(Basis.IDENTITY, c + Vector3(0.6, 1.7, 2.02)), Color(0.85, 0.68, 0.1))
	# horizontal fuel tanks on saddles
	for tz: float in [-58.5, -53.5]:
		var tp := Vector3(34.0, 1.6, tz)
		kit.cyl_geo("steel", 1.3, 7.0, Transform3D(Basis(Vector3.BACK, PI * 0.5), tp), Color(0.72, 0.72, 0.68), 16)
		for sx: float in [-2.5, 2.5]:
			kit.box_geo("concrete", Vector3(0.5, 0.9, 2.2), Transform3D(Basis.IDENTITY, Vector3(tp.x + sx, 0.45, tz)), Color(0.7, 0.68, 0.64))
		kit.solid_cyl(1.3, 7.0, Transform3D(Basis(Vector3.BACK, PI * 0.5), tp), "metal", true)
		kit.ground_quad("blob", Vector3(tp.x, 0, tz), Vector2(8.0, 3.2), 0.0, Color(0.35, 0.33, 0.3, 0.8), Vector2(1, 0.5))
	kit.pipe("steel", Vector3(37.5, 1.6, -58.5), Vector3(47.0, 1.6, -58.5), 0.1, Color(0.6, 0.55, 0.2), 8)
	kit.pipe("steel", Vector3(47.0, 1.6, -58.5), Vector3(47.0, 0.0, -58.5), 0.1, Color(0.6, 0.55, 0.2), 8)
