extends Node3D
## Level builder (TEMPORARY test yard — will be replaced by the full dockyard map).
## API used by the rest of the game:
##   build(), get_player_spawn() -> Transform3D, get_enemy_spawns() -> Array[Vector3],
##   get_menu_camera_path() -> Array[Transform3D], apply_quality(q), nav_region: NavigationRegion3D

var nav_region: NavigationRegion3D
var geo: Node3D
var enemy_spawns: Array[Vector3] = []


func build() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	geo = Node3D.new()
	geo.name = "Geo"
	nav_region.add_child(geo)
	var asphalt := MeshKit.pbr("asphalt", Color(0.9, 0.9, 0.9), 0.25)
	var concrete := MeshKit.pbr("concrete_wall", Color(0.85, 0.85, 0.85), 0.35)
	add_box(Vector3(120, 1, 120), Vector3(0, -0.5, 0), asphalt, "concrete")
	for i in 8:
		var a := i * TAU / 8.0
		var c := MeshKit.pbr("corrugated_metal", Color.from_hsv(randf(), 0.6, 0.6), 0.4)
		add_box(Vector3(2.44, 2.6, 6.06), Vector3(cos(a) * 18, 1.3, sin(a) * 18), c, "metal", Vector3(0, rad_to_deg(a), 0))
	add_box(Vector3(6, 1.0, 0.5), Vector3(0, 0.5, -6), concrete, "concrete")
	add_box(Vector3(4, 1.6, 4), Vector3(6, 0.8, -10), concrete, "concrete")
	for i in 6:
		enemy_spawns.append(Vector3(cos(i) * 35, 0.2, sin(i) * 35))
	bake_nav()


func add_box(size: Vector3, pos: Vector3, mat: Material, surface := "concrete", rot := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = Game.L_WORLD
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees = rot
	sb.set_meta("surface", surface)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	geo.add_child(sb)
	return sb


func bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Game.L_WORLD
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	nav_region.navigation_mesh = nm


func get_player_spawn() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 4))


func get_enemy_spawns() -> Array[Vector3]:
	return enemy_spawns


func get_menu_camera_path() -> Array:
	var arr := []
	for i in 4:
		var a := i * TAU / 4.0
		var p := Vector3(cos(a) * 26, 6, sin(a) * 26)
		arr.append(Transform3D(Basis.IDENTITY, p).looking_at(Vector3(0, 1.5, 0)))
	return arr


func apply_quality(_q: int) -> void:
	pass
