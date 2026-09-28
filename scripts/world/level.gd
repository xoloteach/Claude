extends Node3D
## DOCKYARD — golden-hour industrial port map for IRONLINE.
##
## Public API (used by main.gd / AI / wave director):
##   build(), configure_environment(env, sun), get_player_spawn() -> Transform3D,
##   get_enemy_spawns() -> Array[Vector3], get_cover_points() -> Array[Vector3],
##   get_menu_camera_path() -> Array[Transform3D], apply_quality(q), nav_region: NavigationRegion3D
##
## Layout (X east, Z south, Y up; playable x -56..63, z -62..63; see docs/LEVEL.md):
##   west  : quay apron x -56..-42 (long sniper lane N-S), water beyond, moored ship hull NW, 2 gantry cranes
##   centre: container yard x -42..8, four rows of stacks, steel stair + catwalks at z≈-22
##   east  : road x 8..18, warehouse x 18..60 / z -48..6 (CQB), east alley x 60..63, office x 22..38 / z 34..46
##   south : truck yard / gate z 48..63 (player spawn), north: service road z -62..-48 (enemy side)

const WKit := preload("res://scripts/world/wkit.gd")
const Layout := preload("res://scripts/world/dock_layout.gd")
const Buildings := preload("res://scripts/world/dock_buildings.gd")
const Dressing := preload("res://scripts/world/dock_dressing.gd")
const Backdrop := preload("res://scripts/world/dock_backdrop.gd")

## Direction toward the sun in the unrotated HDRI (see assets/CREDITS.md).
const HDRI_SUN := Vector3(-0.584, 0.108, 0.804)
const SKY_YAW_DEG := -36.0
const SUN_ELEV_DEG := 11.5

var nav_region: NavigationRegion3D
var geo: Node3D
var kit: WKit
var enemy_spawns: Array[Vector3] = []
var _spawns_raw: Array[Vector3] = []
var _cover_cache: Array[Vector3] = []
var _cover_done := false
var _spawns_done := false

# quality-tiered content: [node, min_quality]
var tiered: Array = []
var flickers: Array = []        # [OmniLight3D/SpotLight3D, base_energy, kind]
var fx_nodes: Array = []        # animated emissive/particle helpers
var dust: CPUParticles3D
var quality := 2
var sun_dir := Vector3(-0.9, 0.2, 0.3)   # toward the sun (set in configure_environment)
var _t := 0.0
var _stat_t := 3.0
var _spark_timer := 2.0
var sparks: Array = []


func build() -> void:
	var t0 := Time.get_ticks_msec()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	geo = Node3D.new()
	geo.name = "Geo"
	add_child(geo)
	var col_root := Node3D.new()
	col_root.name = "Collision"
	nav_region.add_child(col_root)
	kit = WKit.new(geo, col_root)
	var tl := [Time.get_ticks_msec()]
	_compute_sun_dir()
	_define_materials()
	tl.append(Time.get_ticks_msec())
	Layout.build(kit, self)
	tl.append(Time.get_ticks_msec())
	Buildings.build(kit, self)
	tl.append(Time.get_ticks_msec())
	Backdrop.build(kit, self)
	tl.append(Time.get_ticks_msec())
	Dressing.build(kit, self)
	tl.append(Time.get_ticks_msec())
	var nverts := 0
	for key in kit.batches:
		nverts += (kit.batches[key].v as PackedVector3Array).size()
	var nb := kit.batches.size()
	if OS.get_cmdline_user_args().has("--level-stats"):
		var per := {}
		for key in kit.batches:
			var m: String = kit.batches[key].mat
			per[m] = per.get(m, 0) + (kit.batches[key].v as PackedVector3Array).size()
		print("[level] verts per material: ", per)
	kit.finish()
	var t1 := Time.get_ticks_msec()
	tl.append(t1)
	bake_nav()
	var t2 := Time.get_ticks_msec()
	var polys := nav_region.navigation_mesh.get_polygon_count() if nav_region.navigation_mesh else 0
	print("[level] build %d ms (kit/mats %d, layout %d, buildings %d, backdrop %d, dressing %d, finish %d), navmesh %d ms polys=%d, batches=%d verts=%d cover_boxes=%d" % [
		t1 - t0, tl[1] - tl[0], tl[2] - tl[1], tl[3] - tl[2], tl[4] - tl[3], tl[5] - tl[4], tl[6] - tl[5], t2 - t1, polys, nb, nverts, kit.cover_boxes.size()])
	set_process(true)


