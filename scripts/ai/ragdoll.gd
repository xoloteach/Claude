extends RefCounted
## Builds a PhysicalBoneSimulator3D ragdoll for the Quaternius soldier skeleton at death time.
## Bodies live on their own collision layer (L_RAGDOLL = bit 7, mask WORLD|PROPS) so they collide with the level
## but never with the player, other enemies or bullets (none of those masks include bit 7).

# bone, child bone (defines length/direction), radius, mass, joint type, limits
const BONES := [
	["pelvis", "spine_01", 0.13, 11.0, "root", []],
	["spine_02", "spine_03", 0.14, 9.0, "cone", [22.0, 20.0]],
	["spine_03", "neck_01", 0.15, 9.0, "cone", [22.0, 20.0]],
	["Head", "", 0.11, 4.0, "cone", [40.0, 40.0]],
	["upperarm_l", "lowerarm_l", 0.055, 2.5, "cone", [75.0, 40.0]],
	["lowerarm_l", "hand_l", 0.045, 1.6, "hinge", [0.0, 135.0]],
	["upperarm_r", "lowerarm_r", 0.055, 2.5, "cone", [75.0, 40.0]],
	["lowerarm_r", "hand_r", 0.045, 1.6, "hinge", [0.0, 135.0]],
	["thigh_l", "calf_l", 0.085, 8.0, "cone", [55.0, 25.0]],
	["calf_l", "foot_l", 0.065, 4.0, "hinge", [0.0, 140.0]],
	["thigh_r", "calf_r", 0.085, 8.0, "cone", [55.0, 25.0]],
	["calf_r", "foot_r", 0.065, 4.0, "hinge", [0.0, 140.0]],
]

## Knee/elbow hinge sign (flip if limbs bend the wrong way).
const HINGE_SIGN := 1.0
const L_RAGDOLL := 64


static func build(sk: Skeleton3D) -> PhysicalBoneSimulator3D:
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	sk.add_child(sim)
	for d in BONES:
		var bi := sk.find_bone(d[0])
		if bi < 0:
			continue
		var length := 0.22
		if d[1] != "":
			var ci := sk.find_bone(d[1])
			if ci >= 0:
				length = sk.get_bone_rest(ci).origin.length()
		var r: float = d[2]
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + d[0]
		pb.bone_name = d[0]
		pb.collision_layer = L_RAGDOLL
		pb.collision_mask = Game.L_WORLD | Game.L_PROPS
		pb.mass = d[3]
		pb.friction = 0.85
		pb.bounce = 0.0
		pb.linear_damp = 0.25
		pb.angular_damp = 2.5
		pb.can_sleep = true
		var half := length * 0.5
		# body frame = bone frame (bone local +Y points to the child), centred on the bone segment
		pb.body_offset = Transform3D(Basis.IDENTITY, Vector3(0, half, 0))
		var cs := CollisionShape3D.new()
		if d[0] == "Head":
			var sph := SphereShape3D.new()
			sph.radius = r
			cs.shape = sph
			pb.body_offset = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0.02))
		elif d[0] in ["pelvis", "spine_02", "spine_03"]:
			var bx := BoxShape3D.new()
			bx.size = Vector3(r * 2.3, maxf(length, 0.12), r * 1.5)
			cs.shape = bx
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = r
			cap.height = maxf(length + r, r * 2.1)
			cs.shape = cap
		pb.add_child(cs)
		var jt: String = d[4]
		var joint_origin := -pb.body_offset.origin   # joint at the bone head
		match jt:
			"root":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
			"cone":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
				# cone-twist: twist axis = joint X -> align with bone +Y
				pb.joint_offset = Transform3D(Basis(Vector3.BACK, PI * 0.5), joint_origin)
				pb.set("joint_constraints/swing_span", d[5][0])
				pb.set("joint_constraints/twist_span", d[5][1])
			"hinge":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
				# hinge axis = joint Z -> align with bone +X
				pb.joint_offset = Transform3D(Basis(Vector3.UP, PI * 0.5), joint_origin)
				pb.set("joint_constraints/angular_limit_enabled", true)
				var lo: float = d[5][0]
				var hi: float = d[5][1]
				if HINGE_SIGN > 0.0:
					pb.set("joint_constraints/angular_limit_lower", -hi)
					pb.set("joint_constraints/angular_limit_upper", -lo)
				else:
					pb.set("joint_constraints/angular_limit_lower", lo)
					pb.set("joint_constraints/angular_limit_upper", hi)
		sim.add_child(pb)
	return sim
