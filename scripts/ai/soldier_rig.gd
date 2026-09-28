extends Node3D
## Visual + animation rig for an enemy soldier: Quaternius soldier.glb, per-archetype gear (helmet, plate carrier,
## pouches, backpack) made from MeshKit boxes, a procedural rifle in the right hand (left hand IK'd to the
## handguard), an AnimationTree (locomotion transition + upper-body aim Blend3 + one-shots), bone-attached
## hitboxes, and a PhysicalBoneSimulator3D ragdoll built on death.
##
## Model space: the character faces +Z (Vector3.MODEL_FRONT). The owning Enemy rotates the whole rig by its facing
## yaw; this node additionally yaws the *legs* (model node) towards the movement direction while the spine twist
## keeps the torso on target.

const AimModifier := preload("res://scripts/ai/aim_modifier.gd")
const Ragdoll := preload("res://scripts/ai/ragdoll.gd")
const SOLDIER_PATH := "res://assets/models/characters/soldier.glb"
const ANIMS_PATH := "res://assets/models/characters/anims.glb"
const SK := "Armature/Skeleton3D:"

## Natural ground speed (m/s) of each locomotion clip at time scale 1.0 (measured from foot contact).
const SPEED_WALK := 1.05
const SPEED_JOG := 3.3
const SPEED_SPRINT := 4.9
const SPEED_CROUCH := 0.78

## hand_r global pose in Pistol_Aim_Neutral (measured once; used to seat the rifle in the hand).
const HAND_R_AIM := Transform3D(
	Vector3(-0.99867, -0.041918, 0.03), Vector3(0.02172, 0.185597, 0.982385), Vector3(-0.046748, 0.981731, -0.18444),
	Vector3(-0.194536, 1.406235, 0.34749))

static var _scene: PackedScene
static var _tree_root: AnimationNodeBlendTree
static var _extra_lib: AnimationLibrary
static var _body_mats := {}
static var _gear_mats := {}

var arch: Dictionary
var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var aim_mod: AimModifier
var ik: SkeletonModifier3D
var rifle: Node3D
var muzzle: Node3D
var hitboxes: Array[Area3D] = []
var ragdoll: PhysicalBoneSimulator3D
var ragdolled := false
var enemy: Node

# animation state
var _gait := "idle"
var _leg_yaw := 0.0
var _aim_amount := 0.0      # 0 = low ready, 1 = shouldered on target
var _aim_pitch := 0.0       # radians
var _anim_accum := 0.0
var lod_step := 1
var _frame := 0
var _bone_head := -1
var _bone_chest := -1
var _ba_head: Node3D
var _ba_chest: Node3D


# ------------------------------------------------------------------ shared resources
static func _load_shared() -> void:
	if _scene != null:
		return
	_scene = load(SOLDIER_PATH)
	_extra_lib = AnimationLibrary.new()
	if ResourceLoader.exists(ANIMS_PATH):
		var extra: Node = (load(ANIMS_PATH) as PackedScene).instantiate()
		var ap: AnimationPlayer = extra.find_child("AnimationPlayer", true, false)
		if ap:
			for n in ["Hit_Knockback", "OverhandThrow"]:
				if ap.has_animation(n):
					_extra_lib.add_animation(n, ap.get_animation(n))
		extra.free()
	_tree_root = _build_tree()


static func _anim(n: String, loop := true) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = n
	if not loop:
		a.use_custom_timeline = false
	return a


