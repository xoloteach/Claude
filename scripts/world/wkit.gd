extends RefCounted
## World building kit for the level: merges procedural geometry per (material, cell) into a few big ArrayMeshes
## (few draw calls), creates collision on Game.L_WORLD grouped by surface, instances glb props through
## MultiMesh, and builds decal quads. Everything is flushed to the scene in finish().

const CELL := 40.0
const SURF_SHADER := preload("res://assets/shaders/world_surface.gdshader")
const TEX := "res://assets/textures/"
const UV_MATS := ["paint", "blob", "puddle", "dirt_decal", "shaft"]

var root: Node3D
var col_root: Node3D
var batches := {}
var mats := {}
var bodies := {}
var props := {}          # prop name -> {parts: [[mesh, xf]], aabb}
var prop_batches := {}   # key -> {mesh, xfs, cell, vis}
var macro_tex: Texture2D
var water_normal: Texture2D
var _bevel_cache := {}
var _cyl_cache := {}
var detail_nodes: Array[GeometryInstance3D] = []
var cover_boxes: Array = []   # [AABB] of solid pieces that provide cover
var rng := RandomNumberGenerator.new()


func _init(visual_root: Node3D, collision_root: Node3D) -> void:
	root = visual_root
	col_root = collision_root
	rng.seed = 7331
	_make_noise()


func _make_noise() -> void:
	var fn := FastNoiseLite.new()
	fn.seed = 91
	fn.noise_type = FastNoiseLite.TYPE_PERLIN
	fn.frequency = 0.02
	fn.fractal_octaves = 5
	var img := fn.get_seamless_image(256, 256, false, false, 0.15, true)
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	macro_tex = ImageTexture.create_from_image(img)
	var wn := FastNoiseLite.new()
	wn.seed = 5
	wn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wn.frequency = 0.025
	wn.fractal_octaves = 4
	var wimg := wn.get_seamless_image(256, 256, false, false, 0.2, true)
	wimg.convert(Image.FORMAT_RGBA8)
	wimg.bump_map_to_normal_map(6.0)
	wimg.generate_mipmaps()
	water_normal = ImageTexture.create_from_image(wimg)


# ------------------------------------------------------------------ materials
func tex(set_name: String, file: String) -> Texture2D:
	var p := TEX + set_name + "/" + file
	return load(p) if ResourceLoader.exists(p) else null


