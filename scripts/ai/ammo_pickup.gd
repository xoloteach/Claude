extends Area3D
## Ammo box dropped by enemies. Walk over it: refills 40% of every weapon's reserve.

const LIFETIME := 30.0
var _t := 0.0
var _mesh: Node3D
var _taken := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Game.L_PLAYER
	monitoring = true
	monitorable = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.9
	cs.shape = sh
	cs.position.y = 0.5
	add_child(cs)
	_mesh = Node3D.new()
	add_child(_mesh)
	var olive := MeshKit.pbr("polymer", Color(0.33, 0.36, 0.22), 8.0, false)
	var dark := MeshKit.flat(Color(0.08, 0.08, 0.07), 0.6, 0.3)
	var yellow := MeshKit.flat(Color(0.9, 0.72, 0.2), 0.5, 0.0, Color(0.9, 0.72, 0.2), 0.4)
	MeshKit.box(_mesh, Vector3(0.3, 0.17, 0.14), olive, Vector3(0, 0.085, 0), Vector3.ZERO, 0.012)
	MeshKit.box(_mesh, Vector3(0.31, 0.03, 0.15), dark, Vector3(0, 0.17, 0), Vector3.ZERO, 0.006)
	MeshKit.box(_mesh, Vector3(0.1, 0.02, 0.03), dark, Vector3(0, 0.195, 0), Vector3.ZERO, 0.006)
	MeshKit.box(_mesh, Vector3(0.18, 0.035, 0.002), yellow, Vector3(0, 0.1, 0.071))
	_mesh.rotation.y = randf() * TAU
	body_entered.connect(_on_body)
	# settle on the ground
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + Vector3.DOWN * 3.0, Game.L_WORLD | Game.L_PROPS)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		global_position = r.position


func _process(delta: float) -> void:
	_t += delta
	_mesh.rotation.y += delta * 1.2
	_mesh.position.y = 0.05 + sin(_t * 2.5) * 0.03
	if _t > LIFETIME:
		queue_free()


func _on_body(b: Node) -> void:
	if _taken or not b.is_in_group("player"):
		return
	var w = b.get("weapons")
	if w and w.has_method("refill_all"):
		w.refill_all(0.4)
	_taken = true
	Audio.play("pickup_ammo", -2.0)
	Game.message("+AMMO|", "popup")
	queue_free()