func _compute_sun_dir() -> void:
	var d := Basis(Vector3.UP, deg_to_rad(SKY_YAW_DEG)) * HDRI_SUN
	var hz := Vector2(d.x, d.z).normalized()
	var e := deg_to_rad(SUN_ELEV_DEG)
	sun_dir = Vector3(hz.x * cos(e), sin(e), hz.y * cos(e)).normalized()


# ------------------------------------------------------------------ materials
func _define_materials() -> void:
	var k := kit
	k.def_surface("ground", "concrete_floor", {"scale": 0.23, "tint": Color(0.74, 0.72, 0.68), "macro_strength": 0.32, "ground_ao": 0.0, "grime": 0.0, "rough_mul": 1.0})
	k.def_surface("floor_in", "concrete_floor", {"scale": 0.2, "tint": Color(0.52, 0.52, 0.5), "macro_strength": 0.25, "ground_ao": 0.0, "grime": 0.0, "rough_mul": 0.55, "specular": 0.55})
	k.def_surface("asphalt", "asphalt", {"scale": 0.18, "tint": Color(0.62, 0.6, 0.58), "macro_strength": 0.3, "ground_ao": 0.0, "grime": 0.0})
	k.def_surface("quay", "concrete_wall", {"scale": 0.2, "tint": Color(0.72, 0.7, 0.66), "macro_strength": 0.35, "ground_ao": 0.0, "grime": 0.0})
	k.def_surface("concrete", "concrete_wall", {"scale": 0.35, "tint": Color(0.78, 0.76, 0.72), "ground_ao": 0.5, "grime": 0.45, "grime_height": 0.9})
	k.def_surface("concrete_dark", "concrete_floor", {"scale": 0.3, "tint": Color(0.5, 0.49, 0.46), "ground_ao": 0.3, "grime": 0.6, "grime_height": 3.0, "grime_color": Color(0.16, 0.18, 0.12)})
	k.def_surface("brick", "brick", {"scale": 0.45, "tint": Color(0.8, 0.72, 0.68), "ground_ao": 0.55, "grime": 0.5})
	k.def_surface("cladding", "corrugated_metal", {"scale": 0.42, "tint": Color(0.62, 0.66, 0.66), "stack_h": 10.02, "streaks": 0.65, "ground_ao": 0.3, "grime": 0.3, "metallic": 0.25, "rough_mul": 0.9})
	k.def_surface("cladding_dark", "corrugated_metal", {"scale": 0.42, "tint": Color(0.32, 0.33, 0.33), "ground_ao": 0.0, "grime": 0.0, "metallic": 0.3})
	var cont = k.def_surface("container", "corrugated_metal", {"scale": 0.42, "normal_strength": 0.35, "stack_h": 2.59, "streaks": 0.55, "grime": 0.5, "grime_height": 0.7, "ground_ao": 0.4, "ground_ao_height": 0.6, "metallic": 0.15, "rough_mul": 0.95, "macro_strength": 0.18})
	k.def_mat("container_far", cont)
	k.def_surface("steel", "painted_metal", {"flatten": 0.75, "scale": 0.9, "metallic": 0.35, "rough_mul": 0.85, "ground_ao": 0.3, "grime": 0.25, "macro_strength": 0.15})
	k.def_surface("rusty", "rusty_metal", {"scale": 0.35, "tint": Color(0.7, 0.66, 0.62), "metallic": 0.4, "ground_ao": 0.3, "grime": 0.3})
	k.def_surface("hull", "painted_metal", {"scale": 0.12, "stack_h": 12.02, "streaks": 1.0, "streak_color": Color(0.3, 0.15, 0.07), "grime": 0.0, "ground_ao": 0.0, "metallic": 0.3, "macro_strength": 0.35})
	k.def_surface("plate", "metal_plate", {"scale": 0.8, "metallic": 0.6, "ground_ao": 0.0, "grime": 0.0})
	k.def_surface("wood", "wood_planks", {"scale": 0.9, "ground_ao": 0.35, "grime": 0.3, "grime_height": 0.4})
	k.def_mat("wood_floor", k.mats["wood"])
	k.def_surface("plaster", "plaster", {"scale": 0.35, "tint": Color(0.86, 0.84, 0.78), "ground_ao": 0.5, "grime": 0.45})
	k.def_surface("plaster_in", "plaster", {"scale": 0.35, "tint": Color(0.62, 0.64, 0.62), "ground_ao": 0.5, "grime": 0.2})
	k.def_surface("tarp", "fabric_tarp", {"scale": 0.8, "ground_ao": 0.2, "grime": 0.2})
	k.def_surface("cardboard", "fabric_tarp", {"scale": 1.4, "tint": Color(0.78, 0.6, 0.42), "normal_strength": 0.3, "ground_ao": 0.2, "grime": 0.1, "macro_strength": 0.1})
	k.def_surface("rubber", "polymer", {"scale": 1.0, "tint": Color(0.5, 0.5, 0.5), "ground_ao": 0.0, "grime": 0.0, "rough_mul": 0.9})
	k.def_surface("dirt_ground", "ground_dirt", {"scale": 0.3, "ground_ao": 0.0, "grime": 0.0})
	var grate := MeshKit.pbr("metal_grate", Color(0.7, 0.7, 0.7), 1.2, true, {"alpha": true}).duplicate()
	grate.vertex_color_use_as_albedo = true
	k.def_mat("grate", grate)
	var fence := MeshKit.pbr("metal_grate", Color(0.75, 0.75, 0.72), 2.6, true, {"alpha": true}).duplicate()
	fence.vertex_color_use_as_albedo = true
	k.def_mat("fence", fence)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.13, 0.15, 0.55)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.08
	glass.metallic_specular = 0.9
	k.def_mat("glass", glass)
	k.def_mat("emit_warm", _emissive(Color(1.0, 0.72, 0.42), 5.0))
	k.def_mat("emit_cool", _emissive(Color(0.82, 0.9, 1.0), 4.0))
	k.def_mat("emit_red", _emissive(Color(1.0, 0.12, 0.06), 6.0))
	k.def_mat("emit_green", _emissive(Color(0.2, 1.0, 0.45), 3.0))
	k.def_mat("emit_window", _emissive(Color(1.0, 0.78, 0.52), 1.6))
	k.def_mat("emit_sky", _emissive(Color(0.75, 0.8, 0.85), 0.45))
	k.def_mat("black", MeshKit.flat(Color(0.03, 0.03, 0.03), 0.9))
	var bd := ShaderMaterial.new()
	bd.shader = load("res://assets/shaders/world_backdrop.gdshader")
	k.def_mat("backdrop", bd)
	k.shader_mat("paint", "res://assets/shaders/world_paint.gdshader", {"tex_normal": k.tex("asphalt", "normal.jpg")})
	k.shader_mat("blob", "res://assets/shaders/world_blob.gdshader")
	k.shader_mat("puddle", "res://assets/shaders/world_wet.gdshader", {"tex_normal": k.tex("asphalt", "normal.jpg"), "roughness": 0.05, "specular": 0.7, "normal_flat": 0.92, "ripple": 0.25})
	k.shader_mat("dirt_decal", "res://assets/shaders/world_wet.gdshader", {"tex_albedo": k.tex("ground_dirt", "albedo.jpg"), "tex_normal": k.tex("ground_dirt", "normal.jpg"), "use_tex": 1.0, "tex_scale": 0.3, "roughness": 0.95, "specular": 0.3, "edge_noise": 0.9})
	k.shader_mat("shaft", "res://assets/shaders/world_shaft.gdshader", {"intensity": 1.0, "near_fade": 4.0})
	var water := k.shader_mat("water", "res://assets/shaders/world_water.gdshader", {"tex_n1": k.water_normal})
	water.render_priority = -1


