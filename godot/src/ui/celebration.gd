class_name Celebration
extends Control
## Annonce plein écran : niveau du roi atteint ou nouvelle arène (diorama de la 16.4 et cartes
## qu'elle débloque). Un toucher ferme.

var kind := ""
var value: Variant


func _ready() -> void:
	theme = Style.theme()
	size = ScreenLayout.size()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.14, 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 24)
	col.size = size
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	if kind == "level":
		col.add_child(Style.title("Niveau du roi", 44))
		var big := Style.title(str(value), 160)
		big.add_theme_color_override("font_color", Style.YELLOW)
		col.add_child(big)
		var sub := Label.new()
		sub.text = "Tes tours sont plus fortes !"
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
		Sounds.play("ui_menu_general", "king_level_up_01")
	else:
		var arena := {}
		for a in GameDB.arenas():
			if a.id == value:
				arena = a
		col.add_child(Style.title("Nouvelle arène !", 48))
		var number := int(arena.get("number", 1))
		var icon := Style.icon("ui_arena", "arena_%02d" % number if number < 10 else "arena_legendary", size.x * 0.6)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(icon)
		col.add_child(Style.title(GameDB.arena_title(arena), 34))
		var cards := HBoxContainer.new()
		cards.alignment = BoxContainer.ALIGNMENT_CENTER
		cards.add_theme_constant_override("separation", 8)
		col.add_child(cards)
		for c in GameDB.cards:
			if int(c.arena) == number:
				var v := CardView.make(c.id, 80, false)
				v.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cards.add_child(v)
		Sounds.play("ui_menu_general", "unlock_tier_01")
	var hint := Label.new()
	hint.text = "Touche pour continuer"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.7
	col.add_child(hint)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			queue_free())
