class_name ViewmodelArms
extends Node3D
## Procedural first-person arms (sleeves + gloves) solved with 2-bone IK toward weapon grip markers.
## Lives in the camera's local space (child of the viewmodel root).

const UPPER_LEN := 0.33
const FORE_LEN := 0.33

var shoulder_r := Vector3(0.2, -0.3, 0.02)
var shoulder_l := Vector3(-0.17, -0.3, -0.02)
var pole_r := Vector3(1.0, -1.2, 0.4)
var pole_l := Vector3(-1.0, -1.4, 0.2)

var target_r: Node3D   # grip markers (global transforms read each frame)
var target_l: Node3D
var left_override: Node3D   # e.g. magazine during reload
var left_override_w := 0.0

var _upper: Array[MeshInstance3D] = []
var _fore: Array[MeshInstance3D] = []
var _cuff: Array[MeshInstance3D] = []
var _hand: Array[Node3D] = []


func _ready() -> void:
	var sleeve := MeshKit.pbr("camo_fabric", Color(0.8, 0.8, 0.78), 5.0, false, {"normal_scale": 1.2})
	var glove := MeshKit.pbr("fabric_uniform", Color(0.13, 0.13, 0.12), 14.0, false, {"normal_scale": 1.5})
	var leather := MeshKit.pbr("polymer", Color(0.26, 0.24, 0.2), 12.0, false)
	var watch := MeshKit.flat(Color(0.05, 0.05, 0.05), 0.4, 0.2)
	for i in 2:
		var up := MeshInstance3D.new()
		up.mesh = MeshKit.cyl(0.05, 1.0, 14, 0.045)
		up.material_override = sleeve
		add_child(up)
		_upper.append(up)
		var fo := MeshInstance3D.new()
		fo.mesh = MeshKit.cyl(0.043, 1.0, 14, 0.034)
		fo.material_override = sleeve
		add_child(fo)
		_fore.append(fo)
		var cf := MeshInstance3D.new()
		cf.mesh = MeshKit.cyl(0.036, 0.05, 14, 0.033)
		cf.material_override = leather if i == 1 else glove
		add_child(cf)
		_cuff.append(cf)
		var h := _make_hand(glove, leather, i == 0)
		add_child(h)
		_hand.append(h)
		if i == 1:
			MeshKit.part(cf, MeshKit.cyl(0.037, 0.022, 14), watch, Vector3(0, -0.005, 0))
	for m in _upper + _fore + _cuff:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _make_hand(glove: Material, leather: Material, right: bool) -> Node3D:
	# Fist wrapped around a grip. Local frame: -Z forward (along weapon), grip axis ~Y.
	var h := Node3D.new()
	var s := 1.0 if right else -1.0
	MeshKit.box(h, Vector3(0.05, 0.085, 0.07), glove, Vector3(0, 0, 0.005), Vector3.ZERO, 0.018)       # palm/fist core
	for f in 4:  # fingers wrapping forward of grip
		MeshKit.box(h, Vector3(0.056, 0.019, 0.03), glove, Vector3(-s * 0.004, 0.03 - f * 0.021, -0.034), Vector3(0, 0, 0), 0.008)
	MeshKit.box(h, Vector3(0.02, 0.02, 0.055), glove, Vector3(-s * 0.024, 0.036, -0.012), Vector3(-15, s * 10, 0), 0.008)   # thumb
	MeshKit.box(h, Vector3(0.052, 0.03, 0.03), leather, Vector3(s * 0.002, 0.012, 0.03), Vector3.ZERO, 0.008)            # knuckle pad
	return h


func _solve(shoulder: Vector3, target: Vector3, pole: Vector3) -> Vector3:
	var d := target - shoulder
	var dist := clampf(d.length(), 0.05, UPPER_LEN + FORE_LEN - 0.001)
	var dir := d.normalized()
	# law of cosines: distance along dir to elbow projection
	var a := (UPPER_LEN * UPPER_LEN - FORE_LEN * FORE_LEN + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(UPPER_LEN * UPPER_LEN - a * a, 0.0))
	var pole_dir := (pole - dir * pole.dot(dir)).normalized()
	return shoulder + dir * a + pole_dir * h


func _orient_segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var y := b - a
	var length := y.length()
	if length < 0.001:
		return
	y /= length
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)


func update_arms() -> void:
	var inv := global_transform.affine_inverse()
	for i in 2:
		var t: Node3D = target_r if i == 0 else target_l
		if t == null or not is_instance_valid(t):
			visible = false
			return
		visible = true
		var hand_xf: Transform3D = inv * t.global_transform
		if i == 1 and left_override and is_instance_valid(left_override) and left_override_w > 0.001:
			var o: Transform3D = inv * left_override.global_transform
			hand_xf = hand_xf.interpolate_with(Transform3D(hand_xf.basis, o.origin), left_override_w)
		var hb := hand_xf.basis.orthonormalized()
		var wrist := hand_xf.origin + hb * Vector3((0.01 if i == 0 else -0.01), -0.02, 0.055)
		if i == 1:
			wrist = hand_xf.origin + hb * Vector3(-0.035, -0.035, 0.04)
		var sh := shoulder_r if i == 0 else shoulder_l
		var pole := pole_r if i == 0 else pole_l
		var elbow := _solve(sh, wrist, pole)
		# re-normalise forearm length so wrist lands on target even if unreachable
		_orient_segment(_upper[i], sh, elbow)
		_orient_segment(_fore[i], elbow, wrist)
		var cuff_end := wrist.lerp(elbow, 0.12)
		_orient_segment(_cuff[i], wrist, cuff_end)
		_cuff[i].transform.basis = _cuff[i].transform.basis.orthonormalized()
		_hand[i].transform = Transform3D(hb, hand_xf.origin)
		if i == 1:
			_hand[i].transform = Transform3D(hb * Basis(Vector3.FORWARD, deg_to_rad(-70.0)), hand_xf.origin + hb * Vector3(-0.018, -0.02, 0))
