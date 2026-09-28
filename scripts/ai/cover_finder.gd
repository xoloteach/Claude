extends RefCounted
## Cover selection that works on any level geometry. Candidates come from level.get_cover_points() when the
## level provides it, otherwise from rings sampled around the enemy, snapped to the navmesh.
## A good cover spot: at a useful range from the player, the crouched chest ray to the player is blocked,
## and there is a peek position (stand up in place, or step ~0.9 m sideways) with line of sight.

const MAX_CANDIDATES := 14

static var claims := {}   # enemy instance id -> Vector3 (claimed cover positions)


static func release(enemy: Node) -> void:
	claims.erase(enemy.get_instance_id())


static func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, Game.L_WORLD | Game.L_PROPS)
	return space.intersect_ray(q).is_empty()


static func find(enemy: Node3D, retreat: bool) -> Dictionary:
	var player: Node3D = enemy.player
	if player == null:
		return {}
	var space := enemy.get_world_3d().direct_space_state
	var map := enemy.get_world_3d().navigation_map
	var nav_ok := NavigationServer3D.map_get_iteration_id(map) > 0
	var ppos := player.global_position
	var pchest := ppos + Vector3.UP * 1.2
	var epos := enemy.global_position
	var pref: Array = enemy.arch.range_pref
	var lo: float = pref[0]
	var hi: float = pref[1]
	if retreat:
		lo = maxf(lo, epos.distance_to(ppos) + 6.0)
		hi = lo + 18.0
	var cands: Array[Vector3] = []
	var lvl = enemy.level
	if lvl and is_instance_valid(lvl) and lvl.has_method("get_cover_points"):
		var pts: Array = lvl.get_cover_points()
		var scored := []
		for p in pts:
			var dp: float = (p as Vector3).distance_to(epos)
			if dp < 30.0:
				scored.append([dp, p])
		scored.sort_custom(func(a, b): return a[0] < b[0])
		for i in mini(scored.size(), MAX_CANDIDATES - 6):
			cands.append(scored[i][1])
	# procedural samples: bias towards the player's flank-side ring at the preferred range
	var to_e := epos - ppos
	to_e.y = 0
	var base_ang := atan2(to_e.x, to_e.z)
	var want := clampf(to_e.length(), lo, hi)
	while cands.size() < MAX_CANDIDATES:
		var a := base_ang + randf_range(-0.9, 0.9)
		var r := want + randf_range(-4.0, 4.0)
		var p := ppos + Vector3(sin(a), 0, cos(a)) * r
		if p.distance_to(epos) > 22.0:
			p = epos + (p - epos).normalized() * 22.0
		cands.append(p)
	var best := {}
	var best_score := -INF
	for c in cands:
		var p: Vector3 = c
		if nav_ok:
			p = NavigationServer3D.map_get_closest_point(map, p)
		var d := p.distance_to(ppos)
		if d < lo * 0.6 or d > hi * 1.3:
			continue
		var taken := false
		for k in claims:
			if k != enemy.get_instance_id() and (claims[k] as Vector3).distance_to(p) < 2.2:
				taken = true
				break
		if taken:
			continue
		var low := p + Vector3.UP * 0.95
		if _clear(space, low, pchest):
			continue   # no protection
		# peek options
		var peek := Vector3.INF
		var stand := false
		if _clear(space, p + Vector3.UP * 1.55, pchest):
			peek = p
			stand = true
		else:
			var to_p := (ppos - p)
			to_p.y = 0
			to_p = to_p.normalized()
			var side := Vector3(-to_p.z, 0, to_p.x)
			for s in [1.0, -1.0]:
				var sp: Vector3 = p + side * s * 0.95
				if _clear(space, p + Vector3.UP * 1.2, sp + Vector3.UP * 1.2) and _clear(space, sp + Vector3.UP * 1.45, pchest):
					peek = sp
					break
		var score := 0.0
		score -= absf(d - (lo + hi) * 0.5) * 0.35
		score -= p.distance_to(epos) * 0.45
		if peek == Vector3.INF:
			score -= 6.0 if not retreat else 1.0
		else:
			score += 3.0
		if retreat:
			score += d * 0.3
		# don't run across the player's line of fire towards them
		if not retreat and p.distance_to(ppos) < epos.distance_to(ppos) - 8.0:
			score -= 4.0
		if score > best_score:
			best_score = score
			best = {"pos": p, "peek": peek if peek != Vector3.INF else p, "stand": stand, "score": score}
	if not best.is_empty():
		claims[enemy.get_instance_id()] = best.pos
	return best
