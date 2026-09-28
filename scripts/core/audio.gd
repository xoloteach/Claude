extends Node
## Pooled sound playback. Sounds are referenced by base name, e.g. "ar_fire" -> ar_fire_1..N.wav (random variant).

const SFX_DIR := "res://assets/audio/sfx/"
const POOL_3D := 48
const POOL_2D := 24

var _cache := {}         # base name -> Array[AudioStream]
var _last_idx := {}      # base name -> last variant index (avoid repeats)
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _music: AudioStreamPlayer
var _amb: Array[AudioStreamPlayer] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"World"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		p.max_distance = 140.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -18.0
		p.panning_strength = 1.0
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool2d.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	for i in 2:
		var a := AudioStreamPlayer.new()
		a.bus = &"SFX"
		add_child(a)
		_amb.append(a)


func get_variants(base: String) -> Array:
	if _cache.has(base):
		return _cache[base]
	var arr: Array = []
	for ext: String in [".wav", ".ogg"]:
		var single := SFX_DIR + base + ext
		if ResourceLoader.exists(single):
			arr.append(load(single))
		for i in range(1, 10):
			var path := "%s%s_%d%s" % [SFX_DIR, base, i, ext]
			if ResourceLoader.exists(path):
				arr.append(load(path))
			elif i > 1:
				break
	_cache[base] = arr
	return arr

func has_sound(base: String) -> bool:
	return not get_variants(base).is_empty()

func _pick(base: String) -> AudioStream:
	var v := get_variants(base)
	if v.is_empty():
		return null
	if v.size() == 1:
		return v[0]
	var idx := randi() % v.size()
	if idx == _last_idx.get(base, -1):
		idx = (idx + 1) % v.size()
	_last_idx[base] = idx
	return v[idx]


## Positional one-shot.
func play3d(base: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.06, unit_size := 6.0, max_dist := 140.0) -> AudioStreamPlayer3D:
	var s := _pick(base)
	if s == null:
		return null
	var p := _pool3d[_i3]
	_i3 = (_i3 + 1) % POOL_3D
	p.stop()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = max_dist
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
	return p

## Non-positional one-shot (player weapon, UI, feedback).
func play(base: String, volume_db := 0.0, pitch_var := 0.04, bus := &"SFX") -> AudioStreamPlayer:
	var s := _pick(base)
	if s == null:
		return null
	var p := _pool2d[_i2]
	_i2 = (_i2 + 1) % POOL_2D
	p.stop()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
	return p

func ui(base: String) -> void:
	play(base, -4.0, 0.02, &"UI")

func play_music(base: String, fade := 1.5) -> void:
	var s := _pick(base)
	if s == null:
		return
	if _music.stream == s and _music.playing:
		return
	_music.stream = s
	_music.volume_db = -40.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", 0.0, fade)

func stop_music(fade := 1.5) -> void:
	if _music.playing:
		var t := create_tween()
		t.tween_property(_music, "volume_db", -40.0, fade)
		t.tween_callback(_music.stop)

func play_ambience(bases: Array, volume_db := -10.0) -> void:
	for i in _amb.size():
		var a := _amb[i]
		if i < bases.size():
			var s := _pick(bases[i])
			if s:
				a.stream = s
				a.volume_db = volume_db - 4.0 * i
				a.play()
		else:
			a.stop()

func stop_ambience() -> void:
	for a in _amb:
		a.stop()
