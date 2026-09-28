extends CharacterBody3D
## Enemy soldier: perception (vision cone + hearing + shared squad knowledge), tactical state machine
## (hunt / investigate / combat{cover, peek, move, strafe, flank, assault, suppress, push, retreat, throw}),
## NavigationAgent3D movement, fair probabilistic hitscan shooting, reactions, ragdoll death, ammo drops.
##
## Facing convention: the soldier model faces +Z; `facing_yaw` = atan2(dir.x, dir.z) and rotation.y = facing_yaw.

const Cfg := preload("res://scripts/ai/ai_config.gd")
const Rig := preload("res://scripts/ai/soldier_rig.gd")
const Pickup := preload("res://scripts/ai/ammo_pickup.gd")
const Grenade := preload("res://scripts/ai/grenade.gd")
const CoverFinder := preload("res://scripts/ai/cover_finder.gd")

signal died(enemy: Node)

var arch_id := "rifleman"
var arch: Dictionary
var hp := 100.0
var max_hp := 100.0
var alive := true
var director: Node
var player: Node3D
var level: Node

var rig: Rig
var agent: NavigationAgent3D
var col: CollisionShape3D

# --- state
var state := "idle"          # idle, hunt, investigate, combat, dead
var mode := ""               # combat sub-mode
var mode_t := 0.0            # time spent in current mode
var mode_dur := 0.0
var _t := 0.0
var _think_t := 0.0
var _perc_t := 0.0

# --- knowledge
var awareness := 0.0
var has_los := false
var los_since := -100.0
var lost_los_t := -100.0
var last_seen_pos := Vector3.ZERO
var last_seen_t := -100.0
var knows_pos := false
var investigate_pos := Vector3.ZERO
var reaction_until := 0.0
var acquire_t := 0.0

# --- movement
var move_target := Vector3.ZERO
var moving := false
var speed_mode := "run"      # walk, run, sprint
var crouch := false
var facing_yaw := 0.0
var _safe_vel := Vector3.ZERO
var _desired_vel := Vector3.ZERO
var _last_agent_target := Vector3(INF, INF, INF)
var _stuck_t := 0.0
var _step_dist := 0.0
var face_override := Vector3.INF

# --- shooting
var burst_left := 0
var next_shot_t := 0.0
var burst_pause_until := 0.0
var mag_left := 30
var reloading_until := 0.0
var throwing_until := 0.0
var shots := 0
var suppress_target := Vector3.ZERO
var suppressing := false
var flinch_until := 0.0
var _ping_t := 0.0
var grenades := 0
var _reload_pending := false
var _throw_at := -1.0
var _throw_target := Vector3.ZERO

# --- cover
var cover: Dictionary = {}   # {"pos", "peek", "stand"}
var peeks_left := 2
var retreated := false
var _dmg_window := 0.0
var _dmg_window_t := 0.0
var _last_attacker_pos := Vector3.ZERO

# --- death
var death_t := 0.0
var _sunk := false
var stats := {"shots": 0, "hits": 0, "damage_dealt": 0.0}


# ================================================================== setup
func setup(p_arch: String, p_director: Node, p_player: Node3D, p_level: Node, variant := -1) -> void:
	arch_id = p_arch
	arch = Cfg.ARCHETYPES.get(p_arch, Cfg.ARCHETYPES.rifleman)
	director = p_director
	player = p_player
	level = p_level
	max_hp = arch.hp
	hp = max_hp
	mag_left = arch.mag
	grenades = arch.get("grenades", 0)
	peeks_left = randi_range(arch.peeks_before_move[0], arch.peeks_before_move[1])
	if variant < 0:
		variant = randi()
	name = "%s_%d" % [arch.name.capitalize(), get_instance_id() % 10000]
	_build(variant)


func _build(variant: int) -> void:
	add_to_group("enemy")
	collision_layer = Game.L_ENEMY
	collision_mask = Game.L_WORLD | Game.L_PROPS | Game.L_PLAYER | Game.L_ENEMY
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	safe_margin = 0.02
	col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	rig = Rig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build(arch, variant, self)
	agent = NavigationAgent3D.new()
	agent.name = "Nav"
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.6
	agent.path_max_distance = 3.0
	agent.avoidance_enabled = true
	agent.radius = 0.45
	agent.height = 1.8
	agent.neighbor_distance = 6.0
	agent.max_neighbors = 6
	agent.time_horizon_agents = 1.0
	agent.max_speed = 7.0
	agent.avoidance_layers = 1
	agent.avoidance_mask = 1
	add_child(agent)
	agent.velocity_computed.connect(func(v: Vector3): _safe_vel = v)
	_think_t = randf() * Cfg.THINK_INTERVAL
	_perc_t = randf() * Cfg.PERCEPTION_INTERVAL