## Registers a world_surface.gdshader material under `name` using texture set `set_name`.
func def_surface(name: String, set_name: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURF_SHADER
	m.set_shader_parameter("tex_albedo", tex(set_name, "albedo.jpg"))
	m.set_shader_parameter("tex_normal", tex(set_name, "normal.jpg"))
	var r := tex(set_name, "roughness.jpg")
	if r: m.set_shader_parameter("tex_rough", r)
	var ao := tex(set_name, "ao.jpg")
	if ao: m.set_shader_parameter("tex_ao", ao)
	m.set_shader_parameter("tex_macro", macro_tex)
	for k in params:
		m.set_shader_parameter(k, params[k])
	mats[name] = m
	return m


func def_mat(name: String, m: Material) -> Material:
	mats[name] = m
	return m


func shader_mat(name: String, shader_path: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	m.set_shader_parameter("tex_macro", macro_tex)
	for k in params:
		m.set_shader_parameter(k, params[k])
	mats[name] = m
	return m


# ------------------------------------------------------------------ batches
func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


## Returns the batch dictionary for a material at a world position. `group` separates e.g. detail geometry
## (visibility ranged) from big structures.
func batch(mat_name: String, at: Vector3, group := "") -> Dictionary:
	var c := _cell(at)
	var key := "%s|%d|%d|%s" % [mat_name, c.x, c.y, group]
	if not batches.has(key):
		batches[key] = {"mat": mat_name, "cell": c, "group": group, "v": PackedVector3Array(), "n": PackedVector3Array(),
			"c": PackedColorArray(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "center": Vector3.ZERO, "cnt": 0}
	return batches[key]


func _push(b: Dictionary, v: Vector3, n: Vector3, c: Color, uv := Vector2.ZERO, uv2 := Vector2.ZERO) -> void:
	b.v.append(v)
	b.n.append(n)
	b.c.append(c)
	b.uv.append(uv)
	b.uv2.append(uv2)


func tri(b: Dictionary, a: Vector3, bb: Vector3, c: Vector3, col: Color) -> void:
	# Godot front faces are clockwise when seen from the front
	var n := (c - a).cross(bb - a).normalized()
	_push(b, a, n, col)
	_push(b, bb, n, col)
	_push(b, c, n, col)


## Quad a-b-c-d (counter-clockwise as seen from the front); normal computed.
func quad4(b: Dictionary, a: Vector3, bb: Vector3, c: Vector3, d: Vector3, col: Color, uv2 := Vector2.ZERO) -> void:
	var n := (bb - a).cross(d - a).normalized()
	_push(b, a, n, col, Vector2(0, 1), uv2)
	_push(b, c, n, col, Vector2(1, 0), uv2)
	_push(b, bb, n, col, Vector2(1, 1), uv2)
	_push(b, a, n, col, Vector2(0, 1), uv2)
	_push(b, d, n, col, Vector2(0, 0), uv2)
	_push(b, c, n, col, Vector2(1, 0), uv2)


const _BOX_FACES := [
	# normal, u axis, v axis
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]


## Axis-aligned (in xf space) box of full extents `size` centred at xf.origin. skip_bottom drops the -Y face.
func box_geo(mat_name: String, size: Vector3, xf: Transform3D, col := Color.WHITE, bevel := 0.0, group := "", skip_bottom := false) -> void:
	var b := batch(mat_name, xf.origin, group)
	var h := size * 0.5
	if bevel > 0.0:
		var arr := _bevel_arrays(size, bevel)
		var vs: PackedVector3Array = arr[0]
		var ns: PackedVector3Array = arr[1]
		for i in vs.size():
			_push(b, xf * vs[i], (xf.basis * ns[i]).normalized(), col)
		return
	for f in _BOX_FACES:
		var n: Vector3 = f[0]
		if skip_bottom and n.y < -0.5:
			continue
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var ue := u * absf(u.dot(h))
		var ve := v * absf(v.dot(h))
		var p0 := xf * (c - ue - ve)
		var p1 := xf * (c + ue - ve)
		var p2 := xf * (c + ue + ve)
		var p3 := xf * (c - ue + ve)
		var wn := (xf.basis * n).normalized()
		_push(b, p0, wn, col)
		_push(b, p2, wn, col)
		_push(b, p1, wn, col)
		_push(b, p0, wn, col)
		_push(b, p3, wn, col)
		_push(b, p2, wn, col)


func _bevel_arrays(size: Vector3, bevel: float) -> Array:
	var key := "%s|%s" % [size, bevel]
	if _bevel_cache.has(key):
		return _bevel_cache[key]
	var m: ArrayMesh = MeshKit.bevel_box(size, bevel)
	var a := m.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx = a[Mesh.ARRAY_INDEX]
	if idx != null and (idx as PackedInt32Array).size() > 0:
		var v2 := PackedVector3Array()
		var n2 := PackedVector3Array()
		for i in idx:
			v2.append(vs[i])
			n2.append(ns[i])
		vs = v2
		ns = n2
	var r := [vs, ns]
	_bevel_cache[key] = r
	return r


## Cylinder along local Y, base at xf.origin - h/2 (centred).
func cyl_geo(mat_name: String, radius: float, height: float, xf: Transform3D, col := Color.WHITE, segs := 12, group := "", caps := true, top_radius := -1.0) -> void:
	var b := batch(mat_name, xf.origin, group)
	var tr := radius if top_radius < 0.0 else top_radius
	var hh := height * 0.5
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := xf * (d0 * radius + Vector3(0, -hh, 0))
		var p1 := xf * (d1 * radius + Vector3(0, -hh, 0))
		var p2 := xf * (d1 * tr + Vector3(0, hh, 0))
		var p3 := xf * (d0 * tr + Vector3(0, hh, 0))
		var n0 := (xf.basis * d0).normalized()
		var n1 := (xf.basis * d1).normalized()
		_push(b, p0, n0, col)
		_push(b, p1, n1, col)
		_push(b, p2, n1, col)
		_push(b, p0, n0, col)
		_push(b, p2, n1, col)
		_push(b, p3, n0, col)
		if caps:
			var up := (xf.basis * Vector3.UP).normalized()
			var ct := xf * Vector3(0, hh, 0)
			_push(b, ct, up, col)
			_push(b, p3, up, col)
			_push(b, p2, up, col)
			var cb := xf * Vector3(0, -hh, 0)
			_push(b, cb, -up, col)
			_push(b, p1, -up, col)
			_push(b, p0, -up, col)


## Beam between two points (square section).
func beam(mat_name: String, a: Vector3, bpt: Vector3, thick: float, col := Color.WHITE, group := "", thick_y := -1.0) -> void:
	var d := bpt - a
	var l := d.length()
	if l < 0.001:
		return
	var z := d / l
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	var xf := Transform3D(Basis(x, y, z), (a + bpt) * 0.5)
	box_geo(mat_name, Vector3(thick, thick if thick_y < 0.0 else thick_y, l), xf, col, 0.0, group)


## Pipe (round) between two points.
func pipe(mat_name: String, a: Vector3, bpt: Vector3, radius: float, col := Color.WHITE, segs := 8, group := "") -> void:
	var d := bpt - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	cyl_geo(mat_name, radius, l, Transform3D(Basis(x, y, z), (a + bpt) * 0.5), col, segs, group, false)


## Horizontal ground decal quad (UV 0..1), rotated by rot_y degrees.
func ground_quad(mat_name: String, center: Vector3, size: Vector2, rot_y := 0.0, col := Color.WHITE, uv2 := Vector2.ZERO, group := "decal") -> void:
	var b := batch(mat_name, center, group)
	var bs := Basis(Vector3.UP, deg_to_rad(rot_y))
	var hx := bs * Vector3(size.x * 0.5, 0, 0)
	var hz := bs * Vector3(0, 0, size.y * 0.5)
	var p0 := center - hx + hz
	var p1 := center + hx + hz
	var p2 := center + hx - hz
	var p3 := center - hx - hz
	var n := Vector3.UP
	_push(b, p0, n, col, Vector2(0, 1), uv2)
	_push(b, p2, n, col, Vector2(1, 0), uv2)
	_push(b, p1, n, col, Vector2(1, 1), uv2)
	_push(b, p0, n, col, Vector2(0, 1), uv2)
	_push(b, p3, n, col, Vector2(0, 0), uv2)
	_push(b, p2, n, col, Vector2(1, 0), uv2)


## Vertical/arbitrary quad in the XY plane of xf, facing +Z of xf.
func quad_xf(mat_name: String, xf: Transform3D, size: Vector2, col := Color.WHITE, uv2 := Vector2.ZERO, group := "") -> void:
	var b := batch(mat_name, xf.origin, group)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var p0 := xf * Vector3(-hx, -hy, 0)
	var p1 := xf * Vector3(hx, -hy, 0)
	var p2 := xf * Vector3(hx, hy, 0)
	var p3 := xf * Vector3(-hx, hy, 0)
	var n := (xf.basis * Vector3.BACK).normalized()
	_push(b, p0, n, col, Vector2(0, 1), uv2)
	_push(b, p2, n, col, Vector2(1, 0), uv2)
	_push(b, p1, n, col, Vector2(1, 1), uv2)
	_push(b, p0, n, col, Vector2(0, 1), uv2)
	_push(b, p3, n, col, Vector2(0, 0), uv2)
	_push(b, p2, n, col, Vector2(1, 0), uv2)


# ------------------------------------------------------------------ collision
func body(surface: String) -> StaticBody3D:
	if bodies.has(surface):
		return bodies[surface]
	var sb := StaticBody3D.new()
	sb.name = "Col_" + surface
	sb.collision_layer = Game.L_WORLD
	sb.collision_mask = 0
	sb.set_meta("surface", surface)
	col_root.add_child(sb)
	bodies[surface] = sb
	return sb


func solid(size: Vector3, xf: Transform3D, surface := "concrete", cover := false) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body(surface).add_child(cs)
	if cover:
		cover_boxes.append(xf * AABB(-size * 0.5, size))


func solid_cyl(radius: float, height: float, xf: Transform3D, surface := "metal", cover := false) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	cs.shape = s
	cs.transform = xf
	body(surface).add_child(cs)
	if cover:
		cover_boxes.append(xf * AABB(Vector3(-radius, -height * 0.5, -radius), Vector3(radius * 2, height, radius * 2)))


## Visual + collision box. rot = degrees (euler YXZ). Position = centre.
func block(mat_name: String, size: Vector3, pos: Vector3, rot := Vector3.ZERO, surface := "concrete", col := Color.WHITE, bevel := 0.0, cover := false) -> Transform3D:
	var xf := Transform3D(Basis.from_euler(rot * (PI / 180.0)), pos)
	box_geo(mat_name, size, xf, col, bevel)
	if surface != "":
		solid(size, xf, surface, cover)
	return xf


static func xf_at(pos: Vector3, rot_y_deg := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y_deg)), pos)


## Smooth ramp collision between two points on the ground plane (a low, b high), width w. Returns the transform.
func ramp_collision(a: Vector3, bpt: Vector3, width: float, surface := "metal", thick := 0.2) -> void:
	var d := bpt - a
	var l := d.length()
	var z := d / l
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	var c := (a + bpt) * 0.5 - y * thick * 0.5
	solid(Vector3(width, thick, l), Transform3D(Basis(x, y, z), c), surface)


# ------------------------------------------------------------------ props (glb via MultiMesh)
func load_prop(name: String) -> Dictionary:
	if props.has(name):
		return props[name]
	var sc: PackedScene = load("res://assets/models/props/%s.glb" % name)
	var inst := sc.instantiate()
	var parts := []
	var ab := AABB()
	var first := true
	_collect(inst, Transform3D.IDENTITY, parts)
	for p in parts:
		var a: AABB = p[1] * (p[0] as Mesh).get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	inst.free()
	var d := {"parts": parts, "aabb": ab}
	props[name] = d
	return d


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		# bake surface override materials into a copy if present
		if mi.get_surface_override_material_count() > 0 and mi.get_surface_override_material(0):
			mesh = mesh.duplicate()
			for s in mesh.get_surface_count():
				var om := mi.get_surface_override_material(s)
				if om: mesh.surface_set_material(s, om)
		out.append([mesh, t])
	for c in n.get_children():
		_collect(c, t, out)


## Places a glb prop. collide: "" none, "box", "cyl". Returns the prop AABB in world space.
func prop(name: String, pos: Vector3, rot_y := 0.0, surface := "metal", collide := "box", cover := false, extra_basis := Basis.IDENTITY, vis := "detail") -> AABB:
	var d := load_prop(name)
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)) * extra_basis, pos)
	var c := _cell(pos)
	for i in d.parts.size():
		var key := "%s|%d|%d|%d|%s" % [name, i, c.x, c.y, vis]
		if not prop_batches.has(key):
			prop_batches[key] = {"mesh": d.parts[i][0], "xfs": [], "vis": vis}
		prop_batches[key].xfs.append(xf * d.parts[i][1])
	var ab: AABB = d.aabb
	var wab := xf * ab
	if collide == "box":
		solid(ab.size, xf * Transform3D(Basis.IDENTITY, ab.get_center()), surface, cover)
	elif collide == "cyl":
		solid_cyl(maxf(ab.size.x, ab.size.z) * 0.5, ab.size.y, xf * Transform3D(Basis.IDENTITY, ab.get_center()), surface, cover)
	return wab