func _emissive(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.6
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.roughness = 0.5
	m.vertex_color_use_as_albedo = false
	return m


# ------------------------------------------------------------------ helpers used by the builders
## Registers a node that exists only at quality >= min_q.
func tier(n: Node3D, min_q: int) -> Node3D:
	tiered.append([n, min_q])
	return n


func add_omni(pos: Vector3, color: Color, energy: float, rng: float, min_q := 1, flicker := "", shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadow
	l.light_specular = 0.4
	l.distance_fade_enabled = true
	l.distance_fade_begin = 60.0
	l.distance_fade_length = 20.0
	geo.add_child(l)
	tier(l, min_q)
	if flicker != "":
		flickers.append([l, energy, flicker, randf() * 10.0])
	return l


func add_spot(pos: Vector3, dir: Vector3, color: Color, energy: float, rng: float, angle: float, min_q := 1) -> SpotLight3D:
	var l := SpotLight3D.new()
	geo.add_child(l)
	l.position = pos
	l.basis = Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD)
	l.light_color = color
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_attenuation = 0.8
	l.spot_angle_attenuation = 1.5
	l.shadow_enabled = false
	l.light_specular = 0.3
	l.distance_fade_enabled = true
	l.distance_fade_begin = 90.0
	l.distance_fade_length = 30.0
	tier(l, min_q)
	return l


func add_spawn(p: Vector3) -> void:
	_spawns_raw.append(p)


# ------------------------------------------------------------------ navigation
func bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.region_min_size = 4.0
	nm.edge_max_error = 1.3
	nm.detail_sample_distance = 6.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Game.L_WORLD
	nm.filter_baking_aabb = AABB(Vector3(-57, -1.5, -64), Vector3(122, 16, 128))
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, nav_region)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	nav_region.navigation_mesh = nm