# ================================================================== public API
func aim_point() -> Vector3:
	# upper chest / neck
	if rig:
		return rig.chest_pos().lerp(rig.head_pos(), 0.35)
	return global_position + Vector3.UP * 1.45


func hear_noise(pos: Vector3, radius: float) -> void:
	if not alive:
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	var k := 1.0 - d / radius
	if radius >= 30.0:
		# gunfire
		awareness = minf(1.0, awareness + 0.45 + 0.6 * k)
		if state != "combat":
			if d < radius * 0.45 or awareness >= 1.0:
				_learn_position(pos, 1.5)
				_enter_combat()
			else:
				_investigate(pos + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
		elif not has_los:
			last_seen_pos = pos
			last_seen_t = maxf(last_seen_t, _t - 0.6)
	else:
		awareness = minf(1.0, awareness + 0.25 * k + 0.05)
		if state in ["idle", "hunt"]:
			_investigate(pos)
			face_override = pos


## Squad-mate spotted the player.
func share_contact(pos: Vector3) -> void:
	if not alive:
		return
	if state != "combat":
		awareness = maxf(awareness, 1.0)
		_learn_position(pos, 0.8)
		_enter_combat()
	elif not has_los and _t - last_seen_t > 1.0:
		last_seen_pos = pos
		last_seen_t = _t - 0.8


## Director: wave spawns already know roughly where the player is.
func hunt(pos: Vector3) -> void:
	state = "hunt"
	knows_pos = true
	investigate_pos = pos
	awareness = maxf(awareness, 0.5)
	_go(pos, "run")


func take_damage(amount: float, info: Dictionary) -> Dictionary:
	var zone: String = info.get("zone", "body")
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	if not alive:
		return {"killed": false}
	var armor := false
	if zone == "head":
		if arch_id == "heavy":
			amount *= 2.0
		else:
			amount = maxf(amount, hp + 1.0)   # headshots are instant kills on light infantry
	elif zone == "body" and arch.body_armor < 1.0:
		amount *= arch.body_armor
		armor = true
	hp -= amount
	var att = info.get("attacker")
	if att and is_instance_valid(att):
		_last_attacker_pos = (att as Node3D).global_position
		awareness = 1.0
		if state != "combat":
			_learn_position(_last_attacker_pos, 0.5)
			_enter_combat()
		elif not has_los:
			last_seen_pos = _last_attacker_pos
			last_seen_t = _t
	if hp <= 0.0:
		_die(info, amount)
		return {"killed": true, "headshot": zone == "head", "armor": armor}
	# reactions
	if _t - _dmg_window_t > 0.12:
		_dmg_window = 0.0
	_dmg_window_t = _t
	_dmg_window += amount
	var big: bool = _dmg_window >= 45.0 and randf() > float(arch.stagger_resist)
	rig.flinch(zone, dir, big)
	flinch_until = _t + (0.6 if big else 0.3)
	next_shot_t = maxf(next_shot_t, _t + (0.45 if big else 0.18))
	Audio.play3d("cloth", global_position + Vector3.UP, -8.0, 0.1, 4.0, 30.0)
	# get out of the open
	if state == "combat" and mode in ["strafe", "peek"] and randf() < 0.35:
		_set_mode("reposition")
	return {"killed": false, "headshot": zone == "head", "armor": armor}


# ================================================================== main loop
## Debug/showcase pose: "", "aim", "low", "walk", "jog", "sprint", "crouch", "strafe", "back".
var debug_pose := ""


func _debug_pose_tick(delta: float) -> void:
	var pl := Game.player as Node3D
	if pl:
		var d := pl.global_position - global_position
		facing_yaw = atan2(d.x, d.z)
		rotation.y = facing_yaw
	var v := Vector3.ZERO
	var aim := 1.0
	var cr := false
	var sp := false
	match debug_pose:
		"low": aim = 0.0
		"walk": v = Vector3(0, 0, 2.0)
		"jog": v = Vector3(0, 0, 4.5)
		"sprint": v = Vector3(0, 0, 5.5); sp = true; aim = 0.0
		"crouch": cr = true
		"strafe": v = Vector3(2.0, 0, 0)
		"back": v = Vector3(0, 0, -2.0)
	var pitch := 0.0
	if pl:
		var dd := pl.global_position + Vector3.UP * 1.5 - (global_position + Vector3.UP * 1.45)
		pitch = atan2(dd.y, Vector2(dd.x, dd.z).length())
	rig.update_rig(delta, v, cr, sp, aim, pitch)


func _physics_process(delta: float) -> void:
	_t += delta
	if not alive:
		_update_dead(delta)
		return
	if debug_pose != "":
		_debug_pose_tick(delta)
		return
	if player == null or not is_instance_valid(player):
		player = Game.player as Node3D
		if player == null:
			return
	_perc_t -= delta
	if _perc_t <= 0.0:
		_perc_t += Cfg.PERCEPTION_INTERVAL
		_perceive(Cfg.PERCEPTION_INTERVAL)
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t += Cfg.THINK_INTERVAL
		_think()
	mode_t += delta
	_update_timers()
	_move(delta)
	_update_facing(delta)
	_update_fire(delta)
	_update_anim(delta)


# ================================================================== perception
func eye_pos() -> Vector3:
	return global_position + Vector3.UP * (1.05 if crouch else 1.58)


func _player_points() -> Array[Vector3]:
	var p := player.global_position
	var head: Vector3 = (player.get("head") as Node3D).global_position if player.get("head") else p + Vector3.UP * 1.6
	var chest := p.lerp(head, 0.62)
	return [chest, head]


func _ray_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.L_WORLD | Game.L_PROPS)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _perceive(dt: float) -> void:
	var pts := _player_points()
	var eye := eye_pos()
	var to: Vector3 = pts[0] - eye
	var d := to.length()
	var visible := false
	var alive_player: bool = player.get("alive") != false
	if d < Cfg.VIEW_DIST and alive_player:
		var fwd := Vector3(sin(facing_yaw), 0, cos(facing_yaw))
		var flat := Vector3(to.x, 0, to.z).normalized()
		var ang := rad_to_deg(fwd.angle_to(flat))
		var in_cone := ang < Cfg.VIEW_HALF_ANGLE
		var peripheral := ang < Cfg.PERIPHERAL_HALF_ANGLE
		if in_cone or peripheral or d < 5.0 or state == "combat":
			if _ray_clear(eye, pts[1]) or _ray_clear(eye, pts[0]):
				visible = true
				if state != "combat":
					var rate := (1.8 if in_cone else (0.45 if peripheral else 0.25))
					rate *= clampf(1.5 - d / 40.0, 0.25, 1.5)
					if player.get("crouching"):
						rate *= 0.6
					if player.get("sprinting"):
						rate *= 1.3
					if d < 6.0:
						rate *= 3.0
					awareness = minf(1.0, awareness + rate * dt)
	if visible:
		if not has_los:
			if _t - lost_los_t > 1.0:
				acquire_t = _t
				reaction_until = maxf(reaction_until, _t + randf_range(arch.reaction[0], arch.reaction[1]))
			los_since = _t
		has_los = true
		if awareness >= 1.0 or state == "combat":
			last_seen_pos = player.global_position
			last_seen_t = _t
			knows_pos = true
			if state != "combat":
				_enter_combat()
			if director and director.has_method("report_contact"):
				director.report_contact(self, last_seen_pos)
		elif awareness > 0.4 and state in ["idle", "hunt"]:
			face_override = player.global_position
	else:
		if has_los:
			lost_los_t = _t
		has_los = false
		if state != "combat":
			awareness = maxf(0.0, awareness - 0.08 * dt)


