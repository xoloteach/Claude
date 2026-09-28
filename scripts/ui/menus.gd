extends CanvasLayer
## IRONLINE front-end: title ("press any button"), main menu, pause, settings, controls, credits, game over.
## Left-side military-shooter layout over the 3D flythrough rendered by main.gd.
## Full mouse / keyboard / gamepad / touch navigation. All settings are live-applied via Game.set_setting().
##
## API used by main.gd: hide_all(), show_main(), show_pause(), show_game_over(stats)

const T := preload("res://scripts/ui/ui_theme.gd")
const W := preload("res://scripts/ui/menu_widgets.gd")

const TAGLINE := "OPERATION: DEEP WATER"
const DESIGN_H := 900.0          # logical height on desktop
const DESIGN_H_TOUCH := 600.0    # logical height on touch screens (=> everything bigger)

const DEFAULTS := {
	"sensitivity": 1.0, "ads_sensitivity": 0.85, "pad_sensitivity": 1.0, "touch_sensitivity": 1.0,
	"fov": 90.0, "invert_y": false, "master_volume": 0.9, "sfx_volume": 1.0, "music_volume": 0.6,
	"quality": 2, "show_fps": false, "touch_controls": -1, "aim_assist": true,
}

const BACKDROP_SHADER := """
shader_type canvas_item;
uniform float panel_frac = 0.45;
uniform float strength = 1.0;
uniform float time_s = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float left = 1.0 - smoothstep(panel_frac * 0.55, panel_frac * 1.5, uv.x);
	float a = mix(0.1, 0.84, left);
	a = max(a, smoothstep(0.62, 1.0, uv.y) * 0.72);
	a = max(a, (1.0 - smoothstep(0.0, 0.16, uv.y)) * 0.4);
	a = max(a, smoothstep(0.45, 1.05, length((uv - 0.5) * vec2(1.1, 1.5))) * 0.6);
	vec3 col = mix(vec3(0.018, 0.022, 0.028), vec3(0.05, 0.035, 0.02), left * 0.35);
	col += (hash(floor(FRAGCOORD.xy) + floor(time_s * 24.0)) - 0.5) * 0.018;
	col *= 1.0 - 0.035 * step(0.5, fract(FRAGCOORD.y * 0.5));
	COLOR = vec4(col, clamp(a * strength, 0.0, 1.0));
}
"""

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float radius = 7.0;
uniform float lod = 2.5;
uniform float darken = 0.5;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius * amount;
	float l = lod * amount;
	vec3 c = textureLod(screen_tex, SCREEN_UV, l).rgb * 0.16;
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0472;
		c += textureLod(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * px * 1.4, l).rgb * 0.07;
		c += textureLod(screen_tex, SCREEN_UV + vec2(cos(a + 0.5236), sin(a + 0.5236)) * px * 3.2, l).rgb * 0.07;
	}
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(lum), 0.35 * amount);
	c *= mix(1.0, darken, amount);
	COLOR = vec4(c, 1.0);
}
"""

var root: Control
var blur: ColorRect
var backdrop: ColorRect
var footer_left: Label
var prompts: HBoxContainer
var screens := {}              # name -> Control
var columns: Array = []        # [Control, width_logical] placed at the left margin by _layout()
var stack: Array = []          # screen navigation stack
var ctx := "title"             # title | menu | pause | over
var _scale := 1.0
var _logical := Vector2(1600, 900)
var _mode := ""
var _time := 0.0
var _blur_t := 0.0
var _blur_target := 0.0
var _title_armed_t := 0.0

# per-screen widgets
var _main_items: Array = []
var _main_desc: Label
var _pause_items: Array = []
var _pause_info: Label
var _over_items: Array = []
var _over_title: Label
var _over_sub: Label
var _over_values := {}         # key -> Label
var _over_stats := {}
var _confirm_items: Array = []
var _title_prompt: Label
var _settings_tabs: Array = []
var _settings_pages: Array = []    # VBoxContainer per tab
var _settings_rows: Array = []     # Array per tab (focusables)
var _settings_tab := 0
var _settings_scroll: ScrollContainer
var _settings_desc: Label
var _rows := {}                    # setting key -> SettingRow
var _controls_tabs: Array = []
var _controls_pages: Array = []
var _controls_tab := 0
var _prompt_buttons := {}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_ui_actions()
	root = Control.new()
	root.name = "MenusRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	blur = ColorRect.new()
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bs := Shader.new()
	bs.code = BLUR_SHADER
	var bm := ShaderMaterial.new()
	bm.shader = bs
	blur.material = bm
	blur.visible = false
	root.add_child(blur)
	backdrop = ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ds := Shader.new()
	ds.code = BACKDROP_SHADER
	var dm := ShaderMaterial.new()
	dm.shader = ds
	backdrop.material = dm
	root.add_child(backdrop)
	_build_title()
	_build_main()
	_build_pause()
	_build_settings()
	_build_controls()
	_build_credits()
	_build_confirm()
	_build_game_over()
	_build_footer()
	get_viewport().size_changed.connect(_layout)
	Game.settings_changed.connect(_on_settings_changed)
	_layout()
	_open_root("title", "title")


## Gamepad A/B must drive the GUI (not in the engine defaults for this version).
func _ensure_ui_actions() -> void:
	var add_btn := func(action: String, b: JoyButton):
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton and e.button_index == b:
				return
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)
	add_btn.call("ui_accept", JOY_BUTTON_A)
	add_btn.call("ui_cancel", JOY_BUTTON_B)


# ====================================================================== public API (main.gd)
func hide_all() -> void:
	stack.clear()
	for s in screens.values():
		s.visible = false
	backdrop.visible = false
	_blur_target = 0.0
	blur.visible = false
	_blur_t = 0.0
	prompts.get_parent().visible = false
	ctx = "hidden"
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()


func show_main() -> void:
	_open_root("main", "menu")


func show_pause() -> void:
	_refresh_pause_info()
	_open_root("pause", "pause")


func show_game_over(stats: Dictionary) -> void:
	_over_stats = stats
	_open_root("over", "over")
	_animate_game_over()


func is_open() -> bool:
	return ctx != "hidden" and not stack.is_empty()


# ====================================================================== navigation
func _open_root(name: String, c: String) -> void:
	ctx = c
	stack = [name]
	backdrop.visible = true
	_blur_target = 1.0 if c in ["pause", "over"] else 0.0
	blur.visible = _blur_target > 0.0
	prompts.get_parent().visible = true
	_show_screen(name)


func _push(name: String) -> void:
	T.sound("ui_click")
	stack.append(name)
	_show_screen(name)


func _back() -> void:
	if stack.size() <= 1:
		if ctx == "pause":
			_resume()
		return
	T.sound("ui_back")
	stack.pop_back()
	_show_screen(stack.back(), true)


func _show_screen(name: String, backwards := false) -> void:
	for k in screens:
		screens[k].visible = k == name
	var s: Control = screens[name]
	s.modulate.a = 0.0
	s.position.x = 26.0 if backwards else -26.0
	var tw := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(s, "modulate:a", 1.0, 0.22)
	tw.tween_property(s, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_update_prompts()
	match name:
		"title":
			_title_armed_t = 0.35
		"main": _focus(_main_items[0])
		"pause": _focus(_pause_items[0])
		"over": _focus(_over_items[0])
		"confirm": _focus(_confirm_items[1])
		"settings":
			_sync_settings()
			_select_settings_tab(_settings_tab, false)
		"controls":
			_select_controls_tab(_controls_tab if _controls_tab >= 0 else 0, false)
			var f := get_viewport().gui_get_focus_owner()
			if f: f.release_focus()
		"credits":
			var f2 := get_viewport().gui_get_focus_owner()
			if f2: f2.release_focus()


func _focus(c: Control) -> void:
	if c == null:
		return
	c.set("silent_focus", true)
	c.grab_focus()
	if not c.has_focus():
		c.set("silent_focus", false)


func _main_node() -> Node:
	return get_parent()


func _deploy() -> void:
	T.sound("ui_click")
	var m := _main_node()
	# NOTE: called from the click/press handler -> the browser treats it as a user gesture,
	# so main.start_game()'s pointer capture is allowed on web.
	if m and m.has_method("start_game"):
		m.start_game()


func _resume() -> void:
	T.sound("ui_back")
	var m := _main_node()
	if m and m.has_method("resume_game"):
		m.resume_game()


func _quit_to_menu() -> void:
	T.sound("ui_click")
	var m := _main_node()
	if m and m.has_method("quit_to_menu"):
		m.quit_to_menu()


func _retry() -> void:
	T.sound("ui_click")
	var m := _main_node()
	if m and m.has_method("start_game"):
		m.start_game()


# ====================================================================== input
func _input(event: InputEvent) -> void:
	if ctx == "title" and _title_armed_t <= 0.0 and screens.title.visible:
		var any := false
		if event is InputEventKey and event.pressed and not event.echo:
			any = true
		elif event is InputEventMouseButton and event.pressed:
			any = true
		elif event is InputEventJoypadButton and event.pressed:
			any = true
		elif event is InputEventScreenTouch and event.pressed:
			any = true
		if any:
			get_viewport().set_input_as_handled()
			T.sound("ui_click")
			_open_root("main", "menu")
		return
	if not is_open():
		return
	var top: String = stack.back()
	if top == "settings" or top == "controls":
		var dir := 0
		if event is InputEventJoypadButton and event.pressed:
			if event.button_index == JOY_BUTTON_LEFT_SHOULDER: dir = -1
			elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER: dir = 1
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_Q: dir = -1
			elif event.physical_keycode == KEY_E: dir = 1
		if dir != 0:
			get_viewport().set_input_as_handled()
			T.sound("ui_hover")
			if top == "settings":
				_select_settings_tab(posmod(_settings_tab + dir, _settings_pages.size()), true)
			else:
				_select_controls_tab(posmod(_controls_tab + dir, _controls_pages.size()), true)
			return
		if top == "controls" and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")):
			var sc: ScrollContainer = _controls_pages[_controls_tab].get_meta("scroll")
			sc.scroll_vertical += -60 if event.is_action_pressed("ui_up") else 60
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or ctx == "title":
		return
	var top: String = stack.back()
	# Start / P while paused resumes from anywhere in the pause stack
	if ctx == "pause" and event.is_action_pressed("pause") and not (event is InputEventKey and event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_resume()
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_XBUTTON1):
		get_viewport().set_input_as_handled()
		if top == "over" or top == "main":
			return
		_back()
		return
	# something must always own focus for pad/keys: recover it if the mouse cleared it
	if (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_accept")) and get_viewport().gui_get_focus_owner() == null:
		var list: Array = _focus_list(top)
		if not list.is_empty():
			_focus(list[0])
			get_viewport().set_input_as_handled()


func _focus_list(name: String) -> Array:
	match name:
		"main": return _main_items
		"pause": return _pause_items
		"over": return _over_items
		"confirm": return _confirm_items
		"settings": return _settings_rows[_settings_tab]
	return []


# ====================================================================== frame
func _process(delta: float) -> void:
	_time += delta
	_title_armed_t -= delta
	(backdrop.material as ShaderMaterial).set_shader_parameter("time_s", _time)
	_blur_t = move_toward(_blur_t, _blur_target, delta * 4.0)
	if blur.visible:
		(blur.material as ShaderMaterial).set_shader_parameter("amount", _blur_t)
		if _blur_t <= 0.0 and _blur_target <= 0.0:
			blur.visible = false
	if screens.title.visible:
		_title_prompt.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_time * 3.2))
	if Game.input_mode != _mode:
		_mode = Game.input_mode
		_update_prompts()
		_layout()


# ====================================================================== layout / scaling
func _is_touchish() -> bool:
	return Game.input_mode == "touch" or Game.wants_touch_controls() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 2.0 or vp.y < 2.0:
		return
	var dh := DESIGN_H_TOUCH if _is_touchish() else DESIGN_H
	_scale = maxf(0.3, minf(vp.y / dh, vp.x / 760.0))
	_logical = vp / _scale
	root.position = Vector2.ZERO
	root.scale = Vector2(_scale, _scale)
	root.size = _logical
	var margin := 96.0 if _logical.x > 1250.0 else 44.0
	for pair in columns:
		var c: Control = pair[0]
		var w: float = minf(pair[1], _logical.x - margin * 2.0)
		c.offset_left = margin
		c.offset_right = margin + w
	var mat := backdrop.material as ShaderMaterial
	mat.set_shader_parameter("panel_frac", clampf((margin + 560.0) / _logical.x, 0.25, 0.9))
	if footer_left:
		footer_left.get_parent().offset_left = margin
		footer_left.get_parent().offset_right = -margin


func _column(parent: Control, width: float, top := 70.0, bottom := 84.0) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.anchor_top = 0.0
	v.anchor_bottom = 1.0
	v.offset_top = top
	v.offset_bottom = -bottom
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	parent.add_child(v)
	columns.append([v, width])
	return v


func _screen(name: String) -> Control:
	var s := Control.new()
	s.name = "Screen_" + name
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.visible = false
	root.add_child(s)
	screens[name] = s
	return s


func _spacer(parent: Control, h: float, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c


func _chain(items: Array) -> void:
	var n := items.size()
	for i in n:
		var c: Control = items[i]
		var prev: Control = items[(i - 1 + n) % n]
		var next: Control = items[(i + 1) % n]
		c.focus_neighbor_top = c.get_path_to(prev)
		c.focus_neighbor_bottom = c.get_path_to(next)
		c.focus_previous = c.get_path_to(prev)
		c.focus_next = c.get_path_to(next)
		c.focus_neighbor_left = c.get_path_to(c)
		c.focus_neighbor_right = c.get_path_to(c)


# ====================================================================== pieces
func _wordmark(size_px: int, with_tag := true) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	if with_tag:
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 12)
		var bar := T.rect(T.C_ACCENT)
		bar.custom_minimum_size = Vector2(34, 3)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		h.add_child(T.label(TAGLINE, T.FONT_SEMI, maxi(16, size_px / 5), T.C_ACCENT, 5))
		v.add_child(h)
	var logo := T.shadow(T.label("IRONLINE", T.FONT_HEAD, size_px, T.C_WHITE, int(size_px * 0.06)), 0.5, 14)
	logo.add_theme_constant_override("line_spacing", -int(size_px * 0.2))
	v.add_child(logo)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 0)
	var a := T.rect(T.C_ACCENT)
	a.custom_minimum_size = Vector2(size_px * 0.9, 2)
	line.add_child(a)
	var b := T.rect(Color(1, 1, 1, 0.18))
	b.custom_minimum_size = Vector2(size_px * 2.4, 1)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(b)
	v.add_child(line)
	return v


func _heading(parent: Control, title: String, sub := "") -> void:
	if sub != "":
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 10)
		var bar := T.rect(T.C_ACCENT)
		bar.custom_minimum_size = Vector2(22, 3)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		h.add_child(T.label(sub.to_upper(), T.FONT_SEMI, 19, T.C_ACCENT, 4))
		parent.add_child(h)
	parent.add_child(T.shadow(T.label(title.to_upper(), T.FONT_HEAD, 76, T.C_WHITE, 3)))
	var line := T.rect(Color(1, 1, 1, 0.16))
	line.custom_minimum_size = Vector2(0, 1)
	parent.add_child(line)
	_spacer(parent, 14)


func _item(parent: Control, cap: String, desc: String, cb: Callable, size_px := 34) -> Button:
	var b := W.MenuItem.new(cap, desc, size_px)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ====================================================================== TITLE
func _build_title() -> void:
	var s := _screen("title")
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_bottom = -60
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(c)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	v.add_child(_wordmark(170))
	_spacer(v, 70)
	_title_prompt = T.shadow(T.label("PRESS ANY BUTTON", T.FONT_SEMI, 28, T.C_WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_title_prompt)


# ====================================================================== MAIN
func _build_main() -> void:
	var s := _screen("main")
	var col := _column(s, 720, 64, 92)
	col.add_child(_wordmark(104))
	_spacer(col, 20, true)
	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 2)
	list.custom_minimum_size = Vector2(460, 0)
	list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(list)
	_main_items = [
		_item(list, "Deploy", "Hold the harbor against endless waves of hostiles. How long can you survive?", _deploy, 44),
		_item(list, "Settings", "Sensitivity, field of view, graphics quality, audio and touch controls.", func(): _push("settings")),
		_item(list, "Controls", "Keyboard & mouse, controller and touchscreen layouts.", func(): _push("controls")),
		_item(list, "Credits", "The tools, assets and people behind IRONLINE.", func(): _push("credits")),
	]
	if not OS.has_feature("web"):
		_main_items.append(_item(list, "Quit", "Exit to desktop.", func(): get_tree().quit()))
	for b in _main_items:
		b.custom_minimum_size.x = 460
	_chain(_main_items)
	_spacer(col, 18)
	var dl := T.rect(Color(1, 1, 1, 0.14))
	dl.custom_minimum_size = Vector2(460, 1)
	dl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(dl)
	_spacer(col, 8)
	_main_desc = T.label("", T.FONT_BODY_MED, 19, T.C_DIM)
	_main_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_desc.custom_minimum_size = Vector2(460, 50)
	_main_desc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_main_desc)
	for b in _main_items:
		b.focus_entered.connect(func(): _main_desc.text = b.desc)


# ====================================================================== PAUSE
func _build_pause() -> void:
	var s := _screen("pause")
	var col := _column(s, 720, 64, 92)
	_heading(col, "Paused", TAGLINE)
	_pause_info = T.label("", T.FONT_SEMI, 22, T.C_DIM, 2)
	col.add_child(_pause_info)
	_spacer(col, 20, true)
	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(list)
	_pause_items = [
		_item(list, "Resume", "", _resume, 40),
		_item(list, "Settings", "", func(): _push("settings")),
		_item(list, "Controls", "", func(): _push("controls")),
		_item(list, "Quit to Menu", "", func(): _push("confirm")),
	]
	_pause_items[3].danger = true
	for b in _pause_items:
		b.custom_minimum_size.x = 460
	_chain(_pause_items)
	_spacer(col, 40, true)


func _refresh_pause_info() -> void:
	var t := int(Game.time_alive)
	_pause_info.text = "WAVE %d     SCORE %d     KILLS %d     TIME %02d:%02d" % [maxi(Game.wave, 1), Game.score, Game.kills, t / 60, t % 60]


# ====================================================================== CONFIRM (quit)
func _build_confirm() -> void:
	var s := _screen("confirm")
	var col := _column(s, 720, 64, 92)
	_heading(col, "Abandon?", "Quit to main menu")
	var l := T.label("Your current run will end and its score will be lost.", T.FONT_BODY_MED, 21, T.C_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	_spacer(col, 20, true)
	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(list)
	_confirm_items = [
		_item(list, "Quit to Menu", "", _quit_to_menu, 36),
		_item(list, "Cancel", "", _back, 36),
	]
	_confirm_items[0].danger = true
	for b in _confirm_items:
		b.custom_minimum_size.x = 460
	_chain(_confirm_items)
	_spacer(col, 40, true)


# ====================================================================== SETTINGS
func _fmt2(v: float) -> String: return "%.2f" % v
func _fmtx(v: float) -> String: return "%.2fx" % v
func _fmti(v: float) -> String: return "%d" % roundi(v)
func _fmtpct(v: float) -> String: return "%d%%" % roundi(v * 100.0)


func _build_settings() -> void:
	var s := _screen("settings")
	var col := _column(s, 900, 64, 84)
	_heading(col, "Settings", "Options")
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override("separation", 4)
	col.add_child(tabs)
	var tab_line := T.rect(Color(1, 1, 1, 0.1))
	tab_line.custom_minimum_size = Vector2(0, 1)
	col.add_child(tab_line)
	_spacer(col, 12)
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.follow_focus = true
	_settings_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_scrollbar(_settings_scroll)
	col.add_child(_settings_scroll)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_scroll.add_child(holder)
	var pages := [
		["Controls", [
			["slider", "sensitivity", "Mouse Sensitivity", "Camera speed for mouse look.", 0.1, 5.0, 0.05, _fmt2],
			["slider", "ads_sensitivity", "ADS Sensitivity Multiplier", "Look speed while aiming down sights, relative to hip-fire.", 0.2, 2.0, 0.05, _fmtx],
			["slider", "pad_sensitivity", "Controller Sensitivity", "Right-stick look speed.", 0.2, 3.0, 0.05, _fmt2],
			["slider", "touch_sensitivity", "Touch Look Sensitivity", "Camera speed when dragging on a touchscreen.", 0.2, 3.0, 0.05, _fmt2],
			["bool", "invert_y", "Invert Look Y", "Push up to look down (mouse, stick and touch)."],
			["bool", "aim_assist", "Aim Assist", "Slowdown and gentle pull near targets. Controller and touch only."],
		]],
		["Video", [
			["slider", "fov", "Field of View", "Horizontal field of view in degrees. Higher shows more, lower zooms in.", 60.0, 120.0, 1.0, _fmti],
			["select", "quality", "Graphics Quality", "Low favours frame rate (resolution scale, shadows, anti-aliasing, glow).", ["Low", "Medium", "High"]],
			["fullscreen", "", "Fullscreen", "Toggle fullscreen display."],
			["bool", "show_fps", "Show FPS Counter", "Frame-rate readout in the top-right corner."],
		]],
		["Audio", [
			["slider", "master_volume", "Master Volume", "Overall loudness.", 0.0, 1.0, 0.05, _fmtpct],
			["slider", "sfx_volume", "Effects Volume", "Weapons, footsteps, impacts and interface.", 0.0, 1.0, 0.05, _fmtpct],
			["slider", "music_volume", "Music Volume", "Menu and combat music.", 0.0, 1.0, 0.05, _fmtpct],
		]],
		["Touch", [
			["touch", "touch_controls", "Touch Controls", "Auto shows on-screen controls when a touchscreen is used. On forces them (desktop mouse drives them for testing)."],
			["slider", "touch_sensitivity", "Touch Look Sensitivity", "Camera speed when dragging on a touchscreen.", 0.2, 3.0, 0.05, _fmt2],
			["bool", "aim_assist", "Aim Assist", "Slowdown and gentle pull near targets."],
		]],
	]
	for pi in pages.size():
		var p: Array = pages[pi]
		var tb := W.TabButton.new(p[0])
		var idx: int = pi
		tb.pressed.connect(func():
			T.sound("ui_hover")
			_select_settings_tab(idx, true))
		tabs.add_child(tb)
		_settings_tabs.append(tb)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 4)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(page)
		_settings_pages.append(page)
		var focusables: Array = []
		for d in p[1]:
			var row := _make_setting_row(d)
			page.add_child(row)
			focusables.append(row)
		var rst := W.MenuItem.new("Restore Defaults", "", 24)
		rst.custom_minimum_size = Vector2(300, 48)
		rst.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var keys: Array = []
		for d in p[1]:
			if d[1] != "":
				keys.append(d[1])
		rst.pressed.connect(func():
			T.sound("ui_click")
			for k in keys:
				Game.set_setting(k, DEFAULTS[k])
			_sync_settings())
		_spacer(page, 6)
		page.add_child(rst)
		rst.focus_entered.connect(func(): _settings_desc.text = "Reset this page to its default values.")
		focusables.append(rst)
		_chain(focusables)
		_settings_rows.append(focusables)
	_spacer(col, 10)
	var dl := T.rect(Color(1, 1, 1, 0.12))
	dl.custom_minimum_size = Vector2(0, 1)
	col.add_child(dl)
	_spacer(col, 6)
	_settings_desc = T.label("", T.FONT_BODY_MED, 19, T.C_DIM)
	_settings_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_desc.custom_minimum_size = Vector2(0, 48)
	col.add_child(_settings_desc)


func _make_setting_row(d: Array) -> Control:
	var kind: String = d[0]
	var key: String = d[1]
	var row := W.SettingRow.new(d[2], d[3])
	match kind:
		"slider":
			row.setup_slider(d[4], d[5], d[6], float(Game.settings.get(key, d[4])), d[7])
			row.value_changed.connect(func(v): Game.set_setting(key, float(v)))
		"bool":
			row.setup_select(["Off", "On"], 1 if Game.settings.get(key, false) else 0)
			row.value_changed.connect(func(v): Game.set_setting(key, v == 1))
		"select":
			row.setup_select(d[4], int(Game.settings.get(key, 0)))
			row.value_changed.connect(func(v): Game.set_setting(key, int(v)))
		"touch":
			row.setup_select(["Auto", "On", "Off"], [-1, 1, 0].find(int(Game.settings.get(key, -1))))
			row.value_changed.connect(func(v): Game.set_setting(key, [-1, 1, 0][v]))
		"fullscreen":
			row.setup_select(["Off", "On"], 1 if _is_fullscreen() else 0)
			row.value_changed.connect(func(v):
				# runs inside the click / key handler => counts as a user gesture on web
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if v == 1 else DisplayServer.WINDOW_MODE_WINDOWED))
			key = "__fullscreen"
	row.focus_entered.connect(func(): _settings_desc.text = row.desc)
	if not _rows.has(key):
		_rows[key] = []
	_rows[key].append(row)
	return row


func _is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _sync_settings() -> void:
	for key in _rows:
		for row in _rows[key]:
			if key == "__fullscreen":
				row.set_value_silent(1 if _is_fullscreen() else 0)
				continue
			var v = Game.settings.get(key)
			if key == "touch_controls":
				row.set_value_silent([-1, 1, 0].find(int(v)))
			elif v is bool:
				row.set_value_silent(1 if v else 0)
			else:
				row.set_value_silent(v)


func _on_settings_changed() -> void:
	if screens.has("settings") and screens.settings.visible:
		_sync_settings()
	_layout()


func _select_settings_tab(i: int, focus_first: bool) -> void:
	_settings_tab = i
	for t in _settings_tabs.size():
		_settings_tabs[t].selected = t == i
		_settings_pages[t].visible = t == i
	_settings_scroll.scroll_vertical = 0
	var first: Control = _settings_rows[i][0]
	if focus_first:
		first.grab_focus()
	else:
		_focus(first)
	_settings_desc.text = first.get("desc") if first.get("desc") else ""


func _style_scrollbar(sc: ScrollContainer) -> void:
	var bar := sc.get_v_scroll_bar()
	var g := StyleBoxFlat.new()
	g.bg_color = Color(T.C_ACCENT, 0.8)
	g.content_margin_left = 3
	g.content_margin_right = 3
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(1, 1, 1, 0.06)
	bgs.content_margin_left = 3
	bgs.content_margin_right = 3
	bar.add_theme_stylebox_override("grabber", g)
	bar.add_theme_stylebox_override("grabber_highlight", g)
	bar.add_theme_stylebox_override("grabber_pressed", g)
	bar.add_theme_stylebox_override("scroll", bgs)


# ====================================================================== CONTROLS
const BIND_KBM := [
	["Move", "W A S D"], ["Look", "Mouse"], ["Fire", "Left Mouse"], ["Aim Down Sights", "Right Mouse"],
	["Jump / Mantle", "Space"], ["Crouch / Slide", "C  /  Ctrl"], ["Sprint / Tactical Sprint", "Shift (tap again)"],
	["Reload", "R"], ["Swap Weapon", "Q  /  Mouse Wheel"], ["Select Weapon", "1 - 5"], ["Grenade", "G"],
	["Melee", "V"], ["Hold Breath (scoped)", "Shift"], ["Scoreboard", "Tab"], ["Pause", "Esc  /  P"],
]
const BIND_PAD := [
	["Move", "Left Stick"], ["Look", "Right Stick"], ["Fire", "RT"], ["Aim Down Sights", "LT"],
	["Jump / Mantle", "A"], ["Crouch / Slide", "B"], ["Sprint / Tactical Sprint", "L3 (click again)"],
	["Reload", "X"], ["Swap Weapon", "Y"], ["Grenade", "RB"], ["Melee", "R3"],
	["Hold Breath (scoped)", "L3"], ["Scoreboard", "View / Back"], ["Pause", "Menu / Start"],
	["Menus", "D-pad / Left Stick, A select, B back, LB/RB tabs"],
]
const BIND_TOUCH := [
	["Move", "Left joystick (appears under your thumb)"], ["Sprint", "Push joystick to the top edge"],
	["Look", "Drag anywhere on the right side"], ["Fire", "Large FIRE button (drag it to aim while firing)"],
	["Fire (left hand)", "Small FIRE above the joystick"], ["Aim Down Sights", "ADS (toggle)"],
	["Jump / Mantle", "JUMP"], ["Crouch / Slide", "CROUCH (while sprinting = slide)"], ["Reload", "RELOAD"],
	["Swap Weapon", "SWAP"], ["Grenade", "GRENADE"], ["Melee", "MELEE"], ["Pause", "II (top right)"],
]


func _build_controls() -> void:
	var s := _screen("controls")
	var col := _column(s, 980, 64, 84)
	_heading(col, "Controls", "Layouts")
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override("separation", 4)
	col.add_child(tabs)
	var tl := T.rect(Color(1, 1, 1, 0.1))
	tl.custom_minimum_size = Vector2(0, 1)
	col.add_child(tl)
	_spacer(col, 12)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(holder)
	var sets := [["Keyboard & Mouse", BIND_KBM], ["Controller", BIND_PAD], ["Touch", BIND_TOUCH]]
	for i in sets.size():
		var tb := W.TabButton.new(sets[i][0])
		var idx: int = i
		tb.pressed.connect(func():
			T.sound("ui_hover")
			_select_controls_tab(idx, true))
		tabs.add_child(tb)
		_controls_tabs.append(tb)
		var sc := ScrollContainer.new()
		sc.set_anchors_preset(Control.PRESET_FULL_RECT)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.mouse_filter = Control.MOUSE_FILTER_PASS
		_style_scrollbar(sc)
		holder.add_child(sc)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 2)
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(list)
		for r in sets[i][1]:
			list.add_child(_bind_row(r[0], r[1]))
		sc.set_meta("scroll", sc)
		_controls_pages.append(sc)
	var note := T.label("Sprint while moving forward, sprint again for tactical sprint. Crouch while sprinting to slide. Jump at a ledge to mantle.", T.FONT_BODY_MED, 18, T.C_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spacer(col, 8)
	col.add_child(note)


func _bind_row(action: String, binding: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.28)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var a := T.label(action.to_upper(), T.FONT_SEMI, 23, T.C_DIM, 1)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := T.label(binding.to_upper(), T.FONT_HEAD, 23, T.C_WHITE, 1, HORIZONTAL_ALIGNMENT_RIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	return p


func _select_controls_tab(i: int, _user: bool) -> void:
	_controls_tab = i
	for t in _controls_tabs.size():
		_controls_tabs[t].selected = t == i
		_controls_pages[t].visible = t == i


# ====================================================================== CREDITS
func _build_credits() -> void:
	var s := _screen("credits")
	var col := _column(s, 900, 64, 84)
	_heading(col, "Credits", "IRONLINE " + T.VERSION)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(sc)
	col.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	var entries := [
		["Engine", "Built with Godot Engine 4.7.2 (Compatibility renderer, exported to the web)."],
		["Textures & Sky", "CC0 PBR materials by ambientCG and Poly Haven. HDRI sky by Poly Haven."],
		["Models", "CC0 props by Poly Haven; characters and animation based on Quaternius (CC0)."],
		["Interface", "Touch-control sprites by Kenney (CC0)."],
		["Fonts", "Barlow, Barlow Condensed and Rajdhani, SIL Open Font License 1.1."],
		["Audio", "Procedural and CC0 sound effects."],
		["Thanks", "Everyone who plays, tests and breaks it. See assets/CREDITS.md for the full list."],
	]
	for e in entries:
		v.add_child(T.label(e[0].to_upper(), T.FONT_SEMI, 20, T.C_ACCENT, 4))
		var l := T.label(e[1], T.FONT_BODY_MED, 22, T.C_WHITE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
		_spacer(v, 12)


# ====================================================================== GAME OVER
func _build_game_over() -> void:
	var s := _screen("over")
	var col := _column(s, 900, 50, 92)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 10)
	var bar := T.rect(T.C_RED)
	bar.custom_minimum_size = Vector2(22, 3)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(T.label("MISSION FAILED", T.FONT_SEMI, 20, T.C_RED, 5))
	col.add_child(h)
	_over_title = T.shadow(T.label("K.I.A.", T.FONT_HEAD, 160, T.C_WHITE, 6), 0.6, 18)
	_over_title.add_theme_constant_override("line_spacing", -40)
	col.add_child(_over_title)
	_over_sub = T.label("", T.FONT_SEMI, 24, T.C_DIM, 3)
	col.add_child(_over_sub)
	_spacer(col, 22)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grid)
	for d in [["score", "Score"], ["wave", "Wave Reached"], ["kills", "Kills"], ["headshots", "Headshots"], ["accuracy", "Accuracy"], ["time", "Time Survived"]]:
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.025, 0.03, 0.72)
		sb.border_width_left = 3
		sb.border_color = T.C_ACCENT if d[0] == "score" else Color(1, 1, 1, 0.18)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", sb)
		card.custom_minimum_size = Vector2(232, 0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(v)
		v.add_child(T.label(d[1].to_upper(), T.FONT_SEMI, 18, T.C_DIM, 3))
		var val := T.label("0", T.FONT_NUM, 50, T.C_ACCENT if d[0] == "score" else T.C_WHITE)
		v.add_child(val)
		_over_values[d[0]] = val
		grid.add_child(card)
	_spacer(col, 20, true)
	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(list)
	_over_items = [
		_item(list, "Retry", "", _retry, 40),
		_item(list, "Main Menu", "", _quit_to_menu, 34),
	]
	for b in _over_items:
		b.custom_minimum_size.x = 460
	_chain(_over_items)


func _fmt_time(t: float) -> String:
	var i := int(t)
	return "%02d:%02d" % [i / 60, i % 60]


func _animate_game_over() -> void:
	var st := _over_stats
	_over_sub.text = "YOU WERE KILLED IN ACTION ON WAVE %d" % int(st.get("wave", 0))
	_over_title.modulate = Color(1.6, 0.4, 0.3, 0.0)
	_over_title.scale = Vector2(1.08, 1.08)
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_over_title, "modulate", Color(1, 1, 1, 1), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_over_title, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_over_values, 0.0, 1.0, 1.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_set_over_values(0.0)


func _set_over_values(k: float) -> void:
	var st := _over_stats
	_over_values.score.text = "%d" % roundi(float(st.get("score", 0)) * k)
	_over_values.wave.text = "%d" % roundi(float(st.get("wave", 0)) * k)
	_over_values.kills.text = "%d" % roundi(float(st.get("kills", 0)) * k)
	_over_values.headshots.text = "%d" % roundi(float(st.get("headshots", 0)) * k)
	_over_values.accuracy.text = "%.1f%%" % (float(st.get("accuracy", 0.0)) * k)
	_over_values.time.text = _fmt_time(float(st.get("time", 0.0)) * k)


# ====================================================================== FOOTER / PROMPTS
func _build_footer() -> void:
	var f := HBoxContainer.new()
	f.anchor_left = 0.0
	f.anchor_right = 1.0
	f.anchor_top = 1.0
	f.anchor_bottom = 1.0
	f.offset_top = -62
	f.offset_bottom = -20
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(f)
	footer_left = T.label("IRONLINE %s  ·  %s" % [T.VERSION, "WEB BUILD" if OS.has_feature("web") else OS.get_name().to_upper()], T.FONT_SEMI, 17, T.C_FAINT, 2)
	footer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	f.add_child(footer_left)
	prompts = HBoxContainer.new()
	prompts.add_theme_constant_override("separation", 26)
	prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.add_child(prompts)
	for d in [["tab_prev", "Prev Tab"], ["tab_next", "Next Tab"], ["accept", "Select"], ["back", "Back"]]:
		var b := W.PromptButton.new(d[0], d[1])
		prompts.add_child(b)
		_prompt_buttons[d[0]] = b
	_prompt_buttons.back.pressed.connect(func():
		if is_open() and stack.back() not in ["main", "over"]:
			_back())
	_prompt_buttons.accept.pressed.connect(func():
		var fo := get_viewport().gui_get_focus_owner()
		if fo is BaseButton:
			fo.pressed.emit())
	_prompt_buttons.tab_prev.pressed.connect(func(): _tab_step(-1))
	_prompt_buttons.tab_next.pressed.connect(func(): _tab_step(1))


func _tab_step(d: int) -> void:
	if not is_open():
		return
	T.sound("ui_hover")
	if stack.back() == "settings":
		_select_settings_tab(posmod(_settings_tab + d, _settings_pages.size()), true)
	elif stack.back() == "controls":
		_select_controls_tab(posmod(_controls_tab + d, _controls_pages.size()), true)


func _update_prompts() -> void:
	if prompts == null:
		return
	var top: String = stack.back() if not stack.is_empty() else ""
	var mode := Game.input_mode
	for b in _prompt_buttons.values():
		b.set_mode(mode)
	var tabs := top in ["settings", "controls"]
	_prompt_buttons.tab_prev.visible = tabs
	_prompt_buttons.tab_next.visible = tabs
	_prompt_buttons.accept.visible = top in ["main", "pause", "settings", "over", "confirm"] and mode != "touch"
	_prompt_buttons.back.visible = top in ["settings", "controls", "credits", "confirm", "pause"]
	_prompt_buttons.back.caption = "RESUME" if top == "pause" else "BACK"
	_prompt_buttons.back.set_mode("")
	_prompt_buttons.back.set_mode(mode)
	prompts.visible = top != "title" and top != ""
	if top == "title":
		_title_prompt.text = "TAP TO START" if _is_touchish() else ("PRESS ANY BUTTON" if mode == "pad" else "CLICK OR PRESS ANY KEY")
