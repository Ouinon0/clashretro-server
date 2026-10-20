class_name Style
extends RefCounted
## Thème de l'interface (en attendant tous les éléments de la 16.4) : polices du jeu, boutons
## arrondis à liseré, couleurs du jeu actuel.

const TITLE_FONT := "res://assets/gen/font/supercell-magic_0.ttf"
const BODY_FONT := "res://assets/gen/font/sc_ccbackbeatregular.ttf"
const BLUE := Color("2f7bf2")
const YELLOW := Color("ffc928")
const GREEN := Color("4cc63b")
const DARK := Color("1b2a4a")

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	var body: Font = load(BODY_FONT) if ResourceLoader.exists(BODY_FONT) else null
	if body:
		_theme.default_font = body
	_theme.default_font_size = 30
	_theme.set_color("font_color", "Label", Color.WHITE)
	_theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	_theme.set_constant("outline_size", "Label", 6)
	var field := _box(Color(1, 1, 1, 0.95), Color("8aa0c8"), 14)
	_theme.set_stylebox("normal", "LineEdit", field)
	_theme.set_stylebox("focus", "LineEdit", _box(Color.WHITE, BLUE, 14))
	_theme.set_color("font_color", "LineEdit", DARK)
	_theme.set_font_size("font_size", "LineEdit", 30)
	return _theme


## Bouton du jeu : couleur pleine, liseré sombre, ombre portée, texte en police titre.
static func button(text: String, color: Color, font_size := 40) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if ResourceLoader.exists(TITLE_FONT):
		b.add_theme_font_override("font", load(TITLE_FONT))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("outline_size", 10)
	b.add_theme_stylebox_override("normal", _box(color, color.darkened(0.55), 22, 6))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.08), color.darkened(0.55), 22, 6))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.15), color.darkened(0.6), 22, 2))
	b.add_theme_stylebox_override("disabled", _box(Color(0.5, 0.5, 0.55), Color(0.25, 0.25, 0.3), 22, 6))
	b.pivot_offset = Vector2(0, 0)
	b.button_down.connect(func() -> void: b.scale = Vector2(0.96, 0.96))
	b.button_up.connect(func() -> void: b.scale = Vector2.ONE)
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2)
	return b


## Icône .sc dans un Control de hauteur `height` (centrée, proportions gardées).
static func icon(sc_file: String, export_name: String, height: float) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lib := ScLibrary.get_library(sc_file)
	if not lib.has_export(export_name):
		return holder
	var clip := lib.create_export(export_name)
	var b := ScMovieClip.bounds_of(clip)
	var k := height / maxf(1.0, b.size.y)
	clip.scale = Vector2.ONE * k
	clip.position = -b.position * k
	holder.custom_minimum_size = b.size * k
	holder.add_child(clip)
	return holder


static func title(text: String, font_size := 48) -> Label:
	var l := Label.new()
	l.text = text
	if ResourceLoader.exists(TITLE_FONT):
		l.add_theme_font_override("font", load(TITLE_FONT))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _box(color: Color, border: Color, radius: int, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(4)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 14
	s.content_margin_bottom = 14 + shadow
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = shadow
	s.shadow_offset = Vector2(0, shadow)
	return s