func _learn_position(pos: Vector3, noise: float) -> void:
	last_seen_pos = pos + Vector3(randf_range(-noise, noise), 0, randf_range(-noise, noise))
	last_seen_t = _t
	knows_pos = true


# ================================================================== decision making
func _set_mode(m: String, dur := 0.0) -> void:
	mode = m
	mode_t = 0.0
	mode_dur = dur


func _enter_combat() -> void:
	if state == "combat":
		return
	state = "combat"
	awareness = 1.0
	face_override = Vector3.INF
	if not has_los:
		acquire_t = _t
	reaction_until = maxf(reaction_until, _t + randf_range(arch.reaction[0], arch.reaction[1]))
	if arch.flank:
		_set_mode("flank")
		_plan_flank()
	else:
		_set_mode("reposition")


func _investigate(pos: Vector3) -> void:
	state = "investigate"
	investigate_pos = pos
	mode_t = 0.0
	_go(pos, "run" if awareness > 0.5 else "walk")


func _think() -> void:
	match state:
		"idle":
			moving = false
			if awareness >= 1.0:
				_enter_combat()
		"hunt":
			if not moving or global_position.distance_to(investigate_pos) < 3.0:
				# arrived at the rumoured position: search around it
				_investigate(investigate_pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)))
			elif director and director.has_method("player_hint") and mode_t > 4.0:
				mode_t = 0.0
				investigate_pos = director.player_hint(self)
				_go(investigate_pos, "run")
		"investigate":
			if global_position.distance_to(investigate_pos) < 1.5 or not moving:
				moving = false
				if mode_t > 3.0:
					if director and director.has_method("player_hint"):
						hunt(director.player_hint(self))
					else:
						state = "idle"
		"combat":
			_think_combat()