# ------------------------------------------------------------------ flush
func finish() -> void:
	for key in batches:
		var b: Dictionary = batches[key]
		if (b.v as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.v
		arrays[Mesh.ARRAY_NORMAL] = b.n
		arrays[Mesh.ARRAY_COLOR] = b.c
		if str(b.mat) in UV_MATS:
			arrays[Mesh.ARRAY_TEX_UV] = b.uv
			arrays[Mesh.ARRAY_TEX_UV2] = b.uv2
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "B_" + str(b.mat) + "_" + str(b.cell.x) + "_" + str(b.cell.y) + "_" + str(b.group)
		mi.mesh = am
		mi.material_override = mats.get(b.mat)
		var g: String = b.group
		if g == "decal" or g == "paint":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if g == "detail" or g == "decal":
			detail_nodes.append(mi)
		if g == "noshadow" or g == "bg" or g == "far" or g.ends_with("ns"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	batches.clear()
	for key in prop_batches:
		var pb: Dictionary = prop_batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pb.mesh
		mm.instance_count = pb.xfs.size()
		for i in pb.xfs.size():
			mm.set_instance_transform(i, pb.xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "P_" + key.replace("|", "_")
		mmi.multimesh = mm
		root.add_child(mmi)
		if pb.vis == "detail":
			detail_nodes.append(mmi)
	prop_batches.clear()