static func _upper_paths() -> Array[NodePath]:
	# spine_02 subtree of the Quaternius skeleton (arms, neck, head, fingers)
	var names := ["spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
		"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
	for side in ["l", "r"]:
		for f in ["index", "middle", "ring", "pinky", "thumb"]:
			for i in [1, 2, 3]:
				names.append("%s_0%d_%s" % [f, i, side])
	var out: Array[NodePath] = []
	for n in names:
		out.append(NodePath(SK + n))
	return out


static func _build_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var upper := _upper_paths()
	# --- locomotion: each gait clip -> TimeScale -> Transition
	var gaits := [["idle", "Idle"], ["walk", "Walk"], ["jog", "Jog_Fwd"], ["sprint", "Sprint"],
		["cidle", "Crouch_Idle"], ["cwalk", "Crouch_Fwd"]]
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.22
	tr.input_count = gaits.size()
	for i in gaits.size():
		var g: String = gaits[i][0]
		tr.set_input_name(i, g)
		tr.set_input_reset(i, false)
		bt.add_node("a_" + g, _anim(gaits[i][1]))
		var ts := AnimationNodeTimeScale.new()
		bt.add_node("ts_" + g, ts)
		bt.connect_node("ts_" + g, 0, "a_" + g)
	bt.add_node("gait", tr)
	for i in gaits.size():
		bt.connect_node("gait", i, "ts_" + gaits[i][0])
	# --- full-body stagger
	var stagger := AnimationNodeOneShot.new()
	stagger.fadein_time = 0.06
	stagger.fadeout_time = 0.25
	bt.add_node("stagger", stagger)
	bt.add_node("a_stagger", _anim("Hit_Chest", false))
	bt.connect_node("stagger", 0, "gait")
	bt.connect_node("stagger", 1, "a_stagger")
	# --- upper body aim (Down / Neutral / Up)
	var aim := AnimationNodeBlend3.new()
	bt.add_node("aim", aim)
	bt.add_node("a_down", _anim("Pistol_Aim_Down", false))
	bt.add_node("a_neutral", _anim("Pistol_Aim_Neutral", false))
	bt.add_node("a_up", _anim("Pistol_Aim_Up", false))
	bt.connect_node("aim", 0, "a_down")
	bt.connect_node("aim", 1, "a_neutral")
	bt.connect_node("aim", 2, "a_up")
	var up := AnimationNodeBlend2.new()
	up.filter_enabled = true
	for p in upper:
		up.set_filter_path(p, true)
	bt.add_node("upper", up)
	bt.connect_node("upper", 0, "stagger")
	bt.connect_node("upper", 1, "aim")
	# --- upper-body one-shots
	var last := "upper"
	for os in [["flinch", "Hit_Chest", 0.04, 0.16], ["flinch_head", "Hit_Head", 0.04, 0.18],
			["reload", "Pistol_Reload", 0.15, 0.25], ["throw", "x/OverhandThrow", 0.12, 0.25]]:
		var o := AnimationNodeOneShot.new()
		o.fadein_time = os[2]
		o.fadeout_time = os[3]
		o.filter_enabled = true
		for p in upper:
			o.set_filter_path(p, true)
		bt.add_node(os[0], o)
		bt.add_node("a_" + os[0], _anim(os[1], false))
		bt.connect_node(os[0], 0, last)
		bt.connect_node(os[0], 1, "a_" + os[0])
		last = os[0]
	# --- life (fallback death animation when ragdolls are unavailable)
	var life := AnimationNodeTransition.new()
	life.xfade_time = 0.15
	life.input_count = 2
	life.set_input_name(0, "alive")
	life.set_input_name(1, "dead")
	bt.add_node("life", life)
	bt.add_node("a_death", _anim("Death01", false))
	bt.connect_node("life", 0, last)
	bt.connect_node("life", 1, "a_death")
	bt.connect_node("output", 0, "life")
	return bt


# ------------------------------------------------------------------ build
func build(p_arch: Dictionary, variant: int, p_enemy: Node) -> void:
	_load_shared()
	arch = p_arch
	enemy = p_enemy
	model = _scene.instantiate()
	model.name = "Model"
	add_child(model)
	skeleton = model.get_node("Armature/Skeleton3D")
	anim_player = model.get_node("AnimationPlayer")
	if not anim_player.has_animation_library("x"):
		anim_player.add_animation_library("x", _extra_lib)
	_bone_head = skeleton.find_bone("Head")
	_bone_chest = skeleton.find_bone("spine_03")
	_apply_body_material(variant)
	# modifiers (order = evaluation order)
	aim_mod = AimModifier.new()
	aim_mod.name = "AimMod"
	skeleton.add_child(aim_mod)
	_build_rifle()
	_build_left_ik()
	_build_gear(variant)
	_build_hitboxes()
	_ba_head = skeleton.get_node_or_null("BA_Head")
	_ba_chest = skeleton.get_node_or_null("BA_spine_03")
	tree = AnimationTree.new()
	tree.name = "AnimTree"
	tree.tree_root = _tree_root
	model.add_child(tree)
	tree.root_node = NodePath("..")
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	tree.set("parameters/upper/blend_amount", 1.0)
	tree.set("parameters/gait/transition_request", "idle")
	tree.set("parameters/aim/blend_amount", -0.45)
	for s in ["idle", "walk", "jog", "sprint", "cidle", "cwalk"]:
		tree.set("parameters/ts_%s/scale" % s, 1.0)
	# shadows are expensive on web: only the body casts
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name in ["Eyes", "Eyebrows"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _apply_body_material(variant: int) -> void:
	var tints: Array = arch.get("tints", [Color(1, 1, 1)])
	var tint: Color = tints[variant % tints.size()]
	var body: MeshInstance3D = skeleton.get_node_or_null("SuperHero_Male")
	if body == null:
		return
	var key := tint.to_html()
	var m: Material = _body_mats.get(key)
	if m == null:
		var src: Material = body.mesh.surface_get_material(0)
		if src is BaseMaterial3D:
			m = src.duplicate()
			(m as BaseMaterial3D).albedo_color = tint
		else:
			m = src
		_body_mats[key] = m
	body.material_override = m


static func _gear_mat(kind: String, col: Color) -> Material:
	var key := kind + col.to_html()
	if _gear_mats.has(key):
		return _gear_mats[key]
	var m: StandardMaterial3D
	match kind:
		"poly":
			m = MeshKit.pbr("polymer", col, 6.0, false, {"normal_scale": 0.7})
		"fabric":
			m = MeshKit.pbr("polymer", col, 14.0, false, {"normal_scale": 1.0, "roughness": 1.0})
		"metal":
			m = MeshKit.pbr("gun_metal", col, 6.0, false, {"normal_scale": 0.5})
		"visor":
			m = MeshKit.flat(col, 0.12, 0.6)
		_:
			m = MeshKit.flat(col, 0.8)
	_gear_mats[key] = m
	return m


func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.name = "BA_" + bone
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba


## Transform expressed in the rest (T-pose) model space -> local to the given bone's rest frame.
func _rest_local(bone: String, xf_model: Transform3D) -> Transform3D:
	var bi := skeleton.find_bone(bone)
	return skeleton.get_bone_global_rest(bi).affine_inverse() * xf_model


func _gbox(parent: Node3D, bone: String, size: Vector3, pos_model: Vector3, mat: Material, rot_deg := Vector3.ZERO, bevel := 0.012) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.bevel_box(size, bevel)
	mi.material_override = mat
	mi.transform = _rest_local(bone, Transform3D(Basis.from_euler(rot_deg * PI / 180.0), pos_model))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if size.length() < 0.12 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)


func _build_gear(variant: int) -> void:
	var g: Dictionary = arch.get("gear", {})
	var gear_col: Color = g.get("color", Color(0.36, 0.34, 0.26))
	var alt := gear_col.darkened(0.25)
	var vest := _gear_mat("fabric", gear_col)
	var vest_dark := _gear_mat("fabric", alt)
	var head := _attach("Head")
	var chest := _attach("spine_03")
	var hips := _attach("pelvis")
	var helm: String = g.get("helmet", "helmet")
	# --- headgear (head centre ~ (0, 1.70, 0.0) in rest model space; face at z = +0.12)
	if helm == "helmet" or helm == "heavy":
		var hm := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.132 if helm == "helmet" else 0.142
		sph.height = sph.radius * 2.0
		sph.is_hemisphere = true
		sph.radial_segments = 20
		sph.rings = 8
		hm.mesh = sph
		var hcol: Color = g.get("helmet_color", gear_col)
		hm.material_override = _gear_mat("poly", hcol)
		hm.transform = _rest_local("Head", Transform3D(Basis.from_scale(Vector3(1.0, 0.95, 1.12)), Vector3(0, 1.715, -0.005)))
		head.add_child(hm)
		# rim + strap pads
		_gbox(head, "Head", Vector3(0.27, 0.035, 0.30), Vector3(0, 1.72, -0.01), _gear_mat("poly", hcol.darkened(0.1)), Vector3.ZERO, 0.015)
		_gbox(head, "Head", Vector3(0.05, 0.03, 0.03), Vector3(0, 1.79, 0.13), _gear_mat("metal", Color(0.2, 0.2, 0.2)))  # NVG mount
		if helm == "heavy":
			# ballistic visor + ear protection
			_gbox(head, "Head", Vector3(0.23, 0.12, 0.02), Vector3(0, 1.665, 0.145), _gear_mat("visor", Color(0.05, 0.06, 0.07)), Vector3(-8, 0, 0), 0.008)
			for s in [-1.0, 1.0]:
				_gbox(head, "Head", Vector3(0.035, 0.085, 0.085), Vector3(s * 0.112, 1.665, 0.0), _gear_mat("poly", Color(0.12, 0.12, 0.12)), Vector3.ZERO, 0.012)
		else:
			for s in [-1.0, 1.0]:
				_gbox(head, "Head", Vector3(0.03, 0.07, 0.07), Vector3(s * 0.105, 1.66, 0.0), _gear_mat("poly", Color(0.15, 0.15, 0.13)), Vector3.ZERO, 0.01)
	elif helm == "cap":
		_gbox(head, "Head", Vector3(0.2, 0.07, 0.22), Vector3(0, 1.785, -0.005), _gear_mat("fabric", alt.darkened(0.3)), Vector3.ZERO, 0.03)
		_gbox(head, "Head", Vector3(0.17, 0.012, 0.09), Vector3(0, 1.76, 0.13), _gear_mat("fabric", alt.darkened(0.3)), Vector3(-10, 0, 0), 0.005)
		# balaclava / shemagh around the lower face
		_gbox(head, "Head", Vector3(0.19, 0.08, 0.2), Vector3(0, 1.605, 0.01), _gear_mat("fabric", Color(0.12, 0.12, 0.12)), Vector3.ZERO, 0.03)
	# --- plate carrier (chest front ~z=+0.12, back ~z=-0.16 at y 1.25..1.42)
	var heavy := helm == "heavy"
	var vw := 0.36 if heavy else 0.32
	_gbox(chest, "spine_03", Vector3(vw, 0.33, 0.06), Vector3(0, 1.3, 0.13), vest, Vector3(-6, 0, 0), 0.02)
	_gbox(chest, "spine_03", Vector3(vw, 0.33, 0.06), Vector3(0, 1.3, -0.165), vest, Vector3(4, 0, 0), 0.02)
	for s in [-1.0, 1.0]:
		_gbox(chest, "spine_03", Vector3(0.05, 0.2, 0.24), Vector3(s * (vw * 0.5 - 0.005), 1.26, -0.015), vest_dark, Vector3.ZERO, 0.015)  # cummerbund
		_gbox(chest, "spine_03", Vector3(0.07, 0.03, 0.3), Vector3(s * 0.1, 1.47, -0.02), vest_dark, Vector3.ZERO, 0.012)   # shoulder straps
	if g.get("pouches", true):
		for i in 3:
			_gbox(chest, "spine_03", Vector3(0.075, 0.11, 0.05), Vector3((i - 1) * 0.085, 1.19, 0.175), vest_dark, Vector3(-4, 0, 0), 0.012)
		_gbox(chest, "spine_03", Vector3(0.1, 0.08, 0.04), Vector3(0.08, 1.37, 0.17), vest_dark, Vector3(-6, 0, 0), 0.01)  # radio/admin pouch
	if heavy:
		_gbox(chest, "spine_03", Vector3(0.42, 0.1, 0.34), Vector3(0, 1.49, -0.02), vest_dark, Vector3.ZERO, 0.04)   # collar
		for s in [-1.0, 1.0]:
			_gbox(chest, "spine_03", Vector3(0.1, 0.07, 0.17), Vector3(s * 0.2, 1.46, -0.02), vest, Vector3(0, 0, s * 18), 0.03)  # shoulder pads
		_gbox(hips, "pelvis", Vector3(0.24, 0.16, 0.05), Vector3(0, 0.95, 0.14), vest, Vector3(8, 0, 0), 0.02)  # groin plate
	if g.get("backpack", false):
		_gbox(chest, "spine_03", Vector3(0.28, 0.34, 0.14), Vector3(0, 1.26, -0.26), _gear_mat("fabric", alt), Vector3(4, 0, 0), 0.04)
		_gbox(chest, "spine_03", Vector3(0.05, 0.18, 0.04), Vector3(0.1, 1.44, -0.3), _gear_mat("metal", Color(0.12, 0.12, 0.12)), Vector3.ZERO, 0.01)  # radio
	# belt + drop pouch
	_gbox(hips, "pelvis", Vector3(0.36, 0.06, 0.25), Vector3(0, 1.04, -0.02), _gear_mat("fabric", Color(0.15, 0.14, 0.12)), Vector3.ZERO, 0.02)
	_gbox(hips, "pelvis", Vector3(0.06, 0.11, 0.1), Vector3(0.19, 0.97, -0.05), vest_dark, Vector3.ZERO, 0.015)
	# knee pads
	for s in ["l", "r"]:
		var sx := 1.0 if s == "l" else -1.0
		var knee := _attach("calf_" + s)
		_gbox(knee, "calf_" + s, Vector3(0.1, 0.11, 0.05), Vector3(sx * 0.114, 0.53, 0.06), _gear_mat("poly", Color(0.14, 0.14, 0.13)), Vector3.ZERO, 0.02)


func _build_rifle() -> void:
	var wid: String = arch.get("weapon_model", "ar")
	rifle = WeaponModels.build(wid, true)
	rifle.name = "Rifle"
	var sc: float = arch.get("weapon_scale", 1.0)
	var grip: Node3D = rifle.get_node_or_null("GripR")
	var grip_local: Vector3 = grip.position if grip else Vector3(0, -0.058, 0.07)
	# desired rifle transform in model space for the neutral aim pose: barrel along +Z (model front), level
	var h := HAND_R_AIM
	var fist := h.origin + h.basis.y * 0.075 - h.basis.x * 0.018
	var rb := Basis(Vector3.UP, PI).scaled(Vector3.ONE * sc)
	var r := Transform3D(rb, fist - rb * grip_local)
	var ba := _attach("hand_r")
	ba.add_child(rifle)
	rifle.transform = h.affine_inverse() * r
	muzzle = rifle.get_node_or_null("Muzzle")
	if muzzle == null:
		muzzle = rifle
	if arch.get("drum", false):
		MeshKit.box(rifle, Vector3(0.07, 0.1, 0.1), _gear_mat("poly", Color(0.1, 0.1, 0.1)), Vector3(0, -0.09, -0.04), Vector3.ZERO, 0.02)
	for mi in rifle.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_left_ik() -> void:
	if not ClassDB.class_exists("TwoBoneIK3D"):
		return
	var target := Marker3D.new()
	target.name = "LeftHandTarget"
	rifle.add_child(target)
	var gl: Node3D = rifle.get_node_or_null("GripL")
	# left hand on the handguard just ahead of the magwell (arm length limits how far forward it can reach)
	target.position = Vector3(0.0, -0.01, -0.13) if gl == null else Vector3(gl.position.x, gl.position.y - 0.01, lerpf(gl.position.z, -0.05, 0.6))
	var pole := Marker3D.new()
	pole.name = "LeftElbowPole"
	model.add_child(pole)
	pole.position = Vector3(0.55, 0.9, 0.2)
	ik = ClassDB.instantiate("TwoBoneIK3D")
	ik.name = "LeftHandIK"
	skeleton.add_child(ik)
	ik.set("setting_count", 1)
	ik.call("set_root_bone_name", 0, "upperarm_l")
	ik.call("set_middle_bone_name", 0, "lowerarm_l")
	ik.call("set_end_bone_name", 0, "hand_l")
	ik.call("set_target_node", 0, ik.get_path_to(target))
	ik.call("set_pole_node", 0, ik.get_path_to(pole))
	ik.influence = 0.9


func _build_hitboxes() -> void:
	# [bone, zone, shape, size, offset along bone]
	var defs := [
		["Head", "head", "sphere", Vector3(0.135, 0, 0), Vector3(0, 0.095, 0.02)],
		["neck_01", "body", "capsule", Vector3(0.07, 0.14, 0), Vector3(0, 0.05, 0.0)],
		["spine_03", "body", "box", Vector3(0.38, 0.28, 0.3), Vector3(0, 0.09, -0.01)],
		["spine_02", "body", "box", Vector3(0.32, 0.16, 0.25), Vector3(0, 0.06, 0.0)],
		["pelvis", "body", "box", Vector3(0.36, 0.2, 0.25), Vector3(0, 0.04, 0.0)],
		["upperarm_l", "limb", "capsule", Vector3(0.06, 0.3, 0), Vector3(0, 0.125, 0)],
		["upperarm_r", "limb", "capsule", Vector3(0.06, 0.3, 0), Vector3(0, 0.125, 0)],
		["lowerarm_l", "limb", "capsule", Vector3(0.05, 0.3, 0), Vector3(0, 0.12, 0)],
		["lowerarm_r", "limb", "capsule", Vector3(0.05, 0.3, 0), Vector3(0, 0.12, 0)],
		["thigh_l", "limb", "capsule", Vector3(0.09, 0.47, 0), Vector3(0, 0.21, 0)],
		["thigh_r", "limb", "capsule", Vector3(0.09, 0.47, 0), Vector3(0, 0.21, 0)],
		["calf_l", "limb", "capsule", Vector3(0.07, 0.48, 0), Vector3(0, 0.22, 0)],
		["calf_r", "limb", "capsule", Vector3(0.07, 0.48, 0), Vector3(0, 0.22, 0)],
	]
	for d in defs:
		var ba := skeleton.get_node_or_null("BA_" + d[0])
		if ba == null:
			ba = _attach(d[0])
		var area := Area3D.new()
		area.name = "HB_" + d[0]
		area.collision_layer = Game.L_HITBOX
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("hitbox", true)
		area.set_meta("enemy", enemy)
		area.set_meta("zone", d[1])
		area.set_meta("bone", d[0])
		var cs := CollisionShape3D.new()
		var sz: Vector3 = d[3]
		match d[2]:
			"sphere":
				var s := SphereShape3D.new()
				s.radius = sz.x
				cs.shape = s
			"box":
				var b := BoxShape3D.new()
				b.size = sz
				cs.shape = b
			_:
				var c := CapsuleShape3D.new()
				c.radius = sz.x
				c.height = sz.y
				cs.shape = c
		cs.position = d[4]
		area.add_child(cs)
		ba.add_child(area)
		hitboxes.append(area)


# ------------------------------------------------------------------ per-frame
## vel_local: velocity in the enemy's facing frame (x = left, z = forward). aim 0..1, pitch radians (+up).
func update_rig(delta: float, vel_local: Vector3, crouch: bool, sprint: bool, aim: float, pitch: float) -> void:
	if ragdolled:
		return
	var spd := Vector2(vel_local.x, vel_local.z).length()
	var move_ang := atan2(vel_local.x, vel_local.z)   # 0 = forward, + = towards model left
	var target_leg := 0.0
	var reverse := false
	if spd > 0.3:
		if absf(move_ang) <= deg_to_rad(110.0):
			target_leg = clampf(move_ang, -deg_to_rad(80.0), deg_to_rad(80.0))
		else:
			reverse = true
			target_leg = wrapf(move_ang - PI, -PI, PI)
			target_leg = clampf(target_leg, -deg_to_rad(70.0), deg_to_rad(70.0))
	_leg_yaw = lerp_angle(_leg_yaw, target_leg, clampf(delta * 8.0, 0.0, 1.0))
	model.rotation.y = _leg_yaw
	# gait selection with hysteresis + time scale matched to ground speed (no foot sliding)
	var g := _gait
	if crouch:
		g = "cwalk" if spd > 0.35 else "cidle"
	elif spd < 0.3:
		g = "idle"
	elif sprint and spd > 4.6 and not reverse:
		g = "sprint"
	elif spd > (2.6 if _gait == "jog" else 2.9):
		g = "jog"
	else:
		g = "walk"
	if reverse and g in ["jog", "sprint"]:
		g = "walk"
	if g != _gait:
		_gait = g
		tree.set("parameters/gait/transition_request", g)
	var sgn := -1.0 if reverse else 1.0
	match _gait:
		"walk": tree.set("parameters/ts_walk/scale", sgn * clampf(spd / SPEED_WALK, 0.7, 2.1))
		"jog": tree.set("parameters/ts_jog/scale", sgn * clampf(spd / SPEED_JOG, 0.75, 1.5))
		"sprint": tree.set("parameters/ts_sprint/scale", clampf(spd / SPEED_SPRINT, 0.8, 1.35))
		"cwalk": tree.set("parameters/ts_cwalk/scale", sgn * clampf(spd / SPEED_CROUCH, 0.7, 2.2))
	# upper body: low ready (-0.42 ~ muzzle 38 deg down) -> shouldered at the aim pitch
	var tgt_aim := 0.0 if sprint else aim
	_aim_amount = move_toward(_aim_amount, tgt_aim, delta * (4.0 if tgt_aim > _aim_amount else 2.5))
	_aim_pitch = lerpf(_aim_pitch, pitch, clampf(delta * 10.0, 0.0, 1.0))
	var pitch_blend := clampf(_aim_pitch / (PI * 0.5), -0.85, 0.85)
	var low := -0.42 if not sprint else -0.55
	tree.set("parameters/aim/blend_amount", lerpf(low, pitch_blend, _aim_amount))
	aim_mod.twist = -_leg_yaw * lerpf(0.55, 1.0, _aim_amount) if not sprint else -_leg_yaw
	aim_mod.tick(delta)
	# animation LOD: advance the tree every Nth frame with accumulated time
	_anim_accum += delta
	_frame += 1
	if _frame % lod_step == 0:
		tree.advance(_anim_accum)
		_anim_accum = 0.0


func aim_is_ready() -> bool:
	return _aim_amount > 0.85


func fire_fx(scale := 0.9) -> void:
	aim_mod.kick(arch.get("kick", 1.0))
	if muzzle and muzzle.is_inside_tree():
		FX.muzzle_flash(muzzle, scale, arch.get("suppressed", false))


func muzzle_pos() -> Vector3:
	return muzzle.global_position if muzzle and muzzle.is_inside_tree() else global_position + Vector3.UP * 1.4


## Post-modifier bone positions come from the BoneAttachment3D nodes (Skeleton3D.get_bone_global_pose() returns the
## pre-modifier pose outside the modification pass).
func head_pos() -> Vector3:
	if _ba_head and _ba_head.is_inside_tree():
		return _ba_head.global_transform * Vector3(0, 0.09, 0.02)
	return global_position + Vector3.UP * 1.7


func chest_pos() -> Vector3:
	if _ba_chest and _ba_chest.is_inside_tree():
		return _ba_chest.global_transform * Vector3(0, 0.12, 0.0)
	return global_position + Vector3.UP * 1.35


func flinch(zone: String, dir_world: Vector3, big: bool) -> void:
	if ragdolled:
		return
	var local := global_basis.inverse() * dir_world
	aim_mod.hit_flinch(local, 1.6 if big else 1.0)
	if big:
		tree.set("parameters/stagger/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif zone == "head":
		tree.set("parameters/flinch_head/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif randf() < 0.6:
		tree.set("parameters/flinch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func play_reload() -> void:
	tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func play_throw() -> void:
	tree.set("parameters/throw/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func set_hitboxes_enabled(on: bool) -> void:
	for h in hitboxes:
		h.collision_layer = Game.L_HITBOX if on else 0


# ------------------------------------------------------------------ death
func die(dir: Vector3, hit_bone: String, force: float, body_vel: Vector3, use_ragdoll := true) -> void:
	set_hitboxes_enabled(false)
	if use_ragdoll:
		# settle the rig's final animated pose first, then hand over to physics
		aim_mod.active = false
		if ik:
			ik.active = false
		tree.active = false
		ragdoll = Ragdoll.build(skeleton)
		ragdolled = true
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		ragdoll.physical_bones_start_simulation()
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		var hit_pb: PhysicalBone3D = null
		for pb in ragdoll.get_children():
			if pb is PhysicalBone3D:
				pb.linear_velocity = body_vel + dir * 0.6
				if pb.bone_name == hit_bone:
					hit_pb = pb
		if hit_pb == null:
			hit_pb = ragdoll.get_node_or_null("PB_spine_03")
		if hit_pb:
			hit_pb.apply_central_impulse(dir * force)
		var pel: PhysicalBone3D = ragdoll.get_node_or_null("PB_pelvis")
		if pel:
			pel.apply_central_impulse(dir * force * 0.9)
	else:
		tree.set("parameters/life/transition_request", "dead")


## Called by the enemy when the corpse should disappear: let the ragdoll sink through the floor.
## Debug: joint bend check (reads the post-modifier pose through the bone attachments). For knees/elbows the
## child segment must bend towards the parent bone's local +Z (knees: backwards, elbows: forwards).
func debug_bends() -> Dictionary:
	var out := {}
	for pair in [["thigh_l", "calf_l"], ["thigh_r", "calf_r"], ["upperarm_l", "lowerarm_l"], ["upperarm_r", "lowerarm_r"]]:
		var a: Node3D = skeleton.get_node_or_null("BA_" + pair[0])
		var b: Node3D = skeleton.get_node_or_null("BA_" + pair[1])
		if a and b:
			var dir := b.global_basis.y.normalized()
			out[pair[1]] = snappedf((a.global_basis.orthonormalized().inverse() * dir).z, 0.01)
	var pel: Node3D = skeleton.get_node_or_null("BA_pelvis")
	if pel:
		out["pelvis_y"] = snappedf(pel.global_position.y, 0.01)
	out["head_y"] = snappedf(head_pos().y, 0.01)
	if ragdoll:
		out["sim"] = ragdoll.is_simulating_physics()
	return out


func sink() -> void:
	if ragdoll:
		for pb in ragdoll.get_children():
			if pb is PhysicalBone3D:
				pb.collision_mask = 0
				pb.linear_damp = 6.0
				pb.gravity_scale = 0.25
				pb.apply_central_impulse(Vector3.DOWN * 0.01)