func _dist_to_player() -> float:
	return global_position.distance_to(player.global_position)


func _think_combat() -> void:
	var d := _dist_to_player()
	var since_seen := _t - last_seen_t
	var reloading := _t < reloading_until
	suppressing = false
	# low health: fall back (riflemen)
	if arch_id == "rifleman" and not retreated and hp < max_hp * 0.3 and mode not in ["retreat", "throw"]:
		retreated = true
		var c := CoverFinder.find(self, true)
		if not c.is_empty():
			cover = c
			_set_mode("retreat")
			_go(c.pos, "sprint")
			return
	# player hidden for a while: grenade / suppress / push
	if not has_los and since_seen > 2.2 and mode not in ["throw", "move", "retreat", "flank", "push"]:
		var gd := global_position.distance_to(last_seen_pos)
		if grenades > 0 and gd > 7.0 and gd < 26.0 and since_seen < 9.0 and director and director.can_throw_grenade():
			_start_throw()
			return
		if since_seen < 4.5 and (arch_id == "heavy" or randf() < 0.3) and mode != "suppress" and _ray_clear(eye_pos(), last_seen_pos + Vector3.UP * 1.0):
			_set_mode("suppress", randf_range(1.5, 2.6))
			moving = false
			return
		if since_seen > 4.0 or mode == "suppress" and mode_t > mode_dur:
			_set_mode("push")
			_go(_push_target(), "run")
			return
	match mode:
		"reposition":
			if arch_id == "heavy" and randf() < 0.6:
				_set_mode("advance", randf_range(3.0, 5.0))
				return
			var c := CoverFinder.find(self, false)
			if not c.is_empty():
				cover = c
				_set_mode("move")
				_go(c.pos, "run" if global_position.distance_to(c.pos) < 14.0 else "sprint")
			else:
				_set_mode("strafe", randf_range(2.5, 4.5))
				_pick_strafe_point()
		"move", "retreat":
			if cover.is_empty():
				_set_mode("reposition")
			elif global_position.distance_to(cover.pos) < 0.8 or (not moving and mode_t > 0.5):
				_set_mode("cover", randf_range(0.8, 1.8) if mode == "move" else randf_range(2.5, 4.0))
				moving = false
			elif mode_t > 9.0:
				_set_mode("reposition")
		"cover":
			moving = false
			crouch = true
			if _cover_compromised(d):
				_set_mode("reposition")
				return
			if mode_t > mode_dur and not reloading:
				_set_mode("peek", randf_range(1.6, 3.0))
				if cover.get("peek", cover.pos).distance_to(cover.pos) > 0.3:
					_go(cover.peek, "walk")
		"peek":
			crouch = false
			if cover.is_empty():
				_set_mode("reposition")
				return
			if mag_left <= 0 or (mode_t > mode_dur and burst_left <= 0):
				peeks_left -= 1
				if peeks_left <= 0 or d < 6.0:
					peeks_left = randi_range(arch.peeks_before_move[0], arch.peeks_before_move[1])
					_set_mode("reposition")
				else:
					_set_mode("cover", randf_range(1.0, 2.2))
					_go(cover.pos, "walk")
				if mag_left <= 0:
					_start_reload()
			elif mode_t > 1.2 and not has_los and since_seen > 1.2:
				# nothing to shoot from here
				_set_mode("reposition")
		"strafe":
			crouch = false
			if not moving or mode_t > mode_dur:
				if mode_t > mode_dur:
					_set_mode("reposition")
				else:
					_pick_strafe_point()
		"advance":
			crouch = false
			var pref: Array = arch.range_pref
			if d > pref[0] * 1.2:
				_go(player.global_position, "walk")
			else:
				moving = false
			if mode_t > mode_dur:
				_set_mode("strafe" if randf() < 0.5 else "reposition", randf_range(2.0, 3.5))
				if mode == "strafe":
					_pick_strafe_point()
		"flank":
			crouch = false
			if not moving or mode_t > 7.0 or (has_los and d < 12.0 and mode_t > 1.5):
				_set_mode("assault", randf_range(3.5, 6.0))
		"assault":
			crouch = false
			var pref: Array = arch.range_pref
			if d > pref[1] or not has_los:
				_go(player.global_position, "run")
			elif d > pref[0]:
				var side := Vector3(sin(facing_yaw + PI * 0.5), 0, cos(facing_yaw + PI * 0.5)) * (1.0 if (get_instance_id() & 1) == 0 else -1.0)
				_go(player.global_position + side * 3.0, "walk")
			else:
				_pick_strafe_point(3.0)
			if mode_t > mode_dur:
				_set_mode("flank")
				_plan_flank()
		"suppress":
			moving = false
			if since_seen < 6.0:
				suppressing = true
				suppress_target = last_seen_pos + Vector3.UP * randf_range(0.6, 1.4)
			if has_los or mode_t > mode_dur:
				_set_mode("reposition" if not arch.flank else "flank")
				if arch.flank:
					_plan_flank()
		"push":
			crouch = false
			if has_los:
				_set_mode("strafe" if randf() < 0.5 else "reposition", randf_range(1.5, 3.0))
				if mode == "strafe":
					_pick_strafe_point()
			elif not moving or mode_t > 6.0:
				_go(_push_target(), "run")
				mode_t = 0.0
		"throw":
			moving = false
			if _t > throwing_until:
				_set_mode("reposition")
		_:
			_set_mode("reposition")
	if mag_left <= 0 and not reloading and mode not in ["throw"]:
		_start_reload()


