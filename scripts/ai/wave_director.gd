extends Node
## Wave survival director. Loaded by main.gd when present:
##   start(level, player), stop(), debug_spawn(n), alive_count()
## Spawns waves with a growing count / archetype mix, trickles spawns from points the player cannot see
## (>= 25 m away), caps concurrent enemies, shares contact info between squad-mates, hands out a limited number of
## "attack tokens" (only the N best-placed enemies shoot at full accuracy), and runs the between-wave break.

const Cfg := preload("res://scripts/ai/ai_config.gd")
const EnemyScript := preload("res://scripts/ai/enemy.gd")
const CoverFinder := preload("res://scripts/ai/cover_finder.gd")
const SoldierRig := preload("res://scripts/ai/soldier_rig.gd")

signal wave_started(n: int)
signal wave_cleared(n: int)

const BREAK_TIME := 9.0
const INTRO_TIME := 3.0
const MIN_SPAWN_DIST := 25.0
const MAX_ALIVE := 8
const WAVE_BONUS := 500

var level: Node
var player: Node3D
var running := false
var wave := 0
var phase := "idle"          # idle, intro, wave, break
var phase_t := 0.0
var queue: Array[String] = []
var enemies: Array[Node] = []
var corpses: Array[Node] = []
var spawn_t := 0.0
var use_ragdolls := true
var spawning := true         # debug: "ai waves off" pauses the wave flow (enemies keep fighting)
var _last_grenade_t := -100.0
var _t := 0.0
var _token_t := 0.0
var _tokens := {}            # instance id -> true
var _recent_spawns := []     # [pos, time]
var _last_contact_t := -100.0
var _last_contact_pos := Vector3.ZERO
var total_spawned := 0
var total_killed := 0


func start(p_level: Node, p_player: Node3D) -> void:
	stop()
	level = p_level
	player = p_player
	running = true
	wave = 0
	_t = 0.0
	phase = "intro"
	phase_t = INTRO_TIME
	Game.enemies_remaining.emit(0)


func stop() -> void:
	running = false
	phase = "idle"
	queue.clear()
	for e in enemies + corpses:
		_despawn(e)
	enemies.clear()
	corpses.clear()
	_tokens.clear()
	CoverFinder.claims.clear()
	for c in get_children():
		if not c.is_in_group("enemy") and not c.has_method("take_damage"):
			c.queue_free()


## Disable first, free a moment later: pooled FX (muzzle flashes parented to the rifle) finish their timers.
func _despawn(e: Node) -> void:
	if not is_instance_valid(e) or e.is_queued_for_deletion():
		return
	e.remove_from_group("enemy")
	e.process_mode = Node.PROCESS_MODE_DISABLED
	(e as Node3D).visible = false
	if e.get("rig") and e.rig.hitboxes:
		e.rig.set_hitboxes_enabled(false)
	(e as CollisionObject3D).collision_layer = 0
	get_tree().create_timer(0.2, true, false, true).timeout.connect(e.queue_free)


func _exit_tree() -> void:
	SoldierRig.clear_cache()


func alive_count() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			n += 1
	return n


func remaining() -> int:
	return alive_count() + queue.size()


## Spawn n riflemen 15-25 m in front of the player (testing). They start unaware ("idle").
func debug_spawn(n: int) -> void:
	if player == null or not is_instance_valid(player):
		player = Game.player as Node3D
		if player == null:
			return
	if level == null:
		level = Game.world.get("level") if Game.world else null
	var cam: Camera3D = player.get("camera")
	var fwd: Vector3 = -(cam.global_basis.z if cam else player.global_basis.z)
	fwd.y = 0
	fwd = fwd.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	for i in n:
		var p := player.global_position + fwd * randf_range(15.0, 25.0) + side * ((i - (n - 1) * 0.5) * 3.0 + randf_range(-1.0, 1.0))
		var e := _spawn("rifleman", _snap(p))
		if e:
			e.state = "idle"
			var d: Vector3 = player.global_position - (e as Node3D).global_position
			e.facing_yaw = atan2(d.x, d.z)
			e.rotation.y = e.facing_yaw
	Game.enemies_remaining.emit(remaining())


