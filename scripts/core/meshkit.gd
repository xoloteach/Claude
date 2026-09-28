class_name MeshKit
extends RefCounted
## Procedural mesh + PBR material helpers.

const TEX_DIR := "res://assets/textures/"

static var _mat_cache := {}
static var _mesh_cache := {}
static var _tex_cache := {}


static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t


## PBR material from assets/textures/<set>/. Uses triplanar mapping (world or object space) so procedural
## geometry needs no UVs. `scale` = texture repeats per meter.
static func pbr(set_name: String, tint := Color.WHITE, scale := 0.5, world_space := true, opts := {}) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [set_name, tint.to_html(), scale, world_space, str(opts)]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	var d := TEX_DIR + set_name + "/"
	var alb := tex(d + "albedo.jpg")
	if opts.get("alpha", false):
		alb = tex(d + "albedo_alpha.png")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = alb
	m.albedo_color = tint
	var nrm := tex(d + "normal.jpg")
	if nrm:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = opts.get("normal_scale", 1.0)
	var rough := tex(d + "roughness.jpg")
	if rough:
		m.roughness_texture = rough
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = opts.get("roughness", 1.0)
	var met := tex(d + "metallic.jpg")
	if met and opts.get("use_metal_map", true):
		m.metallic_texture = met
		m.metallic = 1.0
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	else:
		m.metallic = opts.get("metallic", 0.0)
	m.metallic_specular = opts.get("specular", 0.5)
	var ao := tex(d + "ao.jpg")
	if ao and opts.get("use_ao", true):
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.ao_light_affect = 0.6
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world_space
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if opts.has("emission"):
		m.emission_enabled = true
		m.emission = opts.emission
		m.emission_energy_multiplier = opts.get("emission_energy", 1.0)
	_mat_cache[key] = m
	return m


static func flat(color: Color, roughness := 0.6, metallic := 0.0, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var key := "flat|%s|%s|%s|%s|%s" % [color.to_html(), roughness, metallic, emission.to_html(), emission_energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
	return m


static func unshaded(color: Color, additive := false, tex_path := "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	if tex_path != "":
		m.albedo_texture = tex(tex_path)
	return m


## Chamfered box mesh centered at origin. size = full extents, b = bevel width. Flat shaded, UV via triplanar.
static func bevel_box(size: Vector3, b := 0.004) -> ArrayMesh:
	var key := "bb|%s|%s" % [size, b]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var h := size * 0.5
	b = minf(b, minf(h.x, minf(h.y, h.z)) * 0.95)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# corner points: P(s, axis)
	var P := func(s: Vector3, axis: int) -> Vector3:
		var v := Vector3(s.x * (h.x - b), s.y * (h.y - b), s.z * (h.z - b))
		v[axis] = s[axis] * h[axis]
		return v
	var signs := [-1.0, 1.0]
	# main faces
	for axis in 3:
		for sa in signs:
			var quad: Array[Vector3] = []
			var o1 := (axis + 1) % 3
			var o2 := (axis + 2) % 3
			for c in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var s := Vector3.ZERO
				s[axis] = sa
				s[o1] = c[0]
				s[o2] = c[1]
				quad.append(P.call(s, axis))
			_quad(st, quad[0], quad[1], quad[2], quad[3])
	# edges: for each pair of axes (a1,a2), along the third axis
	for a3 in 3:
		var a1 := (a3 + 1) % 3
		var a2 := (a3 + 2) % 3
		for s1 in signs:
			for s2 in signs:
				var sm := Vector3.ZERO
				sm[a1] = s1; sm[a2] = s2; sm[a3] = -1.0
				var sp := sm
				sp[a3] = 1.0
				_quad(st, P.call(sm, a1), P.call(sp, a1), P.call(sp, a2), P.call(sm, a2))
	# corners
	for sx in signs:
		for sy in signs:
			for sz in signs:
				var s := Vector3(sx, sy, sz)
				_tri(st, P.call(s, 0), P.call(s, 1), P.call(s, 2))
	var m := st.commit()
	_mesh_cache[key] = m
	return m


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	var out := -n.normalized()
	st.set_normal(out)
	st.add_vertex(a)
	st.set_normal(out)
	st.add_vertex(b)
	st.set_normal(out)
	st.add_vertex(c)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func cyl(radius: float, height: float, segs := 16, top_radius := -1.0) -> CylinderMesh:
	var key := "cy|%s|%s|%s|%s" % [radius, height, segs, top_radius]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top_radius < 0.0 else top_radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	_mesh_cache[key] = c
	return c


## Adds a mesh instance child. rot in degrees.
static func part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	if name != "":
		mi.name = name
	parent.add_child(mi)
	return mi

static func box(parent: Node3D, size: Vector3, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, bevel := 0.003, name := "") -> MeshInstance3D:
	return part(parent, bevel_box(size, bevel), mat, pos, rot, name)

## Cylinder oriented along Z (barrel axis).
static func tube(parent: Node3D, radius: float, length: float, mat: Material, pos := Vector3.ZERO, segs := 16, name := "", top_radius := -1.0) -> MeshInstance3D:
	return part(parent, cyl(radius, length, segs, top_radius), mat, pos, Vector3(90, 0, 0), name)