func _cover_compromised(d: float) -> bool:
	# flanked: the player can see our crouched position (low ray clear) and is close enough to matter
	if d > 35.0:
		return false
	var low := global_position + Vector3.UP * 0.95
	var pts := _player_points()
	return has_los and _ray_clear(low, pts[0]) and d < 22.0 and mode_t > 0.6


func _push_target() -> Vector3:
	var base := last_seen_pos if knows_pos else player.global_position
	var off := Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	return base + off


func _pick_strafe_point(radius := 4.5) -> void:
	var to_p := (player.global_position - global_position)
	to_p.y = 0
	var dist := to_p.length()
	to_p = to_p.normalized() if dist > 0.01 else Vector3.FORWARD
	var side := Vector3(-to_p.z, 0, to_p.x) * (1.0 if randf() < 0.5 else -1.0)
	var pref: Array = arch.range_pref
	var radial := 0.0
	if dist < pref[0]:
		radial = -2.0
	elif dist > pref[1]:
		radial = 2.5
	var tgt := global_position + side * randf_range(radius * 0.6, radius) + to_p * radial
	_go(tgt, "walk")


func _plan_flank() -> void:
	var p := player.global_position
	var from_p := global_position - p
	from_p.y = 0
	var base_ang := atan2(from_p.x, from_p.z)
	var sgn := 1.0 if randf() < 0.5 else -1.0
	var ang := base_ang + sgn * deg_to_rad(randf_range(70.0, 110.0))
	var r := randf_range(7.0, 11.0)
	var tgt := p + Vector3(sin(ang), 0, cos(ang)) * r
	_go(tgt, "sprint")


func _start_reload() -> void:
	if _t < reloading_until:
		return
	reloading_until = _t + arch.reload
	burst_left = 0
	rig.play_reload()
	Audio.play3d("mag_out", global_position + Vector3.UP * 1.3, -6.0, 0.05, 4.0, 35.0)
	_reload_pending = true


func _start_throw() -> void:
	grenades -= 1
	_set_mode("throw")
	moving = false
	throwing_until = _t + 1.3
	director.note_grenade()
	rig.play_throw()
	var tgt := last_seen_pos + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	face_override = tgt
	_throw_at = _t + 0.55
	_throw_target = tgt
	Audio.play3d("grenade_pin", global_position + Vector3.UP * 1.5, -6.0, 0.05, 4.0, 30.0)


func _update_timers() -> void:
	if _reload_pending and _t >= reloading_until - arch.reload * 0.15:
		_reload_pending = false
		mag_left = arch.mag
		Audio.play3d("mag_in", global_position + Vector3.UP * 1.3, -6.0, 0.05, 4.0, 35.0)
	if _throw_at > 0.0 and _t >= _throw_at:
		_throw_at = -1.0
		var g := Grenade.new()
		(director if director else get_parent()).add_child(g)
		var hand := global_position + Vector3.UP * 1.75 + Vector3(sin(facing_yaw), 0, cos(facing_yaw)) * 0.3
		g.launch(hand, _throw_target, self)


# ================================================================== movement
func _go(pos: Vector3, spd := "run") -> void:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		pos = NavigationServer3D.map_get_closest_point(map, pos)
	move_target = pos
	speed_mode = spd
	moving = true
	_stuck_t = 0.0
	if pos.distance_to(_last_agent_target) > 0.4:
		_last_agent_target = pos
		agent.target_position = pos


func _speed() -> float:
	var s: float = arch.get(speed_mode, arch.run)
	if crouch:
		s = minf(s, 1.3)
	if _t < flinch_until:
		s *= 0.5
	if _t < reloading_until and speed_mode == "sprint":
		s = arch.run
	return s