## Debug commands (routed from Game.run_command("ai ...") when available):
##   lineup [pose]  - one of each archetype 5 m in front of the player, frozen in a pose (aim/low/walk/jog/sprint/crouch/strafe/back)
##   pose <pose>    - change the pose of lined-up enemies ("" / "live" releases them)
##   clear          - remove all enemies
##   waves on|off   - pause/resume wave spawning
func debug_cmd(args: Array) -> void:
	if args.is_empty():
		return
	match str(args[0]):
		"lineup":
			if player == null or not is_instance_valid(player):
				player = Game.player as Node3D
			if level == null:
				level = Game.world.get("level") if Game.world else null
			var pose: String = str(args[1]) if args.size() > 1 else "aim"
			var cam: Camera3D = player.get("camera")
			var fwd: Vector3 = -(cam.global_basis.z if cam else player.global_basis.z)
			fwd.y = 0
			fwd = fwd.normalized()
			var side := Vector3(-fwd.z, 0, fwd.x)
			var dist: float = float(args[2]) if args.size() > 2 else 5.0
			var archs := ["rusher", "rifleman", "heavy"]
			for i in archs.size():
				var e := _spawn(archs[i], _snap(player.global_position + fwd * dist + side * (i - 1) * 1.5))
				e.debug_pose = pose
		"pose":
			var pose: String = str(args[1]) if args.size() > 1 else ""
			for e in enemies:
				if is_instance_valid(e) and e.alive:
					e.debug_pose = "" if pose == "live" else pose
					if pose == "live":
						e.awareness = 1.0
						e._enter_combat()
		"kill":
			# kill the nearest live enemy with a body shot from the player (death/ragdoll check)
			var best: Node3D = null
			for e in enemies:
				if is_instance_valid(e) and e.alive and (best == null or e.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
					best = e
			if best:
				var zone: String = str(args[1]) if args.size() > 1 else "body"
				var hp_pos: Vector3 = best.aim_point() if zone != "head" else best.rig.head_pos()
				var d: Vector3 = (hp_pos - player.global_position - Vector3.UP * 1.6).normalized()
				best.take_damage(500.0, {"zone": zone, "pos": hp_pos, "dir": d, "normal": -d, "weapon": "DEBUG", "attacker": player})
		"clear":
			for e in enemies + corpses:
				_despawn(e)
			enemies.clear()
			corpses.clear()
			queue.clear()
		"waves":
			spawning = args.size() < 2 or str(args[1]) != "off"


func _snap(p: Vector3) -> Vector3:
	var map: RID = get_viewport().get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var s := NavigationServer3D.map_get_closest_point(map, p)
		if s.distance_to(p) < 6.0:
			return s
	return p


func _spawn(arch: String, pos: Vector3) -> Node:
	var e: CharacterBody3D = EnemyScript.new()
	e.setup(arch, self, player, level)
	add_child(e)
	e.global_position = pos + Vector3.UP * 0.05
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	total_spawned += 1
	return e


# ------------------------------------------------------------------ waves
func _compose(n: int) -> Array[String]:
	var out: Array[String] = []
	var total: int
	var rush := 0
	var heavy := 0
	match n:
		1:
			total = 5
		2:
			total = 7
			rush = 2
		_:
			total = mini(7 + (n - 2) * 2, 26)
			heavy = 1 + int((n - 3) / 2)
			rush = int(round(total * 0.3))
	for i in total - rush - heavy:
		out.append("rifleman")
	for i in rush:
		out.append("rusher")
	out.shuffle()
	# the wave opens with riflemen (a firefight), heavies arrive mid-wave
	for i in mini(3, out.size()):
		if out[i] == "rusher":
			for j in range(3, out.size()):
				if out[j] == "rifleman":
					out[i] = "rifleman"
					out[j] = "rusher"
					break
	for i in heavy:
		out.insert(clampi(out.size() / 2 + i * 2, 0, out.size()), "heavy")
	return out


func _max_alive() -> int:
	return mini(MAX_ALIVE, 4 + wave)


func _begin_wave() -> void:
	wave += 1
	Game.set_wave(wave)
	queue = _compose(wave)
	phase = "wave"
	spawn_t = 0.5
	var sub := "Hostiles inbound" if wave == 1 else ("Rushers inbound" if wave == 2 else "Heavy armor spotted" if wave == 3 else "Enemy reinforcements")
	Game.message("WAVE %d|%s" % [wave, sub], "banner")
	Audio.play("wave_start")
	Game.enemies_remaining.emit(remaining())
	wave_started.emit(wave)


func _complete_wave() -> void:
	phase = "break"
	phase_t = BREAK_TIME
	Game.add_score(WAVE_BONUS)
	Game.message("WAVE COMPLETE|+%d" % WAVE_BONUS, "banner")
	Audio.play("wave_complete")
	if player and is_instance_valid(player):
		if player.has_method("heal_full"):
			player.heal_full()
		var w = player.get("weapons")
		if w and w.has_method("refill_all"):
			w.refill_all(1.0)
	wave_cleared.emit(wave)


func _process(delta: float) -> void:
	if not running:
		return
	_t += delta
	if player == null or not is_instance_valid(player):
		return
	match phase if spawning else "paused":
		"intro", "break":
			phase_t -= delta
			if phase_t <= 0.0:
				_begin_wave()
		"wave":
			spawn_t -= delta
			if spawn_t <= 0.0 and not queue.is_empty() and alive_count() < _max_alive():
				_spawn_next()
				spawn_t = randf_range(0.35, 0.8) if alive_count() < 3 else randf_range(1.4, 2.6)
			if queue.is_empty() and alive_count() == 0:
				_complete_wave()
	_token_t -= delta
	if _token_t <= 0.0:
		_token_t = 0.5
		_assign_tokens()
	_prune()


func _spawn_next() -> void:
	var arch: String = queue.pop_front()
	var pos := _pick_spawn()
	if pos == Vector3.INF:
		queue.push_front(arch)
		return
	var e := _spawn(arch, pos)
	if e:
		# they know roughly where the player is
		e.hunt(player_hint(e))
		var d: Vector3 = player.global_position - (e as Node3D).global_position
		e.facing_yaw = atan2(d.x, d.z)
	Game.enemies_remaining.emit(remaining())


func _pick_spawn() -> Vector3:
	var pts: Array = level.get_enemy_spawns() if level and level.has_method("get_enemy_spawns") else []
	if pts.is_empty():
		# no level spawns: ring around the player
		for i in 8:
			var a := randf() * TAU
			pts.append(player.global_position + Vector3(sin(a), 0, cos(a)) * randf_range(30.0, 40.0))
	var cam: Camera3D = player.get("camera")
	var eye: Vector3 = cam.global_position if cam else player.global_position + Vector3.UP * 1.6
	var fwd: Vector3 = -cam.global_basis.z if cam else Vector3.FORWARD
	var space := get_viewport().get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_s := -INF
	for p in pts:
		var pv: Vector3 = p
		var d := pv.distance_to(player.global_position)
		var s := 0.0
		if d < MIN_SPAWN_DIST:
			s -= 100.0 + (MIN_SPAWN_DIST - d) * 5.0
		var to := (pv + Vector3.UP * 1.5) - eye
		var in_view := fwd.dot(to.normalized()) > 0.35
		var q := PhysicsRayQueryParameters3D.create(eye, pv + Vector3.UP * 1.5, Game.L_WORLD | Game.L_PROPS)
		var visible := space.intersect_ray(q).is_empty()
		if visible and in_view:
			s -= 60.0
		elif visible:
			s -= 15.0
		s -= absf(d - 38.0) * 0.4
		for r in _recent_spawns:
			if (r[0] as Vector3).distance_to(pv) < 3.0 and _t - r[1] < 4.0:
				s -= 30.0
		s += randf() * 6.0
		if s > best_s:
			best_s = s
			best = pv
	if best == Vector3.INF:
		return best
	var j := best + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	j = _snap(j)
	_recent_spawns.append([best, _t])
	if _recent_spawns.size() > 12:
		_recent_spawns.pop_front()
	return j


## Where the director tells hunting enemies to go: last contact if recent, else the player's area (noisy).
func player_hint(_e: Node) -> Vector3:
	var p := player.global_position
	if _t - _last_contact_t < 6.0:
		p = _last_contact_pos
	return p + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))


