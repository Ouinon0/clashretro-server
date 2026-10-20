class_name ScTextField
extends Node2D
## Champ texte .sc. Conventions du moteur d'origine :
## - une instance nommée « TID_XXX » affiche la traduction de TID_XXX (texts.csv) ;
## - suffixe « _vcenter » : centrage vertical ; « _noscale » : pas de réduction automatique ;
## - sinon le texte est réduit jusqu'à tenir dans le cadre.

const FONTS := {
	"Supercell-Magic": "res://assets/gen/font/supercell-magic_0.ttf",
	"SC CCBackBeat": "res://assets/gen/font/sc_ccbackbeatregular.ttf",
	"CCBackBeat Light": "res://assets/gen/font/sc_ccbackbeatregular.ttf",
	"CCBattleCry": "res://assets/gen/font/supercell-magic_0.ttf",
}

static var _fonts := {}

var label := Label.new()
var vcenter := false
var autoscale := true
var _base_size := 16
var _settings := LabelSettings.new()


static func clear_cache() -> void:
	_fonts.clear()


static func font_for(font_name: String) -> Font:
	var path: String = FONTS.get(font_name, FONTS["Supercell-Magic"])
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]


static func argb(value: int) -> Color:
	return Color8((value >> 16) & 255, (value >> 8) & 255, value & 255, (value >> 24) & 255)


func _init(data: Dictionary, instance_name: String = "") -> void:
	var b: Array = data.bounds
	label.position = Vector2(b[0], b[1])
	label.size = Vector2(b[2] - b[0], b[3] - b[1])
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base_size = int(data.size)
	_settings.font = font_for(data.font)
	_settings.font_size = _base_size
	_settings.font_color = argb(int(data.color))
	_settings.line_spacing = -_base_size * 0.15
	if data.outline != null:
		_settings.outline_color = argb(int(data.outline))
		_settings.outline_size = maxi(2, _base_size / 6)
		# Ombre portée sous le contour, comme les titres du jeu.
		_settings.shadow_color = Color(_settings.outline_color, 0.9)
		_settings.shadow_size = 0
		_settings.shadow_offset = Vector2(0, maxf(1.0, _base_size / 12.0))
	label.label_settings = _settings
	match int(data.align) & 0x0F:
		1: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		2: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if data.wordwrap or data.multiline else TextServer.AUTOWRAP_OFF
	add_child(label)

	var lower := instance_name.to_lower()
	vcenter = lower.ends_with("_vcenter") or lower.contains("_vcenter_")
	autoscale = not lower.contains("_noscale")
	if vcenter:
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if instance_name.begins_with("TID_"):
		set_text(GameDB.text(instance_name.replace("_vcenter", "").replace("_noscale", "")))
	elif data.text != null:
		set_text(data.text)


func set_text(text: String) -> void:
	label.text = text
	_settings.font_size = _base_size
	if not autoscale or text == "" or label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return
	var width := _settings.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _base_size).x
	if width > label.size.x and width > 0:
		_settings.font_size = maxi(6, int(_base_size * label.size.x / width))


## Largeur du texte affiché (px, repère du champ).
func text_width() -> float:
	return _settings.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _settings.font_size).x


func get_text() -> String:
	return label.text