func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	if moving and _t > throwing_until:
		if agent.is_navigation_finished():
			moving = false
		else:
			var next := agent.get_next_path_position()
			var dir := next - global_position
			dir.y = 0
			if dir.length() > 0.05:
				desired = dir.normalized() * _speed()
			var remaining := global_position.distance_to(move_target)
			if remaining < 1.2:
				desired *= clampf(remaining / 1.2, 0.35, 1.0)
	_desired_vel = desired
	if agent.avoidance_enabled:
		agent.velocity = desired
		if desired == Vector3.ZERO:
			_safe_vel = Vector3.ZERO
	else:
		_safe_vel = desired
	var tv := _safe_vel
	tv.y = 0
	var accel := 10.0 if tv.length() > Vector2(velocity.x, velocity.z).length() else 14.0
	velocity.x = move_toward(velocity.x, tv.x, accel * delta)
	velocity.z = move_toward(velocity.z, tv.z, accel * delta)
	if not is_on_floor():
		velocity.y -= 19.0 * delta
	else:
		velocity.y = maxf(velocity.y, -0.5)
	move_and_slide()
	var hs := Vector2(velocity.x, velocity.z).length()
	# stuck detection
	if moving and desired.length() > 0.5 and hs < 0.25:
		_stuck_t += delta
		if _stuck_t > 1.4:
			_stuck_t = 0.0
			moving = false
			if state == "combat" and mode in ["move", "retreat", "push", "flank"]:
				_set_mode("reposition")
	# footsteps
	_step_dist += hs * delta
	var stride := 0.75 if hs < 3.0 else 1.25
	if _step_dist > stride:
		_step_dist = 0.0
		if player and global_position.distance_squared_to(player.global_position) < 900.0:
			Audio.play3d("footstep_concrete", global_position, -10.0 if hs < 3.0 else -5.0, 0.12, 3.0, 35.0)


func _update_facing(delta: float) -> void:
	var look := Vector3.INF
	if state == "combat":
		if suppressing:
			look = suppress_target
		elif has_los:
			look = player.global_position
		elif mode in ["flank", "push", "move", "retreat"] and Vector2(velocity.x, velocity.z).length() > 2.5:
			look = global_position + velocity
		elif knows_pos:
			look = last_seen_pos
	if face_override != Vector3.INF and (state != "combat" or mode == "throw"):
		look = face_override
	if look == Vector3.INF and Vector2(velocity.x, velocity.z).length() > 0.5:
		look = global_position + velocity
	if look != Vector3.INF:
		var d := look - global_position
		if Vector2(d.x, d.z).length() > 0.1:
			var target_yaw := atan2(d.x, d.z)
			var rate := deg_to_rad(320.0 if state == "combat" else 180.0)
			var diff := wrapf(target_yaw - facing_yaw, -PI, PI)
			facing_yaw += clampf(diff, -rate * delta, rate * delta)
			facing_yaw = wrapf(facing_yaw, -PI, PI)
	rotation.y = facing_yaw


func _yaw_error_to(p: Vector3) -> float:
	var d := p - global_position
	return absf(wrapf(atan2(d.x, d.z) - facing_yaw, -PI, PI))


# ================================================================== shooting
func _wants_fire() -> bool:
	if state != "combat" or _t < reaction_until or _t < reloading_until or _t < throwing_until:
		return false
	if speed_mode == "sprint" and moving:
		return false
	if mode in ["cover", "retreat", "flank", "throw"]:
		return false
	if mode == "move":
		return has_los and arch_id != "rusher" and Vector2(velocity.x, velocity.z).length() < 3.0
	if suppressing:
		return true
	return has_los


func _update_fire(_delta: float) -> void:
	if not _wants_fire() or not rig.aim_is_ready():
		return
	var tgt: Vector3 = suppress_target if suppressing else player.global_position
	if _yaw_error_to(tgt) > deg_to_rad(12.0):
		return
	if _t < next_shot_t or _t < burst_pause_until:
		return
	if mag_left <= 0:
		return
	if burst_left <= 0:
		burst_left = randi_range(arch.burst[0], arch.burst[1])
	_fire_shot()
	burst_left -= 1
	mag_left -= 1
	next_shot_t = _t + 60.0 / arch.rpm * randf_range(0.95, 1.08)
	if burst_left <= 0:
		burst_pause_until = _t + randf_range(arch.burst_pause[0], arch.burst_pause[1])


