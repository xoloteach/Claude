extends SkeletonModifier3D
## Procedural upper-body layer applied after the AnimationTree:
##  - twist: rotates the spine chain around the character's up axis so the torso/rifle keeps facing the target
##    while the legs point along the movement direction (strafing / backpedalling).
##  - pitch_extra: small extra spine pitch on top of the Pistol_Aim_* blend.
##  - recoil: spring-driven kick on spine_03 / right clavicle per shot.
##  - flinch: decaying random rotation on spine_02 when hit.

var twist := 0.0          # radians, + = torso turns left (towards +X of the model)
var pitch_extra := 0.0    # radians, + = look up
var recoil := 0.0         # 0..1ish
var _recoil_v := 0.0
## 0..1: cancel the lower body's forward lean (crouch) on the aiming upper body so the rifle stays on target.
var level_weight := 0.0
var flinch := Vector3.ZERO
var _flinch_v := Vector3.ZERO

var _spine: Array[int] = []
var _weights: Array[float] = [0.25, 0.35, 0.4]
var _clav_r := -1
var _neck := -1
var _ready_bones := false


func _setup_bones() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_spine = [sk.find_bone("spine_01"), sk.find_bone("spine_02"), sk.find_bone("spine_03")]
	_clav_r = sk.find_bone("clavicle_r")
	_neck = sk.find_bone("neck_01")
	_ready_bones = true


func kick(amount: float) -> void:
	_recoil_v += amount * 22.0


func hit_flinch(dir_local: Vector3, strength: float) -> void:
	# dir_local: bullet direction in model space
	_flinch_v += Vector3(dir_local.z * 1.0 + randf_range(-0.4, 0.4), randf_range(-1.0, 1.0), -dir_local.x) * strength * 14.0


func tick(delta: float) -> void:
	# springs (called by the rig every frame)
	var k := 260.0
	var c := 22.0
	_recoil_v += (-k * recoil - c * _recoil_v) * delta
	recoil += _recoil_v * delta
	_flinch_v += (-180.0 * flinch - 16.0 * _flinch_v) * delta
	flinch += _flinch_v * delta


func _rotate_bone_global(sk: Skeleton3D, bone: int, axis_model: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.0001:
		return
	var parent := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var axis_local := (pb.inverse() * axis_model).normalized()
	var q := sk.get_bone_pose_rotation(bone)
	sk.set_bone_pose_rotation(bone, Quaternion(axis_local, angle) * q)


func _process_modification() -> void:
	if not _ready_bones:
		_setup_bones()
		if not _ready_bones:
			return
	var sk := get_skeleton()
	if level_weight > 0.001:
		var y := sk.get_bone_global_pose(_spine[0]).basis.y.normalized()
		var cur := atan2(y.z, y.y)
		var rest := 0.102   # spine_01 rest tilt (rad, forward)
		_rotate_bone_global(sk, _spine[1], Vector3.RIGHT, (rest - cur) * level_weight)
	for i in 3:
		var b := _spine[i]
		_rotate_bone_global(sk, b, Vector3.UP, twist * _weights[i])
		if i == 2:
			_rotate_bone_global(sk, b, Vector3.RIGHT, -pitch_extra * 0.6 - recoil * 0.09 + flinch.x * 0.08)
			_rotate_bone_global(sk, b, Vector3.FORWARD, flinch.z * 0.06)
		elif i == 1:
			_rotate_bone_global(sk, b, Vector3.RIGHT, -pitch_extra * 0.4 + flinch.x * 0.1)
			_rotate_bone_global(sk, b, Vector3.UP, flinch.y * 0.08)
	if _clav_r >= 0:
		_rotate_bone_global(sk, _clav_r, Vector3.RIGHT, -recoil * 0.05)
