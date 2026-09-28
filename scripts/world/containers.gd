extends RefCounted
## ISO shipping containers built into the kit's merged batches: geometric trapezoid corrugation, corner posts,
## rails, corner castings, door end with locking bars / cams / handles / hinges. Length along local Z, door end
## at +Z, origin = bottom centre.

const WKit := preload("res://scripts/world/wkit.gd")
const W := 2.44
const H := 2.59
const L20 := 6.06
const L40 := 12.19
const MAT := "container"

const PALETTE := {
	"maersk": Color(0.36, 0.55, 0.66),
	"rust": Color(0.52, 0.2, 0.13),
	"cma": Color(0.12, 0.17, 0.3),
	"green": Color(0.2, 0.33, 0.24),
	"orange": Color(0.72, 0.36, 0.12),
	"grey": Color(0.48, 0.49, 0.48),
	"white": Color(0.7, 0.69, 0.64),
	"yellow": Color(0.7, 0.55, 0.16),
	"brown": Color(0.33, 0.22, 0.15),
	"teal": Color(0.17, 0.37, 0.38),
}
const STEEL := Color(0.36, 0.35, 0.33)
const DARK := Color(0.16, 0.15, 0.14)


static func color(kit: WKit, name: String) -> Color:
	var c: Color = PALETTE.get(name, PALETTE.grey)
	var v: float = kit.rng.randf_range(0.88, 1.08)
	return Color(c.r * v, c.g * v, c.b * v)


## Corrugated wall in a frame whose basis columns are (u = along, v = up, w = outward); origin at the
## start of the wall (u = 0), bottom (v = 0), outer face plane (w = 0).
static func corr_wall(kit: WKit, frame: Transform3D, length: float, height: float, col: Color, pitch := 0.28, depth := 0.045, group := "") -> void:
	var b: Dictionary = kit.batch(MAT, frame.origin, group)
	var n := int(round(length / pitch))
	var p := length / n
	var us: Array[float] = []
	var ws: Array[float] = []
	for i in n:
		var u0 := i * p
		if i == 0:
			us.append(0.0); ws.append(0.0)
		us.append(u0 + p * 0.3); ws.append(0.0)
		us.append(u0 + p * 0.4); ws.append(-depth)
		us.append(u0 + p * 0.7); ws.append(-depth)
		us.append(u0 + p * 0.8); ws.append(0.0)
	us.append(length); ws.append(0.0)
	for i in us.size() - 1:
		if absf(us[i + 1] - us[i]) < 0.0001:
			continue
		var a: Vector3 = frame * Vector3(us[i], 0, ws[i])
		var bb: Vector3 = frame * Vector3(us[i + 1], 0, ws[i + 1])
		var c: Vector3 = frame * Vector3(us[i + 1], height, ws[i + 1])
		var d: Vector3 = frame * Vector3(us[i], height, ws[i])
		kit.quad4(b, a, bb, c, d, col)