func hit_chance() -> float:
	var d := _dist_to_player()
	var rf: float
	if arch_id == "rusher":
		rf = clampf(1.15 - d / 30.0, 0.2, 1.0)
	else:
		rf = clampf(1.1 - d / 60.0, 0.3, 1.0)
	var pv: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	var ps := Vector2(pv.x, pv.z).length()
	var mf := 1.0 - clampf((ps - 1.0) / 9.0, 0.0, 0.45)
	var stance := 1.0
	if player.get("sliding"):
		stance = 0.45
	elif player.get("crouching"):
		stance = 0.8
	if player.has_method("is_on_floor") and not player.is_on_floor():
		stance *= 0.7
	var ramp := lerpf(Cfg.FIRST_SHOT_ACC, 1.0, clampf((_t - acquire_t) / Cfg.ACQUIRE_RAMP, 0.0, 1.0))
	var self_move := 0.8 if Vector2(velocity.x, velocity.z).length() > 1.0 else 1.0
	var fl := 0.5 if _t < flinch_until else 1.0
	var token := 1.0
	if director and director.has_method("has_token") and not director.has_token(self):
		token = 0.4
	var mercy := 1.0
	if player.has_method("health_ratio") and player.health_ratio() < 0.35:
		mercy = 0.7
	var diff := 1.0
	var dv = Game.settings.get("difficulty", 1)
	if dv is int or dv is float:
		diff = [0.7, 1.0, 1.25][clampi(int(dv), 0, 2)]
	# input fairness: touch / gamepad players aim slower than mouse users -> enemies are slightly less accurate
	var dev := 1.0
	match Game.input_mode:
		"touch": dev = 0.78
		"pad": dev = 0.9
	return clampf(arch.accuracy * rf * mf * stance * ramp * self_move * fl * token * mercy * diff * dev, 0.0, 0.95)