func _nav_ready() -> bool:
	if nav_region == null:
		return false
	var map := nav_region.get_navigation_map()
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0


# ------------------------------------------------------------------ API
func get_player_spawn() -> Transform3D:
	# south truck yard, facing north up the central yard lane (yaw 0 = -Z)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(8.0)), Vector3(-4.0, 0.05, 55.0))


func get_enemy_spawns() -> Array[Vector3]:
	if not _spawns_done and _nav_ready():
		_spawns_done = true
		enemy_spawns.clear()
		var map := nav_region.get_navigation_map()
		for p in _spawns_raw:
			var c := NavigationServer3D.map_get_closest_point(map, p)
			if c.distance_to(p) < 2.5 and c.y < 0.6:
				enemy_spawns.append(c + Vector3(0, 0.05, 0))
			else:
				push_warning("[level] enemy spawn %s is off the navmesh (closest %s)" % [p, c])
	if enemy_spawns.is_empty():
		var out: Array[Vector3] = []
		for p in _spawns_raw:
			out.append(p)
		return out
	return enemy_spawns


## Points on the navmesh right next to waist/full-height cover (for the enemy AI).
func get_cover_points() -> Array[Vector3]:
	if _cover_done or not _nav_ready():
		return _cover_cache
	_cover_done = true
	var map := nav_region.get_navigation_map()
	var seen := {}
	for ab: AABB in kit.cover_boxes:
		if ab.position.y > 0.4 or ab.size.y < 0.8:
			continue
		var c := ab.get_center()
		var hx := ab.size.x * 0.5 + 0.75
		var hz := ab.size.z * 0.5 + 0.75
		var cand: Array[Vector3] = []
		for s: float in [-1.0, 1.0]:
			var nx := maxi(1, int(ab.size.x / 2.5))
			for i in nx:
				var fx := (i + 0.5) / nx - 0.5
				cand.append(Vector3(c.x + fx * ab.size.x, 0.0, c.z + s * hz))
			var nz := maxi(1, int(ab.size.z / 2.5))
			for i in nz:
				var fz := (i + 0.5) / nz - 0.5
				cand.append(Vector3(c.x + s * hx, 0.0, c.z + fz * ab.size.z))
		for p in cand:
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > 0.35 or q.y > 0.5:
				continue
			var key := Vector2i(roundi(q.x / 1.5), roundi(q.z / 1.5))
			if seen.has(key):
				continue
			seen[key] = true
			_cover_cache.append(q)
	return _cover_cache


func get_menu_camera_path() -> Array:
	var keys := [
		[Vector3(-86.0, 5.5, 42.0), Vector3(-50.0, 9.0, -8.0)],      # over the water, quay + cranes, sun behind
		[Vector3(-52.0, 17.0, 18.0), Vector3(-10.0, 2.0, -20.0)],    # high above the quay looking into the yard
		[Vector3(-19.0, 2.4, 16.0), Vector3(-20.0, 3.5, -40.0)],     # low in the central yard lane
		[Vector3(13.5, 2.0, 30.0), Vector3(12.0, 3.2, -30.0)],       # the road: lamps, warehouse facade
		[Vector3(34.0, 11.0, 58.0), Vector3(-40.0, 12.0, -12.0)],    # over the office, toward the sunset + cranes
	]
	var out := []
	for k in keys:
		out.append(Transform3D(Basis.IDENTITY, k[0]).looking_at(k[1], Vector3.UP))
	return out


