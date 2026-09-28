extends Node3D
## Root of the game: environment/lighting, level, player, HUD, menus, wave director, pause & mouse capture.

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var level: Node3D
var player: Player
var hud: HUD
var menus: Node
var director: Node
var touch: Node
var menu_cam: Camera3D
var _menu_t := 0.0
var _had_capture := false
var state := "menu"   # menu, playing, paused, dead


func _ready() -> void:
	Game.world = self
	_setup_environment()
	level = preload("res://scripts/world/level.gd").new()
	level.name = "Level"
	add_child(level)
	level.build()
	menu_cam = Camera3D.new()
	menu_cam.fov = 55.0
	menu_cam.far = 800.0
	add_child(menu_cam)
	menu_cam.current = true
	hud = HUD.new()
	hud.visible = false
	add_child(hud)
	var MenusScript = load("res://scripts/ui/menus.gd") if ResourceLoader.exists("res://scripts/ui/menus.gd") else null
	if MenusScript:
		menus = MenusScript.new()
		add_child(menus)
	var TouchScript = load("res://scripts/ui/touch_controls.gd") if ResourceLoader.exists("res://scripts/ui/touch_controls.gd") else null
	if TouchScript:
		touch = TouchScript.new()
		add_child(touch)
	var DirectorScript = load("res://scripts/ai/wave_director.gd") if ResourceLoader.exists("res://scripts/ai/wave_director.gd") else null
	if DirectorScript:
		director = DirectorScript.new()
		director.name = "WaveDirector"
		add_child(director)
	Game.game_over.connect(_on_game_over)
	Game.settings_changed.connect(_apply_quality)
	_apply_quality()
	Audio.play_music("music_menu")
	Audio.play_ambience(["amb_wind", "amb_battle"], -14.0)
	if OS.get_cmdline_user_args().has("--autostart"):
		start_game()


func _setup_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	if ResourceLoader.exists("res://assets/hdri/sky.hdr"):
		sky_mat.panorama = load("res://assets/hdri/sky.hdr")
	sky_mat.energy_multiplier = 1.0
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_sky_contribution = 0.85
	env.ambient_light_color = Color(0.55, 0.5, 0.48)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.78, 0.6, 0.45)
	env.fog_light_energy = 0.9
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.25
	env.fog_height = 6.0
	env.fog_height_density = 0.02
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	# HDRI sun ~6 deg elevation; raise to ~24 deg for readable shadows while keeping the azimuth
	sun.rotation_degrees = Vector3(-24.0, -35.8 + 180.0, 0.0)
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.8
	add_child(sun)


func _apply_quality() -> void:
	var q: int = Game.settings.quality
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	vp.scaling_3d_scale = [0.75, 0.9, 1.0][q]
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = [45.0, 70.0, 100.0][q]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	env.glow_enabled = q >= 1
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096][q], true)
	if level and level.has_method("apply_quality"):
		level.apply_quality(q)


# ------------------------------------------------------------------ flow
func start_game() -> void:
	if state == "playing":
		return
	Game.reset_run()
	FX.reset()
	if player and is_instance_valid(player):
		player.queue_free()
	player = Player.new()
	player.name = "Player"
	add_child(player)
	var sp: Transform3D = level.get_player_spawn() if level.has_method("get_player_spawn") else Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	player.global_position = sp.origin
	player.yaw = sp.basis.get_euler().y
	player.died.connect(_on_player_died)
	hud.player = player
	hud.visible = true
	menu_cam.current = false
	player.camera.current = true
	state = "playing"
	Game.in_game = true
	Game.paused = false
	get_tree().paused = false
	if menus and menus.has_method("hide_all"):
		menus.hide_all()
	Audio.stop_music(2.0)
	_capture_mouse()
	if director and director.has_method("start"):
		director.start(level, player)
	Game.weapon_changed.emit(player.weapons.weapon.def)
	player.weapons._emit_ammo()


func _capture_mouse() -> void:
	if Game.input_mode != "touch" and not (touch and touch.has_method("is_active") and touch.is_active()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause_game() -> void:
	if state != "playing":
		return
	state = "paused"
	Game.paused = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menus and menus.has_method("show_pause"):
		menus.show_pause()


func resume_game() -> void:
	if state != "paused":
		return
	state = "playing"
	Game.paused = false
	get_tree().paused = false
	_capture_mouse()
	if menus and menus.has_method("hide_all"):
		menus.hide_all()


func quit_to_menu() -> void:
	get_tree().paused = false
	Game.paused = false
	Game.in_game = false
	state = "menu"
	if director and director.has_method("stop"):
		director.stop()
	if player and is_instance_valid(player):
		player.queue_free()
		player = null
	hud.visible = false
	menu_cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_music("music_menu")
	if menus and menus.has_method("show_main"):
		menus.show_main()


func _on_player_died() -> void:
	state = "dead"


func _on_game_over(stats: Dictionary) -> void:
	await get_tree().create_timer(2.2).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menus and menus.has_method("show_game_over"):
		menus.show_game_over(stats)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == "playing":
			pause_game()
		elif state == "paused":
			resume_game()
		get_viewport().set_input_as_handled()
	elif state == "playing" and event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and Game.input_mode == "kbm":
		_capture_mouse()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and not OS.has_feature("web"):
		pause_game()


func _process(delta: float) -> void:
	# web: browser releases pointer lock on Esc -> pause
	if state == "playing" and Game.input_mode == "kbm":
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_had_capture = true
		elif _had_capture:
			_had_capture = false
			pause_game()
	if menu_cam.current:
		_menu_t += delta
		var path: Array = level.get_menu_camera_path() if level.has_method("get_menu_camera_path") else []
		if path.size() >= 2:
			var n := path.size()
			var f := fmod(_menu_t * 0.025, float(n))
			var i := int(f)
			var a: Transform3D = path[i]
			var b: Transform3D = path[(i + 1) % n]
			var k := f - i
			k = k * k * (3.0 - 2.0 * k)
			menu_cam.global_transform = a.interpolate_with(b, k)
		else:
			menu_cam.global_position = Vector3(sin(_menu_t * 0.05) * 30.0, 8.0, cos(_menu_t * 0.05) * 30.0)
			menu_cam.look_at(Vector3(0, 2, 0))


func debug_spawn_enemy(n: int) -> void:
	if director and director.has_method("debug_spawn"):
		director.debug_spawn(n)


func debug_state() -> Dictionary:
	var d := {"state": state}
	if director and director.has_method("alive_count"):
		d["enemies"] = director.alive_count()
	return d