func _fire_shot() -> void:
	var from := rig.muzzle_pos()
	var eye := eye_pos()
	var space := get_world_3d().direct_space_state
	var pts := _player_points()
	var tgt: Vector3
	if suppressing:
		tgt = suppress_target
	else:
		tgt = pts[0]
		if not _ray_clear(eye, pts[0]):
			tgt = pts[1]
	var end := Vector3.ZERO
	var hit_player := false
	shots += 1
	stats.shots += 1
	if not suppressing and has_los and randf() < hit_chance():
		var aim := tgt + Vector3(randf_range(-0.12, 0.12), randf_range(-0.15, 0.1), randf_range(-0.12, 0.12))
		var q := PhysicsRayQueryParameters3D.create(eye, aim, Game.L_WORLD | Game.L_PROPS)
		var r := space.intersect_ray(q)
		if r.is_empty():
			hit_player = true
			end = aim
			var dmg := randf_range(arch.damage[0], arch.damage[1])
			stats.hits += 1
			stats.damage_dealt += dmg
			player.take_damage(dmg, from)
		else:
			end = r.position
			FX.impact(r.position, r.normal, _surface(r.collider), (aim - eye).normalized())
	else:
		# near miss: offset perpendicular to the shot line, biased low so rounds kick up dirt at the player's feet
		var fwd := (tgt - from).normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var up := side.cross(fwd).normalized()
		var ang := randf() * TAU
		var rad := randf_range(0.35, 1.5) if not suppressing else randf_range(0.2, 2.2)
		var off := side * cos(ang) * rad + up * (sin(ang) * rad * 0.8 - 0.25)
		var dirn := ((tgt + off) - from).normalized()
		var max_r: float = arch.max_range + 20.0
		var q := PhysicsRayQueryParameters3D.create(from, from + dirn * max_r, Game.L_WORLD | Game.L_PROPS)
		var r := space.intersect_ray(q)
		end = from + dirn * max_r if r.is_empty() else r.position
		if not r.is_empty() and r.position.distance_squared_to(player.global_position) < 1600.0:
			FX.impact(r.position, r.normal, _surface(r.collider), dirn)
		# whiz past the head
		var head: Vector3 = pts[1]
		var seg := end - from
		var t := clampf((head - from).dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
		var closest := from + seg * t
		if t > 0.05 and t < 0.999 and closest.distance_to(head) < 2.2:
			Audio.play3d("bullet_whiz", closest, -2.0, 0.15, 3.0, 20.0)
	var te: int = arch.tracer_every
	if te <= 1 or shots % te == 0:
		FX.tracer(from, end, 0.8)
	rig.fire_fx(arch.flash_scale)
	Audio.play3d(arch.sound, from, 0.0, 0.07, 10.0, 260.0)
	if _t - _ping_t > 0.5:
		_ping_t = _t
		var hud = Game.world.get("hud") if Game.world else null
		if hud and is_instance_valid(hud) and hud.has_method("ping_enemy"):
			hud.ping_enemy(global_position)


func _surface(c: Object) -> String:
	if c and c.has_meta("surface"):
		return c.get_meta("surface")
	return "concrete"


# ================================================================== animation
func _update_anim(delta: float) -> void:
	var local_v := global_basis.inverse() * velocity
	var aim := 0.0
	var pitch := 0.0
	var look_pt := Vector3.INF
	match state:
		"combat":
			if mode == "cover":
				aim = 0.25
			elif mode in ["flank", "retreat"] or speed_mode == "sprint" and moving:
				aim = 0.0
			elif mode == "throw":
				aim = 0.2
			else:
				aim = 1.0 if (has_los or suppressing or mode in ["peek", "strafe", "advance", "assault"]) else 0.55
			look_pt = suppress_target if suppressing else (player.global_position + Vector3.UP * 1.2 if has_los else last_seen_pos + Vector3.UP * 1.2)
		"investigate":
			aim = 0.45
		_:
			aim = 0.0
	if _t < reloading_until:
		aim = minf(aim, 0.5)
	if look_pt != Vector3.INF:
		var from := global_position + Vector3.UP * (1.0 if crouch else 1.45)
		var d := look_pt - from
		pitch = atan2(d.y, Vector2(d.x, d.z).length())
	var sprint := speed_mode == "sprint" and moving and Vector2(velocity.x, velocity.z).length() > 4.0
	# animation LOD by distance to the camera
	if player:
		var dd := global_position.distance_squared_to(player.global_position)
		rig.lod_step = 1 if dd < 625.0 else (2 if dd < 2500.0 else 3)
	rig.update_rig(delta, local_v, crouch and not moving or crouch and Vector2(velocity.x, velocity.z).length() < 1.4, sprint, aim, pitch)


# ================================================================== death
func _die(info: Dictionary, amount: float) -> void:
	alive = false
	state = "dead"
	hp = 0.0
	remove_from_group("enemy")
	collision_layer = 0
	collision_mask = Game.L_WORLD
	agent.avoidance_enabled = false
	var zone: String = info.get("zone", "body")
	var dir: Vector3 = info.get("dir", -global_basis.z)
	var pos: Vector3 = info.get("pos", global_position + Vector3.UP)
	var weapon: String = str(info.get("weapon", ""))
	Game.register_kill({"name": arch.name, "weapon": weapon, "headshot": zone == "head"})
	if arch.get("score", 0) > 0:
		Game.add_score(arch.score)
	# nearest hit bone
	var bone := "spine_03"
	var best := 999.0
	for h in rig.hitboxes:
		var dd := h.global_position.distance_to(pos)
		if dd < best:
			best = dd
			bone = h.get_meta("bone")
	var force := clampf(25.0 + amount * 0.5, 30.0, 95.0)
	if "BREACHER" in weapon or "SHOTGUN" in weapon.to_upper():
		force = 140.0
	var flat := Vector3(dir.x, 0.15, dir.z).normalized()
	var use_ragdoll: bool = director.use_ragdolls if director and director.get("use_ragdolls") != null else true
	rig.die(flat, bone, force, Vector3(velocity.x, 0, velocity.z), use_ragdoll)
	Audio.play3d("enemy_death", global_position + Vector3.UP * 1.5, -2.0, 0.08, 6.0, 60.0)
	Audio.play3d("body_fall", global_position, -6.0, 0.1, 4.0, 40.0)
	velocity = Vector3.ZERO
	death_t = _t
	if randf() < arch.get("drop_chance", 0.3):
		var pk := Pickup.new()
		(director if director else get_parent()).add_child(pk)
		pk.global_position = global_position + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
	died.emit(self)


func _update_dead(delta: float) -> void:
	if not rig.ragdolled:
		rig.update_rig(delta, Vector3.ZERO, false, false, 0.0, 0.0)
		if not is_on_floor():
			velocity.y -= 19.0 * delta
			move_and_slide()
	var age := _t - death_t
	if age > Cfg.CORPSE_TIME and not _sunk:
		# wait until the player is not looking, or it has been far too long
		var cam := get_viewport().get_camera_3d()
		var seen := cam != null and cam.is_position_in_frustum(global_position + Vector3.UP * 0.4) and cam.global_position.distance_to(global_position) < 25.0
		if not seen or age > Cfg.CORPSE_TIME * 2.5:
			start_sink()
	if _sunk and _t - death_t > 0.0:
		if rig.ragdolled:
			if age > _sink_end:
				queue_free()
		else:
			rig.position.y -= delta * 0.4
			if age > _sink_end:
				queue_free()


var _sink_end := 0.0

func start_sink() -> void:
	if _sunk:
		return
	_sunk = true
	_sink_end = (_t - death_t) + 3.0
	rig.sink()