## Full-detail container. flags: skip_l / skip_r (hidden long sides), open (doors swung open, hollow).
static func build(kit: WKit, xf: Transform3D, length: float, col: Color, flags := {}) -> void:
	var hw := W * 0.5
	var hl := length * 0.5
	var frame_col := col * 0.82
	frame_col.a = 1.0
	var g: String = flags.get("group", "")
	var open: bool = flags.get("open", false)
	var y0 := 0.16
	var wh := H - 0.28
	# long sides (corrugated), outer face at hw - 0.02
	var inset := hw - 0.025
	if not flags.get("skip_r", false):
		# right: w = +X, u = -Z, start at z = +hl - 0.16
		var fr := Transform3D(Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0)), Vector3(inset, y0, hl - 0.16))
		corr_wall(kit, xf * fr, length - 0.32, wh, col, 0.28, 0.045, g)
	if not flags.get("skip_l", false):
		var fl := Transform3D(Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0)), Vector3(-inset, y0, -hl + 0.16))
		corr_wall(kit, xf * fl, length - 0.32, wh, col, 0.28, 0.045, g)
	# front (blind) end: w = -Z, u = -X
	var ff := Transform3D(Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1)), Vector3(hw - 0.16, y0, -hl + 0.02))
	corr_wall(kit, xf * ff, W - 0.32, wh, col, 0.23, 0.035, g)
	# roof panel (slightly below the top rails) + inner closure box (casts clean shadows)
	kit.box_geo(MAT, Vector3(W - 0.14, 0.04, length - 0.2), xf * Transform3D(Basis.IDENTITY, Vector3(0, H - 0.05, 0)), col * 0.95, 0.0, g)
	if not open:
		kit.box_geo(MAT, Vector3(W - 0.2, H - 0.3, length - 0.3), xf * Transform3D(Basis.IDENTITY, Vector3(0, H * 0.5, 0)), DARK, 0.0, g)
	else:
		_hollow_interior(kit, xf, length, col, g)
	# corner posts
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.box_geo(MAT, Vector3(0.16, H - 0.2, 0.16), xf * Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.08), H * 0.5, sz * (hl - 0.08))), frame_col, 0.0, g)
			for y: float in [0.06, H - 0.06]:
				kit.box_geo(MAT, Vector3(0.18, 0.12, 0.18), xf * Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.09), y, sz * (hl - 0.09))), DARK, 0.0, g)
	# side rails top/bottom
	for sx: float in [-1.0, 1.0]:
		kit.box_geo(MAT, Vector3(0.1, 0.16, length - 0.36), xf * Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.05), 0.08, 0)), frame_col, 0.0, g)
		kit.box_geo(MAT, Vector3(0.09, 0.1, length - 0.36), xf * Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.045), H - 0.05, 0)), frame_col, 0.0, g)
	# end rails
	for sz: float in [-1.0, 1.0]:
		kit.box_geo(MAT, Vector3(W - 0.36, 0.16, 0.1), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.08, sz * (hl - 0.05))), frame_col, 0.0, g)
		var th := 0.22 if sz > 0 else 0.1
		kit.box_geo(MAT, Vector3(W - 0.36, th, 0.1), xf * Transform3D(Basis.IDENTITY, Vector3(0, H - th * 0.5, sz * (hl - 0.05))), frame_col, 0.0, g)
	_doors(kit, xf, length, col, open, g)


static func _hollow_interior(kit: WKit, xf: Transform3D, length: float, col: Color, g: String) -> void:
	var hw := W * 0.5 - 0.08
	var hl := length * 0.5 - 0.1
	var dark := col * 0.45
	dark.a = 1.0
	# inward-facing walls: draw thin boxes just inside each wall
	kit.box_geo(MAT, Vector3(0.03, H - 0.3, length - 0.25), xf * Transform3D(Basis.IDENTITY, Vector3(hw, H * 0.5, 0)), dark, 0.0, g)
	kit.box_geo(MAT, Vector3(0.03, H - 0.3, length - 0.25), xf * Transform3D(Basis.IDENTITY, Vector3(-hw, H * 0.5, 0)), dark, 0.0, g)
	kit.box_geo(MAT, Vector3(W - 0.2, H - 0.3, 0.03), xf * Transform3D(Basis.IDENTITY, Vector3(0, H * 0.5, -hl)), dark, 0.0, g)
	kit.box_geo(MAT, Vector3(W - 0.2, 0.03, length - 0.25), xf * Transform3D(Basis.IDENTITY, Vector3(0, H - 0.16, 0)), dark * 0.7, 0.0, g)
	kit.box_geo("wood_floor", Vector3(W - 0.2, 0.04, length - 0.25), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.14, 0)), Color(0.6, 0.55, 0.5), 0.0, g)


