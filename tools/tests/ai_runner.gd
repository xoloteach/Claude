extends Node
## Headless AI test: spawns enemies, checks they path, shoot the (god-mode) player, die when shot, waves progress.
## Run (needs game.gd to load this runner for --test=ai, or copy over runner.gd locally):
##   godot --headless -- --test=ai
var frames := 0
var t := 0.0
var hurt := 0
var hurt_dmg := 0.0
var kills := 0
var banners := []
var waves := []
var phase := 0
var _printed := {}
var _start_pos := {}
var target: Node3D


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.player_hurt.connect(func(_p, a): hurt += 1; hurt_dmg += a)
	Game.kill_registered.connect(func(i): kills += 1; print("KILL ", JSON.stringify(i)))
	Game.hud_message.connect(func(txt, k): banners.append(txt); print("MSG ", k, " ", txt))
	Game.wave_changed.connect(func(w): waves.append(w); print("WAVE ", w))


func _dir():
	return Game.world.director if Game.world else null


func _physics_process(delta):
	frames += 1
	t += delta
	var dir = _dir()
	match phase:
		0:
			if frames == 5:
				Game.run_command("start")
			if frames == 8:
				# debug spawn test (director may auto-start waves; stop them for the controlled test)
				Game.world.player.set("god_mode", true)
				dir.stop()
				dir.player = Game.world.player
				dir.level = Game.world.level
				dir.debug_spawn(3)
				for e in dir.enemies:
					_start_pos[e.get_instance_id()] = e.global_position
				print("SPAWNED ", dir.alive_count())
				phase = 1
				t = 0.0
		1:
			if int(t * 2) != int((t - delta) * 2):
				for e in dir.enemies:
					if is_instance_valid(e):
						print("  E %s st=%s mode=%s aw=%.2f los=%s pos=%s hp=%d mag=%d shots=%d hits=%d v=%.2f" % [e.name, e.state, e.mode, e.awareness, e.has_los, _v(e.global_position), e.hp, e.mag_left, e.stats.shots, e.stats.hits, Vector2(e.velocity.x, e.velocity.z).length()])
				print("  player hurt=%d dmg=%.1f" % [hurt, hurt_dmg])
			if t > 12.0:
				var moved := 0
				for e in dir.enemies:
					if is_instance_valid(e) and e.global_position.distance_to(_start_pos.get(e.get_instance_id(), e.global_position)) > 1.5:
						moved += 1
				print("CHECK moved=%d hurt=%d dmg=%.1f" % [moved, hurt, hurt_dmg])
				phase = 2
				t = 0.0
		2:
			# kill test: aim the player at the nearest enemy and fire
			var p: Node3D = Game.world.player
			if target == null or not is_instance_valid(target) or not target.alive:
				target = null
				var best := 1e9
				for e in dir.enemies:
					if is_instance_valid(e) and e.alive:
						var d: float = e.global_position.distance_to(p.global_position)
						if d < best:
							best = d
							target = e
			if target:
				var ap: Vector3 = target.aim_point()
				var cam: Camera3D = p.camera
				var to := ap - cam.global_position
				var yaw := rad_to_deg(atan2(-to.x, -to.z))
				var pitch := rad_to_deg(atan2(to.y, Vector2(to.x, to.z).length()))
				p.set_view_angles(yaw, pitch)
				Game.run_command("fire on")
			else:
				Game.run_command("fire off")
			if int(t) != int(t - delta):
				print("  kill phase t=%d alive=%d kills=%d ammo=%s" % [int(t), dir.alive_count(), kills, p.weapons.weapon.ammo])
				if p.weapons.weapon.ammo == 0:
					Game.run_command("key reload")
			if dir.alive_count() == 0 or t > 25.0:
				Game.run_command("fire off")
				print("CHECK kills=%d alive=%d" % [kills, dir.alive_count()])
				phase = 3
				t = 0.0
		3:
			if int(t) != int(t - delta):
				for c in dir.corpses:
					if is_instance_valid(c):
						print("  RAGDOLL %s %s" % [c.name, JSON.stringify(c.rig.debug_bends())])
			if t > 4.0:
				# wave progression test
				dir.start(Game.world.level, Game.world.player)
				phase = 4
				t = 0.0
		4:
			var p: Node3D = Game.world.player
			# auto-kill enemies quickly to test wave flow (debug: directly damage)
			if t > 8.0 and int(t * 4) != int((t - delta) * 4):
				for e in dir.enemies:
					if is_instance_valid(e) and e.alive and e.state == "combat":
						e.take_damage(60.0, {"zone": "body", "pos": e.global_position + Vector3.UP, "dir": -e.global_basis.z, "weapon": "TEST", "attacker": p})
						break
			if int(t) != int(t - delta) and int(t) % 3 == 0:
				var modes := {}
				for e in dir.enemies:
					if is_instance_valid(e) and e.alive:
						var k: String = e.arch_id + ":" + e.state + "/" + e.mode
						modes[k] = modes.get(k, 0) + 1
				print("  wave=%d phase=%s alive=%d queue=%d kills=%d hurt=%d modes=%s fps=%d" % [dir.wave, dir.phase, dir.alive_count(), dir.queue.size(), kills, hurt, JSON.stringify(modes), Engine.get_frames_per_second()])
			if dir.wave >= 3 and dir.phase == "wave" and t > 10.0 or t > 160.0:
				print("CHECK waves=%s banners=%s" % [str(waves), str(banners)])
				print("DONE")
				get_tree().quit()


func _v(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]
