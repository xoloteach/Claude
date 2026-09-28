extends RefCounted
## Shared look for IRONLINE front-end UI (menus, touch controls): fonts, colours, label + glyph helpers.

const FONT_NUM := "res://assets/fonts/Rajdhani-Bold.ttf"
const FONT_NUM_SEMI := "res://assets/fonts/Rajdhani-SemiBold.ttf"
const FONT_HEAD := "res://assets/fonts/BarlowCondensed-Bold.ttf"
const FONT_SEMI := "res://assets/fonts/BarlowCondensed-SemiBold.ttf"
const FONT_BODY := "res://assets/fonts/Barlow-SemiBold.ttf"
const FONT_BODY_MED := "res://assets/fonts/Barlow-Medium.ttf"
const FONT_REG := "res://assets/fonts/Barlow-Regular.ttf"

const C_WHITE := Color(0.96, 0.96, 0.94)
const C_DIM := Color(0.78, 0.8, 0.78, 0.72)
const C_FAINT := Color(0.78, 0.8, 0.78, 0.35)
const C_ACCENT := Color(1.0, 0.68, 0.2)
const C_ACCENT_DIM := Color(1.0, 0.68, 0.2, 0.35)
const C_RED := Color(0.92, 0.18, 0.14)
const C_PANEL := Color(0.035, 0.04, 0.045, 0.86)

const VERSION := "v0.9.0"

static var _fonts := {}


## Font with optional extra letter spacing (FontVariation), cached.
static func font(path: String, spacing := 0) -> Font:
	var key := "%s#%d" % [path, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var base: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	var f: Font = base
	if spacing != 0:
		var v := FontVariation.new()
		v.base_font = base
		v.spacing_glyph = spacing
		f = v
	_fonts[key] = f
	return f


static func label(text: String, font_path: String, size: int, color := C_WHITE, spacing := 0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(font_path, spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func shadow(l: Label, alpha := 0.6, size := 8) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, alpha))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", size)
	return l


static func rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Glyph text for a UI prompt given the current input family.
## kind: "accept", "back", "tab_prev", "tab_next", "adjust", "reset"
static func prompt_glyph(kind: String, mode: String) -> String:
	if mode == "pad":
		return {"accept": "A", "back": "B", "tab_prev": "LB", "tab_next": "RB", "adjust": "◄►", "reset": "Y"}.get(kind, "?")
	return {"accept": "ENTER", "back": "ESC", "tab_prev": "Q", "tab_next": "E", "adjust": "◄►", "reset": "R"}.get(kind, "?")


## Pad face buttons use the Xbox colour convention so they read at a glance.
static func pad_color(glyph: String) -> Color:
	match glyph:
		"A": return Color(0.35, 0.78, 0.3)
		"B": return Color(0.9, 0.28, 0.24)
		"X": return Color(0.25, 0.55, 0.95)
		"Y": return Color(0.95, 0.78, 0.2)
	return Color(0.85, 0.85, 0.85)


static func stylebox_empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## Strip every default Button/Control stylebox so custom _draw() owns the look.
static func clear_styles(c: Control) -> void:
	for s in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed", "normal_mirrored", "hover_mirrored", "pressed_mirrored", "disabled_mirrored", "hover_pressed_mirrored"]:
		c.add_theme_stylebox_override(s, StyleBoxEmpty.new())


static func sound(n: String) -> void:
	var ml := Engine.get_main_loop() as SceneTree
	var a: Node = ml.root.get_node_or_null("Audio") if ml else null
	if a:
		a.ui(n)


## Hovering with a real mouse moves keyboard/pad focus, so there is only ever one highlight.
static func hook_hover(c: Control) -> void:
	c.mouse_entered.connect(func():
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and not c.has_focus():
			var ml := Engine.get_main_loop() as SceneTree
			var g: Node = ml.root.get_node_or_null("Game") if ml else null
			if g == null or g.input_mode != "touch":
				c.grab_focus())
