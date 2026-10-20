class_name ChestOpening
extends Control
## Ouverture d'un coffre : le coffre fermé de la 16.4, puis à chaque toucher une carte (« +N »,
## « Nouvelle carte ! »), enfin le récapitulatif avec l'or.

const ICONS := {"Free": "Chest_wood", "Silver": "Chest_iron", "Gold": "Chest_gold", "Magic": "Chest_magical",
	"Giant": "chest_giant_closed", "Super": "chest_mega_closed", "Epic": "chest_epic_closed",
	"Legendary": "chest_legendary_closed"}

var content := {}
var _step := -1
var _stage := Control.new()
var _hint: Label


func _ready() -> void:
	size = ScreenLayout.size()
	theme = Style.theme()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.12, 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_stage.size = size
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_hint = Label.new()
	_hint.text = "Touche pour ouvrir"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0, size.y * 0.82)
	_hint.size = Vector2(size.x, 50)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	var chest := Style.icon("ui_chest", ICONS.get(content.get("type", ""), "Chest_iron"), size.x * 0.5)
	chest.position = (size - chest.custom_minimum_size) / 2
	_stage.add_child(chest)
	gui_input.connect(_on_input)


func _on_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	_step += 1
	Sounds.play("ui_menu_general", "tap_open_lootbox_01" if _step == 0 else "count_cards_01")
	for c in _stage.get_children():
		c.queue_free()
	var cards: Array = content.get("cards", [])
	if _step < cards.size():
		var c: Dictionary = cards[_step]
		var view := CardView.make(c.id, size.x * 0.42)
		view.position = Vector2((size.x - view.custom_minimum_size.x) / 2, size.y * 0.24)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.scale = Vector2(0.6, 0.6)
		view.pivot_offset = view.custom_minimum_size / 2
		_stage.add_child(view)
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(view, "scale", Vector2.ONE, 0.3)
		var name := Style.title(GameDB.text(GameDB.card(c.id).name), 44)
		name.position = Vector2(0, size.y * 0.14)
		name.size = Vector2(size.x, 60)
		_stage.add_child(name)
		var count := Style.title(("Nouvelle carte !  " if c.get("new", false) else "") + "×%d" % c.n, 54)
		count.add_theme_color_override("font_color", Style.YELLOW if c.get("new", false) else Color.WHITE)
		count.position = Vector2(0, size.y * 0.66)
		count.size = Vector2(size.x, 70)
		_stage.add_child(count)
		_hint.text = "%d / %d" % [_step + 1, cards.size()]
	elif _step == cards.size():
		var gold := Style.title("+%d or" % content.get("gold", 0), 64)
		gold.add_theme_color_override("font_color", Style.YELLOW)
		gold.position = Vector2(0, size.y * 0.4)
		gold.size = Vector2(size.x, 90)
		_stage.add_child(gold)
		_hint.text = "Touche pour continuer"
	else:
		queue_free()
