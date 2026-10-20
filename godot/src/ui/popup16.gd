class_name Popup16
extends Control
## Fenêtre de la 16.4 : cadre ardoise (bg_window9s), corps clair (bg_popup_01_1), titre blanc et
## croix rouge (btn_close) ; ouverture en rebond, fond assombri. Le contenu va dans `content`.

const TEXT_COLOR := Color("2c3a57")

var content := VBoxContainer.new()
var title := ""
var width := 600.0
var closable := true
var frame := Control.new()
var _built := false


static func make(popup_title: String, popup_width: float, can_close := true) -> Popup16:
	var p := Popup16.new()
	p.title = popup_title
	p.width = popup_width
	p.closable = can_close
	p.content.add_theme_constant_override("separation", 14)
	return p


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = ScreenLayout.size()
	position = -get_parent().global_position if get_parent() is Control else Vector2.ZERO
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.size = size
	add_child(shade)
	if closable:
		ScUi.make_button(shade, close, "", false)
	add_child(frame)
	content.position = Vector2(30, 96)
	content.custom_minimum_size = Vector2(width - 60, 0)
	content.size = Vector2(width - 60, 0)
	_layout.call_deferred()
	Sounds.ui("scroll_open_01v3333")


var _outer: ScSlice
var _body: ScSlice
var _title_label: Label
var _close_button: Control


func _layout() -> void:
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_outer = ScSlice.make("ui_common", "bg_window9s", Color.WHITE, 1.2)
	frame.add_child(_outer)
	_body = ScSlice.make("ui_common", "bg_popup_01_1", Color.WHITE, 1.0)
	_body.position = Vector2(12, 78)
	frame.add_child(_body)
	_title_label = ScUi.label(title, 34)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(60, 14)
	_title_label.size = Vector2(width - 120, 50)
	frame.add_child(_title_label)
	if closable:
		_close_button = ScUi.fit_height(ScUi.clip("ui_common", "btn_close"), 54)
		_close_button.position = Vector2(width - _close_button.size.x - 14, 12)
		frame.add_child(_close_button)
		ScUi.make_button(_close_button, close)
	frame.add_child(content)
	content.size = Vector2(width - 60, 0)
	_resize()
	content.minimum_size_changed.connect(_resize.call_deferred)
	frame.pivot_offset = frame.size / 2
	frame.scale = Vector2.ONE * 0.6
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(frame, "scale", Vector2.ONE, 0.22)


## Hauteur selon le contenu (limitée à l'écran) ; la fenêtre reste centrée.
func _resize() -> void:
	if not is_instance_valid(_outer):
		return
	var h := minf(content.get_combined_minimum_size().y + 96 + 34, size.y - ScreenLayout.top() - 20)
	frame.size = Vector2(width, h)
	frame.position = (size - frame.size) / 2
	frame.pivot_offset = frame.size / 2
	_outer.size = frame.size
	_body.size = Vector2(width - 24, h - 92)


func close() -> void:
	Sounds.ui("scroll_close_08")
	queue_free()


## Texte du corps (police du jeu, foncé, retour à la ligne).
static func text(s: String, font_size := 24, color := TEXT_COLOR) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = ScTextField.font_for("Supercell-Magic")
	ls.font_size = font_size
	ls.font_color = color
	l.label_settings = ls
	return l


## Champ de saisie blanc aux coins arrondis.
static func field(value: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(0, 72)
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = Color.WHITE
	box.border_color = Color("9fb3d1")
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.content_margin_left = 16
	box.content_margin_right = 16
	e.add_theme_stylebox_override("normal", box)
	var focus := box.duplicate()
	focus.border_color = Color("3b8df0")
	e.add_theme_stylebox_override("focus", focus)
	e.add_theme_color_override("font_color", TEXT_COLOR)
	e.add_theme_font_override("font", ScTextField.font_for("Supercell-Magic"))
	e.add_theme_font_size_override("font_size", 26)
	return e


## Rangée de boutons [texte, couleur (blue, green, red, orange, purple), action].
static func buttons(list: Array, height := 84.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	var w := minf(300.0, 520.0 / list.size())
	for b in list:
		row.add_child(ScUi.text_button(b[1], b[0], Vector2(w, height), b[2]))
	return row