func configure_environment(env: Environment, sun: DirectionalLight3D) -> void:
	env.sky_rotation = Vector3(0.0, deg_to_rad(SKY_YAW_DEG), 0.0)
	if env.sky and env.sky.sky_material is PanoramaSkyMaterial:
		(env.sky.sky_material as PanoramaSkyMaterial).energy_multiplier = 1.0
	env.background_energy_multiplier = 0.65
	sun.global_basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_color = Color(1.0, 0.7, 0.46)
	sun.light_energy = 2.6
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.0
	sun.light_specular = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.42, 0.5, 0.66)
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.92
	env.tonemap_white = 10.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.7, 0.55, 0.45)
	env.fog_light_energy = 0.85
	env.fog_sun_scatter = 0.18
	env.fog_density = 0.0075
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.3
	env.fog_height = 3.0
	env.fog_height_density = 0.025
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.2
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.06
	# water reflects the sky colour near the sun
	var wm: ShaderMaterial = kit.mats.get("water")
	if wm:
		wm.set_shader_parameter("sky_tint", Color(0.62, 0.46, 0.38))


var _checked := false

## Debug self-test (run with `godot --headless -- --test --level-check`): navmesh coverage / reachability.
func _self_check() -> void:
	var map := nav_region.get_navigation_map()
	var sp := get_player_spawn().origin
	var start := NavigationServer3D.map_get_closest_point(map, sp)
	var sp_ok := start.distance_to(sp) < 1.0
	var sh := CapsuleShape3D.new()
	sh.radius = 0.34
	sh.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, sp + Vector3(0, 0.95, 0))
	q.collision_mask = Game.L_WORLD
	var blocked := not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
	print("[level-check] player spawn on navmesh=%s, capsule blocked=%s" % [sp_ok, blocked])
	var targets := {"catwalk": Vector3(-14.0, 5.18, -20.5), "stack_top_stair": Vector3(-2.7, 5.18, -24.0), "office_upper": Vector3(27.0, 3.5, 40.0),
		"warehouse": Vector3(40.0, 0.0, -20.0), "quay_north": Vector3(-50.0, 0.0, -55.0), "east_alley": Vector3(61.8, 0.0, -10.0),
		"truck_yard": Vector3(-25.0, 0.0, 60.0), "storage": Vector3(40.0, 0.0, -55.0)}
	for e in get_enemy_spawns():
		targets["spawn_%d_%d" % [roundi(e.x), roundi(e.z)]] = e
	var fails := 0
	for k in targets:
		var t: Vector3 = targets[k]
		var path := NavigationServer3D.map_get_path(map, start, t, true)
		var ok := path.size() > 0 and path[path.size() - 1].distance_to(t) < 1.2
		if not ok:
			fails += 1
		print("[level-check] path to %s %s: %s (end %s)" % [k, t, "OK" if ok else "FAIL", path[path.size() - 1] if path.size() > 0 else "none"])
	print("[level-check] enemy spawns=%d/%d cover points=%d path failures=%d" % [get_enemy_spawns().size(), _spawns_raw.size(), get_cover_points().size(), fails])
	if not OS.get_cmdline_user_args().has("--test"):
		_play_check()


