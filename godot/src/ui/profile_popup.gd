class_name ProfilePopup
extends Control
## Profil : niveau du roi et expérience, trophées et record, victoires / défaites, route des
## arènes (seuil de trophées, cartes débloquées, arène actuelle en surbrillance).


func _ready() -> void:
	theme = Style.theme()
	size = ScreenLayout.size()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("16305e")
	box.border_color = Color("6b9be6")
	box.set_border_width_all(4)
	box.set_corner_radius_all(28)
	box.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", box)
	panel.position = Vector2(20, ScreenLayout.top() + 20)
	panel.size = Vector2(size.x - 40, size.y - ScreenLayout.top() - ScreenLayout.bottom() - 40)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var p := Player.profile
	var head := HBoxContainer.new()
	col.add_child(head)
	var name := Style.title(p.get("name", ""), 42)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(name)
	var close := Style.button("Fermer", Color("e0463c"), 24)
	close.pressed.connect(queue_free)
	head.add_child(close)
	col.add_child(level_bar(p, size.x - 84))
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 30)
	col.add_child(stats)
	for s in [["Trophées", p.get("trophies", 0)], ["Record", p.get("best", 0)], ["Victoires", p.get("wins", 0)],
			["Défaites", p.get("losses", 0)], ["Cartes trouvées", "%d / %d" % [p.get("cards", {}).size(), GameDB.cards.size()]]]:
		var k := Label.new()
		k.text = s[0]
		k.modulate.a = 0.8
		stats.add_child(k)
		var v := Label.new()
		v.text = str(s[1])
		v.add_theme_color_override("font_color", Style.YELLOW)
		stats.add_child(v)
	col.add_child(Style.title("Route des arènes", 34))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var road := VBoxContainer.new()
	road.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	road.add_theme_constant_override("separation", 12)
	scroll.add_child(road)
	var current: String = p.get("arena", "")
	for a in GameDB.arenas():
		road.add_child(_arena_row(a, a.id == current, int(p.get("trophies", 0)) >= int(a.trophies)))


## Niveau du roi et barre d'expérience (aussi utilisée par l'accueil).
static func level_bar(p: Dictionary, width: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var level := Style.title("Niv. %d" % int(p.get("level", 1)), 28)
	level.add_theme_color_override("font_color", Color("9fd0ff"))
	row.add_child(level)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width * 0.5, 26)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var levels: Array = GameDB.table("exp_levels")
	var need := int(levels[clampi(int(p.get("level", 1)) - 1, 0, levels.size() - 1)])
	bar.max_value = maxi(1, need)
	bar.value = int(p.get("exp", 0))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.06, 0.14)
	bg.set_corner_radius_all(10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("3f8cf0")
	fill.set_corner_radius_all(10)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var txt := Label.new()
	txt.text = "%d / %d" % [int(p.get("exp", 0)), need] if int(p.get("level", 1)) < 13 else "Max"
	txt.add_theme_font_size_override("font_size", 22)
	row.add_child(txt)
	return row


func _arena_row(a: Dictionary, current: bool, reached: bool) -> Control:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.2, 0.32, 0.55, 0.9) if current else Color(0.08, 0.15, 0.3, 0.85)
	box.border_color = Style.YELLOW if current else Color("33558f")
	box.set_border_width_all(3)
	box.set_corner_radius_all(18)
	box.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", box)
	panel.modulate = Color.WHITE if reached else Color(0.65, 0.65, 0.7)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var number := int(a.number)
	row.add_child(Style.icon("ui_arena", "arena_%02d" % number if number < 10 else "arena_legendary", 96))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var t := Label.new()
	t.text = "%s\n%d trophées" % [GameDB.arena_title(a), int(a.trophies)]
	t.add_theme_font_size_override("font_size", 24)
	info.add_child(t)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 4)
	info.add_child(cards)
	for c in GameDB.cards:
		if int(c.arena) == number:
			var v := CardView.make(c.id, 46, false)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cards.add_child(v)
	return panel
