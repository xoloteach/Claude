extends RefCounted
## Custom-drawn, focus-driven menu widgets (mouse, keyboard, gamepad and touch friendly).
##   MenuItem     big condensed uppercase entry with sliding accent bar (main / pause / game-over lists)
##   SettingRow   slider or selector row, adjustable with left/right, click, drag or tap
##   TabButton    settings / controls tab header
##   PromptButton footer prompt: [glyph] LABEL, clickable

const T := preload("res://scripts/ui/ui_theme.gd")


# ====================================================================== MenuItem
class MenuItem extends Button:
	var caption := ""
	var desc := ""
	var font_size := 34
	var danger := false
	var silent_focus := false   # set by owner to suppress the hover blip on programmatic focus
	var _hl := 0.0
	var _flash := 0.0

	func _init(cap: String, description := "", size_px := 34) -> void:
		caption = cap.to_upper()
		desc = description
		font_size = size_px
		text = ""
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(430, size_px + 26)
		T.clear_styles(self)
		focus_entered.connect(func():
			if not silent_focus:
				T.sound("ui_hover")
			silent_focus = false)
		pressed.connect(func(): _flash = 1.0)
		T.hook_hover(self)

	func _process(delta: float) -> void:
		var target := 1.0 if (has_focus() and not disabled) else 0.0
		var prev := _hl
		_hl = move_toward(_hl, target, delta * 7.0)
		_flash = maxf(0.0, _flash - delta * 4.0)
		if prev != _hl or _flash > 0.0:
			queue_redraw()

	func _draw() -> void:
		var s := size
		var k := _hl * _hl * (3.0 - 2.0 * _hl)
		# gradient highlight sweeping in from the left
		if k > 0.001:
			var w := s.x * (0.35 + 0.65 * k)
			var c0 := Color(1, 1, 1, 0.13 * k) if not danger else Color(1, 0.3, 0.2, 0.16 * k)
			var c1 := Color(1, 1, 1, 0.0)
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, s.y), Vector2(0, s.y)]),
				PackedColorArray([c0, c1, c1, c0]))
			# accent bar grows from the centre
			var bh := s.y * k
			draw_rect(Rect2(0, (s.y - bh) * 0.5, 4, bh), T.C_ACCENT if not danger else T.C_RED)
			# hairlines
			draw_rect(Rect2(0, 0, w * 0.8, 1), Color(1, 1, 1, 0.08 * k))
			draw_rect(Rect2(0, s.y - 1, w * 0.8, 1), Color(1, 1, 1, 0.08 * k))
		if _flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, s), Color(1, 0.8, 0.5, 0.18 * _flash))
		var f := T.font(T.FONT_HEAD, 1)
		var col := T.C_DIM.lerp(T.C_WHITE, k)
		if disabled:
			col = T.C_FAINT
		var asc := f.get_ascent(font_size)
		var desc_h := f.get_descent(font_size)
		var y := (s.y + asc - desc_h) * 0.5
		var x := 22.0 + 14.0 * k
		draw_string(f, Vector2(x + 1, y + 2), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.45))
		draw_string(f, Vector2(x, y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
		# chevron on the right when highlighted
		if k > 0.01:
			var cx := s.x - 26.0 + 8.0 * (1.0 - k)
			var cy := s.y * 0.5
			var a := Color(T.C_ACCENT.r, T.C_ACCENT.g, T.C_ACCENT.b, k)
			draw_polyline(PackedVector2Array([Vector2(cx - 5, cy - 8), Vector2(cx + 3, cy), Vector2(cx - 5, cy + 8)]), a, 2.5, true)


# ====================================================================== SettingRow
class SettingRow extends Control:
	signal value_changed(v)

	var caption := ""
	var desc := ""
	var kind := "slider"         # "slider" | "select"
	var min_v := 0.0
	var max_v := 1.0
	var step := 0.05
	var value := 0.0
	var options: Array = []      # for select
	var formatter: Callable      # float -> String
	var silent_focus := false
	var _hl := 0.0
	var _drag := false
	var _hold_t := 0.0
	var _hold_dir := 0
	var _last_tick := 0

	const BAR_W := 300.0
	const VAL_W := 86.0

	func _init(cap: String, description := "") -> void:
		caption = cap.to_upper()
		desc = description
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(640, 58)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_entered.connect(func():
			if not silent_focus:
				T.sound("ui_hover")
			silent_focus = false
			queue_redraw())
		focus_exited.connect(func():
			_drag = false
			_hold_dir = 0)
		T.hook_hover(self)

	func setup_slider(lo: float, hi: float, st: float, v: float, fmt: Callable) -> SettingRow:
		kind = "slider"
		min_v = lo; max_v = hi; step = st; formatter = fmt
		value = clampf(v, lo, hi)
		return self

	func setup_select(opts: Array, idx: int) -> SettingRow:
		kind = "select"
		options = opts
		value = clampi(idx, 0, opts.size() - 1)
		return self

	func set_value_silent(v) -> void:
		value = clampf(v, min_v, max_v) if kind == "slider" else clampi(int(v), 0, options.size() - 1)
		queue_redraw()

	func _control_rect() -> Rect2:
		# right-hand control area
		var w := BAR_W + VAL_W + 20.0
		return Rect2(size.x - w - 16.0, 0, w, size.y)

	func _bar_rect() -> Rect2:
		var r := _control_rect()
		return Rect2(r.position.x, size.y * 0.5 - 3, BAR_W, 6)

	func _nudge(dir: int) -> void:
		if kind == "slider":
			var nv := clampf(snappedf(value + step * dir, step), min_v, max_v)
			if nv != value:
				value = nv
				_emit()
		else:
			var n := options.size()
			value = posmod(int(value) + dir, n)
			_emit()

	func _emit() -> void:
		queue_redraw()
		var now := Time.get_ticks_msec()
		if now - _last_tick > 45:
			_last_tick = now
			T.sound("ui_hover")
		value_changed.emit(value if kind == "slider" else int(value))

	func _set_from_x(x: float) -> void:
		var b := _bar_rect()
		var t := clampf((x - b.position.x) / b.size.x, 0.0, 1.0)
		var nv := clampf(snappedf(lerpf(min_v, max_v, t), step), min_v, max_v)
		if nv != value:
			value = nv
			_emit()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus()
				if kind == "slider":
					var b := _bar_rect().grow_individual(12, 22, 12, 22)
					if b.has_point(event.position):
						_drag = true
						_set_from_x(event.position.x)
				else:
					var cr := _control_rect()
					if event.position.x < cr.position.x + 40.0 and event.position.x > cr.position.x - 10.0:
						_nudge(-1)
					else:
						_nudge(1)
				accept_event()
			else:
				_drag = false
		elif event is InputEventMouseMotion and _drag:
			_set_from_x(event.position.x)
			accept_event()
		elif event.is_action_pressed("ui_left", false) and not event.is_echo():
			_nudge(-1); _hold_dir = -1; _hold_t = 0.0
			accept_event()
		elif event.is_action_pressed("ui_right", false) and not event.is_echo():
			_nudge(1); _hold_dir = 1; _hold_t = 0.0
			accept_event()
		elif event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true):
			accept_event()   # swallow key echo; repeat is timed in _process
		elif event.is_action_pressed("ui_accept") and kind == "select":
			_nudge(1)
			accept_event()

	func _process(delta: float) -> void:
		var target := 1.0 if has_focus() else 0.0
		if _hl != target:
			_hl = move_toward(_hl, target, delta * 8.0)
			queue_redraw()
		if _hold_dir != 0:
			var held := Input.is_action_pressed("ui_left") if _hold_dir < 0 else Input.is_action_pressed("ui_right")
			if not held or not has_focus():
				_hold_dir = 0
			else:
				_hold_t += delta
				if _hold_t > 0.38:
					_hold_t -= 0.055
					if kind == "slider":
						_nudge(_hold_dir)

	func _draw() -> void:
		var s := size
		var k := _hl
		if k > 0.001:
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)]),
				PackedColorArray([Color(1, 1, 1, 0.1 * k), Color(1, 1, 1, 0.02 * k), Color(1, 1, 1, 0.02 * k), Color(1, 1, 1, 0.1 * k)]))
			draw_rect(Rect2(0, 0, 3, s.y), Color(T.C_ACCENT.r, T.C_ACCENT.g, T.C_ACCENT.b, k))
		else:
			draw_rect(Rect2(0, 0, s.x, s.y), Color(0, 0, 0, 0.22))
		draw_rect(Rect2(0, s.y - 1, s.x, 1), Color(1, 1, 1, 0.05))
		var f := T.font(T.FONT_SEMI, 1)
		var fs := 25
		var y := (s.y + f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		draw_string(f, Vector2(20 + 6 * k, y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, T.C_DIM.lerp(T.C_WHITE, k))
		var cr := _control_rect()
		var nf := T.font(T.FONT_NUM)
		if kind == "slider":
			var b := _bar_rect()
			var t := inverse_lerp(min_v, max_v, value)
			draw_rect(b, Color(1, 1, 1, 0.14))
			draw_rect(Rect2(b.position, Vector2(b.size.x * t, b.size.y)), T.C_ACCENT if k > 0.5 else Color(0.9, 0.9, 0.88, 0.85))
			# tick marks
			for i in 11:
				var tx := b.position.x + b.size.x * i / 10.0
				draw_rect(Rect2(tx, b.position.y + b.size.y + 3, 1, 3 if i % 5 else 5), Color(1, 1, 1, 0.18))
			var kx := b.position.x + b.size.x * t
			draw_rect(Rect2(kx - 3, b.position.y - 8, 6, b.size.y + 16), T.C_WHITE)
			var txt: String = formatter.call(value) if formatter.is_valid() else str(value)
			var tw := nf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			var vx := cr.position.x + BAR_W + 20.0 + VAL_W - tw
			draw_string(nf, Vector2(vx, (s.y + nf.get_ascent(26) - nf.get_descent(26)) * 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, T.C_WHITE)
		else:
			var txt2: String = str(options[int(value)]).to_upper()
			var hf := T.font(T.FONT_HEAD, 1)
			var hs := 25
			var cx := cr.position.x + cr.size.x * 0.5
			var tw2 := hf.get_string_size(txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
			draw_string(hf, Vector2(cx - tw2 * 0.5, (s.y + hf.get_ascent(hs) - hf.get_descent(hs)) * 0.5 - 3), txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, T.C_WHITE)
			var ac := T.C_ACCENT if k > 0.5 else Color(1, 1, 1, 0.45)
			var cy := s.y * 0.5 - 3
			var lx := cr.position.x + 14.0
			var rx := cr.position.x + cr.size.x - 14.0
			draw_colored_polygon(PackedVector2Array([Vector2(lx + 7, cy - 8), Vector2(lx - 3, cy), Vector2(lx + 7, cy + 8)]), ac)
			draw_colored_polygon(PackedVector2Array([Vector2(rx - 7, cy - 8), Vector2(rx + 3, cy), Vector2(rx - 7, cy + 8)]), ac)
			# option pips
			var n := options.size()
			var pw := 22.0
			var gap := 5.0
			var total := n * pw + (n - 1) * gap
			for i in n:
				var px := cx - total * 0.5 + i * (pw + gap)
				draw_rect(Rect2(px, s.y - 13, pw, 3), T.C_ACCENT if i == int(value) else Color(1, 1, 1, 0.2))


# ====================================================================== TabButton
class TabButton extends Button:
	var caption := ""
	var selected := false
	var _hl := 0.0

	func _init(cap: String) -> void:
		caption = cap.to_upper()
		text = ""
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		T.clear_styles(self)
		var f := T.font(T.FONT_HEAD, 2)
		custom_minimum_size = Vector2(f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 40, 46)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _process(delta: float) -> void:
		var target := 1.0 if selected else (0.4 if is_hovered() else 0.0)
		if _hl != target:
			_hl = move_toward(_hl, target, delta * 8.0)
			queue_redraw()

	func _draw() -> void:
		var f := T.font(T.FONT_HEAD, 2)
		var fs := 24
		var tw := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col := T.C_DIM.lerp(T.C_WHITE, _hl)
		if selected:
			draw_rect(Rect2(0, 0, size.x, size.y), Color(1, 1, 1, 0.06))
		draw_string(f, Vector2((size.x - tw) * 0.5, (size.y + f.get_ascent(fs) - f.get_descent(fs)) * 0.5), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var uw := size.x * _hl
		draw_rect(Rect2((size.x - uw) * 0.5, size.y - 3, uw, 3), T.C_ACCENT)


# ====================================================================== PromptButton
class PromptButton extends Button:
	var kind := ""
	var caption := ""
	var mode := "kbm"

	func _init(k: String, cap: String) -> void:
		kind = k
		caption = cap.to_upper()
		text = ""
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		T.clear_styles(self)
		_resize()
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func set_mode(m: String) -> void:
		if m != mode:
			mode = m
			_resize()
			queue_redraw()

	func _glyph() -> String:
		return T.prompt_glyph(kind, mode)

	func _resize() -> void:
		var f := T.font(T.FONT_SEMI, 1)
		var gw := _glyph_w()
		custom_minimum_size = Vector2(gw + (12 if mode == "touch" else 10) + f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 8, 40)

	func _glyph_w() -> float:
		if mode == "touch":
			return 0.0
		var g := _glyph()
		if mode == "pad" and g.length() == 1:
			return 28.0
		var nf := T.font(T.FONT_NUM)
		return nf.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16.0

	func _draw() -> void:
		var cy := size.y * 0.5
		var x := 0.0
		var g := _glyph()
		var gw := _glyph_w()
		if mode == "pad" and g.length() == 1:
			var pc := T.pad_color(g)
			draw_circle(Vector2(x + 14, cy), 13, Color(0.08, 0.08, 0.09, 0.9))
			draw_arc(Vector2(x + 14, cy), 13, 0, TAU, 32, pc, 2.0, true)
			var nf := T.font(T.FONT_NUM)
			var w := nf.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(nf, Vector2(x + 14 - w * 0.5, cy + 6), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, pc)
		elif mode != "touch":
			var nf2 := T.font(T.FONT_NUM)
			var r := Rect2(x, cy - 13, gw, 26)
			draw_rect(r, Color(0.9, 0.9, 0.88, 0.92))
			var w2 := nf2.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(nf2, Vector2(x + (gw - w2) * 0.5, cy + 6), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.06, 0.06, 0.07))
		x += gw + (10.0 if gw > 0.0 else 0.0)
		var f := T.font(T.FONT_SEMI, 1)
		var col := T.C_WHITE if is_hovered() else Color(0.9, 0.9, 0.88, 0.85)
		if mode == "touch":
			draw_rect(Rect2(0, 2, size.x, size.y - 4), Color(1, 1, 1, 0.08))
			draw_rect(Rect2(0, 2, 3, size.y - 4), T.C_ACCENT)
			x = 12.0
		draw_string(f, Vector2(x, cy + 8), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, col)