static func _doors(kit: WKit, xf: Transform3D, length: float, col: Color, open: bool, g: String) -> void:
	var hl := length * 0.5
	var hw := W * 0.5
	var leaf_w := (W - 0.3) * 0.5
	var leaf_h := H - 0.4
	for side: float in [-1.0, 1.0]:
		# hinge line at the outer edge of each leaf
		var hinge := Vector3(side * (hw - 0.15), 0.0, hl - 0.02)
		var leaf_basis := Basis.IDENTITY
		if open:
			leaf_basis = Basis(Vector3.UP, deg_to_rad(side * (100.0 + side * 0.0)))
			if side < 0.0:
				leaf_basis = Basis(Vector3.UP, deg_to_rad(-100.0))
			else:
				leaf_basis = Basis(Vector3.UP, deg_to_rad(100.0))
		var lx := Transform3D(leaf_basis, hinge)
		# leaf local: extends from hinge toward the centre (-side * x)
		var cx := -side * leaf_w * 0.5
		kit.box_geo(MAT, Vector3(leaf_w, leaf_h, 0.035), xf * lx * Transform3D(Basis.IDENTITY, Vector3(cx, 0.2 + leaf_h * 0.5, 0)), col, 0.0, g)
		# pressed horizontal ribs on the door leaf
		for k in 3:
			var yy := 0.6 + k * 0.62
			kit.box_geo(MAT, Vector3(leaf_w - 0.12, 0.09, 0.025), xf * lx * Transform3D(Basis.IDENTITY, Vector3(cx, yy, 0.025)), col * 0.97, 0.0, g)
		# two locking bars per leaf
		for bx: float in [0.22, 0.72]:
			var x := -side * leaf_w * bx
			kit.pipe(MAT, xf * lx * Vector3(x, 0.12, 0.07), xf * lx * Vector3(x, H - 0.12, 0.07), 0.018, STEEL, 4, g)
			for yk: float in [0.14, H - 0.14]:
				kit.box_geo(MAT, Vector3(0.09, 0.07, 0.07), xf * lx * Transform3D(Basis.IDENTITY, Vector3(x, yk, 0.06)), DARK, 0.0, g)
			# handle
			kit.box_geo(MAT, Vector3(0.04, 0.34, 0.04), xf * lx * Transform3D(Basis(Vector3.BACK, deg_to_rad(side * 12.0)), Vector3(x - side * 0.08, 1.15, 0.1)), STEEL * 0.8, 0.0, g)
			kit.box_geo(MAT, Vector3(0.12, 0.05, 0.05), xf * lx * Transform3D(Basis.IDENTITY, Vector3(x, 1.0, 0.08)), DARK, 0.0, g)
		# hinges
		for hy: float in [0.45, 1.1, 1.75, 2.35]:
			kit.box_geo(MAT, Vector3(0.1, 0.13, 0.08), xf * Transform3D(Basis.IDENTITY, Vector3(side * (hw - 0.12), hy, hl + 0.01)), col * 0.75, 0.0, g)


## Low-detail container (backdrop / ship deck / boundary tops): body box + darker frame bands.
static func build_lod(kit: WKit, xf: Transform3D, length: float, col: Color, group := "far", bands := true) -> void:
	var mat := "container_far"
	kit.box_geo(mat, Vector3(W, H - 0.02, length), xf * Transform3D(Basis.IDENTITY, Vector3(0, H * 0.5, 0)), col, 0.0, group, true)
	if not bands:
		return
	var fc := col * 0.7
	fc.a = 1.0
	for sz: float in [-1.0, 1.0]:
		kit.box_geo(mat, Vector3(W + 0.02, H, 0.14), xf * Transform3D(Basis.IDENTITY, Vector3(0, H * 0.5, sz * (length * 0.5 - 0.07))), fc, 0.0, group, true)


## Adds a container with collision. xf origin = bottom centre.
static func place(kit: WKit, xf: Transform3D, length: float, col: Color, flags := {}) -> void:
	build(kit, xf, length, col, flags)
	if flags.get("open", false):
		var hw := W * 0.5
		var hl := length * 0.5
		kit.solid(Vector3(0.12, H, length), xf * Transform3D(Basis.IDENTITY, Vector3(hw - 0.06, H * 0.5, 0)), "metal", true)
		kit.solid(Vector3(0.12, H, length), xf * Transform3D(Basis.IDENTITY, Vector3(-hw + 0.06, H * 0.5, 0)), "metal", true)
		kit.solid(Vector3(W, H, 0.12), xf * Transform3D(Basis.IDENTITY, Vector3(0, H * 0.5, -hl + 0.06)), "metal")
		kit.solid(Vector3(W, 0.14, length), xf * Transform3D(Basis.IDENTITY, Vector3(0, H - 0.07, 0)), "metal")
		kit.solid(Vector3(W - 0.2, 0.16, length - 0.2), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0)), "wood")
	else:
		kit.solid(Vector3(W, H, length), xf * Transform3D(Basis.IDENTITY, Vector3(0, H * 0.5, 0)), "metal", true)