func report_contact(from: Node, pos: Vector3) -> void:
	var fresh := _t - _last_contact_t > 1.0
	_last_contact_t = _t
	_last_contact_pos = pos
	if not fresh:
		return
	for e in enemies:
		if e != from and is_instance_valid(e) and e.alive and (e as Node3D).global_position.distance_to((from as Node3D).global_position) < 45.0:
			e.share_contact(pos)


func can_throw_grenade() -> bool:
	return _t - _last_grenade_t > Cfg.GRENADE_COOLDOWN


func note_grenade() -> void:
	_last_grenade_t = _t


func has_token(e: Node) -> bool:
	return _tokens.has(e.get_instance_id())


func _assign_tokens() -> void:
	_tokens.clear()
	var n := 2 if wave <= 1 else 3
	var cands := []
	for e in enemies:
		if is_instance_valid(e) and e.alive and e.state == "combat" and e.has_los:
			cands.append([(e as Node3D).global_position.distance_to(player.global_position), e])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(n, cands.size()):
		_tokens[cands[i][1].get_instance_id()] = true


func _on_enemy_died(e: Node) -> void:
	enemies.erase(e)
	corpses.append(e)
	total_killed += 1
	CoverFinder.release(e)
	while corpses.size() > Cfg.MAX_CORPSES:
		var c = corpses.pop_front()
		if is_instance_valid(c):
			c.start_sink()
	Game.enemies_remaining.emit(remaining())


func _prune() -> void:
	for i in range(corpses.size() - 1, -1, -1):
		if not is_instance_valid(corpses[i]):
			corpses.remove_at(i)
	for i in range(enemies.size() - 1, -1, -1):
		if not is_instance_valid(enemies[i]):
			enemies.remove_at(i)
		elif (enemies[i] as Node3D).global_position.y < -30.0:
			# fell out of the world: recycle into the queue
			queue.push_back(enemies[i].arch_id)
			enemies[i].queue_free()
			enemies.remove_at(i)