## Movement checks with the real player controller (only without the generic --test runner).
func _play_check() -> void:
	Game.run_command("start")
	Game.run_command("god")
	await get_tree().create_timer(0.5).timeout
	var cases := [
		# name, start, yaw, seconds, jump taps, expect(func(pos) -> bool)
		["mantle crate+container C-01", Vector3(-35.9, 0.1, 15.0), 0.0, 4.0, true, func(p: Vector3): return p.y > 2.4],
		["stair to B-04 platform", Vector3(1.9, 0.1, -10.5), 0.0, 6.0, false, func(p: Vector3): return p.y > 5.0],
		["catwalk B-04 -> B-03", Vector3(-3.0, 5.3, -24.0), 90.0, 2.2, false, func(p: Vector3): return p.y > 5.0 and p.x < -11.5],
		["office external stair", Vector3(21.05, 0.1, 47.0), 0.0, 5.0, false, func(p: Vector3): return p.y > 3.3],
		["quay edge blocked", Vector3(-52.0, 0.1, 0.0), 90.0, 3.0, true, func(p: Vector3): return p.x > -56.0 and p.y > -0.5],
		["east wall blocked", Vector3(61.5, 0.1, 20.0), -90.0, 3.0, true, func(p: Vector3): return p.x < 63.6],
		["south fence blocked", Vector3(-20.0, 0.1, 60.0), 180.0, 3.0, true, func(p: Vector3): return p.z < 63.4],
		["north wall blocked", Vector3(-20.0, 0.1, -58.0), 0.0, 3.0, true, func(p: Vector3): return p.z > -62.4],
		["barrier mantle (quay)", Vector3(-47.5, 0.1, -9.0), 30.0, 3.0, true, func(p: Vector3): return true],
	]
	for c in cases:
		var pl: Node3D = Game.player
		Game.run_command("teleport %f %f %f" % [c[1].x, c[1].y, c[1].z])
		Game.run_command("face %f 0" % c[2])
		await get_tree().create_timer(0.3).timeout
		Game.run_command("move fwd on")
		var t := 0.0
		var top := -100.0
		var minx := 1000.0
		while t < c[3]:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
			top = maxf(top, pl.global_position.y)
			minx = minf(minx, pl.global_position.x)
			if c[4] or int(t * 4.0) % 4 == 0:
				Game.run_command("key jump")
		Game.run_command("move fwd off")
		await get_tree().create_timer(0.4).timeout
		var p: Vector3 = pl.global_position
		if c[0].begins_with("mantle") or c[0].begins_with("stair") or c[0].begins_with("office"):
			p.y = top
		if c[0].begins_with("catwalk"):
			p = Vector3(minx, top, p.z)
		print("[level-check] %s: %s pos=%s" % [c[0], "OK" if c[5].call(p) else "FAIL", p])
	get_tree().quit()


func apply_quality(q: int) -> void:
	quality = q
	for e in tiered:
		var n: Node3D = e[0]
		if is_instance_valid(n):
			n.visible = q >= int(e[1])
			if n is GPUParticles3D or n is CPUParticles3D:
				n.emitting = n.visible
	var vr: float = [45.0, 70.0, 110.0][q]
	for n in kit.detail_nodes:
		if is_instance_valid(n):
			n.visibility_range_end = vr
			n.visibility_range_end_margin = 8.0
			n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if dust:
		dust.amount = [1, 60, 140][q]
		dust.emitting = q >= 1


# ------------------------------------------------------------------ runtime ambience
func _process(delta: float) -> void:
	_t += delta
	for f in flickers:
		var l: Light3D = f[0]
		if not l.visible:
			continue
		var base: float = f[1]
		match f[2]:
			"fire":
				l.light_energy = base * (0.75 + 0.25 * sin(_t * 13.0 + f[3]) * sin(_t * 7.3 + f[3] * 2.0) + randf() * 0.12)
			"fluoro":
				var ph := fmod(_t + f[3], 7.0)
				var on := ph > 1.2 or (int(_t * 23.0) % 3 != 0 and ph > 0.4)
				l.light_energy = base if on else base * 0.05
				if f.size() > 4 and f[4]:
					(f[4] as GeometryInstance3D).visible = on
			"blink":
				l.light_energy = base if fmod(_t + f[3], 1.6) < 0.8 else 0.0
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = randf_range(1.5, 4.5)
		for s in sparks:
			var p: CPUParticles3D = s[0]
			if p.visible:
				p.restart()
				p.emitting = true
				var fl: OmniLight3D = s[1]
				if fl and fl.visible:
					fl.light_energy = 3.0
	for s in sparks:
		var fl: OmniLight3D = s[1]
		if fl:
			fl.light_energy = maxf(0.0, fl.light_energy - delta * 12.0)
	if not _checked and _t > 1.5 and OS.get_cmdline_user_args().has("--level-check") and _nav_ready():
		_checked = true
		_self_check()
	_stat_t -= delta
	if _stat_t <= 0.0:
		_stat_t = 5.0
		var want := OS.get_cmdline_user_args().has("--level-stats")
		if OS.has_feature("web"):
			want = str(JavaScriptBridge.eval("String(window.level_stats || 0)", true)) == "1"
		if want:
			print("[level] perf fps=%d draw_calls=%d objects=%d primitives=%d vram_mb=%d" % [Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	if dust and dust.emitting:
		var cam := get_viewport().get_camera_3d()
		if cam:
			dust.global_position = cam.global_position
