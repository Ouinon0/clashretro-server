class_name CardPopup
extends Control
## Fiche d'une carte comme dans la 16.4 : grande illustration du personnage (image/chr de la 16.4)
## au-dessus du panneau, carte et jauge, nom et niveau, rareté et type, statistiques au niveau
## actuel, description ; boutons Améliorer (cartes + or, demande au serveur) et Utiliser.

signal use_requested

const HIRES_DIR := "res://assets/gen/chr/"
const PANEL_COLOR := Color("17366e")
const CHIP_COLOR := Color("4f8ff0")

var card_id := ""
var in_deck := false


func _ready() -> void:
	size = ScreenLayout.size()
	var card := GameDB.card(card_id)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.68)
	shade.size = size
	add_child(shade)
	ScUi.make_button(shade, _close, "", false)
	var w := size.x - 36
	var root := Control.new()
	root.size = Vector2(w, 0)
	add_child(root)
	# Illustration (dépasse au-dessus du panneau).
	var art_h := 0.0
	var tex_path := HIRES_DIR + card_id + ".png"
	if ResourceLoader.exists(tex_path):
		var art := TextureRect.new()
		art.texture = load(tex_path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art_h = w * 0.62
		art.size = Vector2(w * 0.86, art_h)
		art.position = Vector2(w * 0.07, 0)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(art)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.position = Vector2(24, art_h * 0.72 + 24)
	body.size = Vector2(w - 48, 0)
	# Carte et en-tête.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	body.add_child(head)
	var view := CardView.make(card_id, 170)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(view)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	head.add_child(right)
	var title := ScUi.label(GameDB.text(card.name), 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(title)
	var level := Player.card_level(card_id)
	var lvl := ScUi.label(GameDB.format("TID_LEVEL", {"LEVEL": GameDB.display_level(card.rarity, level)}), 26, Color("bfe0ff"))
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(lvl)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(chips)
	chips.add_child(_chip("Rareté", GameDB.text("TID_RARITY_" + str(card.rarity).to_upper())))
	chips.add_child(_chip("Type", {"troop": "Combattant", "building": "Bâtiment", "spell": "Sort"}.get(card.type, "")))
	# Statistiques.
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 12)
	stats.add_theme_constant_override("v_separation", 10)
	for pair in _stats(card, level):
		stats.add_child(_stat(pair[0], pair[1], (w - 48 - 12) / 2.0))
	body.add_child(stats)
	var info := GameDB.text(card.info)
	if info != card.info:
		var desc := ScUi.label(info, 20, Color("dbe6f7"), false)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.custom_minimum_size = Vector2(w - 48, 0)
		body.add_child(desc)
	# Boutons.
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	body.add_child(buttons)
	var up := Player.upgrade_info(card_id)
	if not up.is_empty():
		var ok: bool = up.have >= up.cards and int(Player.profile.get("gold", 0)) >= up.gold
		var b := ScUi.text_button("green" if ok else "blue", "Améliorer", Vector2(260, 96), func() -> void:
			if ok:
				Net.send({"t": "upgrade", "card": card_id})
				Sounds.ui("upgrade_card_01")
				_close(), 26)
		if not ok:
			b.modulate = Color(0.7, 0.7, 0.75)
		var price := ScUi.label(str(up.gold), 22, Color("ffe14d"))
		var coin := ScUi.fit_height(ScUi.clip("ui", "icon_gold"), 26)
		var price_row := HBoxContainer.new()
		price_row.alignment = BoxContainer.ALIGNMENT_CENTER
		price_row.add_child(price)
		price_row.add_child(coin)
		price_row.position = Vector2(0, 56)
		price_row.size = Vector2(260, 30)
		b.get_child(1).size.y = 60
		b.add_child(price_row)
		buttons.add_child(b)
	if not in_deck and Player.has_card(card_id):
		buttons.add_child(ScUi.text_button("orange", "Utiliser", Vector2(220, 96), func() -> void:
			use_requested.emit()
			_close(), 28))
	root.add_child(body)
	_layout.call_deferred(root, body, art_h, w)


func _layout(root: Control, body: VBoxContainer, art_h: float, w: float) -> void:
	var body_h := body.get_combined_minimum_size().y
	var panel_top := art_h * 0.72
	var panel := ScUi.panel("ui_common", "bg_r25", Vector2(w, body_h + 48), PANEL_COLOR, 0.9)
	panel.position = Vector2(0, panel_top)
	root.add_child(panel)
	root.move_child(panel, 0 if art_h == 0.0 else 1)
	var x := ScUi.fit_height(ScUi.clip("ui_common", "btn_close"), 56)
	x.position = Vector2(w - 70, panel_top + 14)
	root.add_child(x)
	ScUi.make_button(x, _close)
	var total := panel_top + body_h + 48
	root.position = Vector2(18, maxf(ScreenLayout.top(), (size.y - total) / 2))
	root.pivot_offset = Vector2(w / 2, total / 2)
	root.scale = Vector2.ONE * 0.7
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(root, "scale", Vector2.ONE, 0.2)
	Sounds.ui("scroll_open_01v3333")


func _close() -> void:
	queue_free()


## Pastille « titre / valeur » (Rareté, Type).
func _chip(head: String, value: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var top := ScUi.panel("ui_common", "bg_r6", Vector2(150, 34), CHIP_COLOR, 0.6)
	var t := ScUi.label(head, 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = top.size
	top.add_child(t)
	col.add_child(top)
	var bottom := ScUi.panel("ui_common", "bg_r6", Vector2(150, 38), Color(0.04, 0.1, 0.26), 0.6)
	var v := ScUi.label(value, 18)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.size = bottom.size
	bottom.add_child(v)
	col.add_child(bottom)
	return col


func _stat(name: String, value: String, width: float) -> Control:
	var box := ScUi.panel("ui_common", "bg_r6", Vector2(width, 64), Color(0.08, 0.18, 0.4), 0.6)
	var n := ScUi.label(name, 16, Color("9ec2f5"), false)
	n.position = Vector2(14, 4)
	box.add_child(n)
	var v := ScUi.label(value, 24)
	v.position = Vector2(14, 26)
	box.add_child(v)
	return box


## Statistiques au niveau de la carte (points de vie, dégâts, cadence, portée…).
func _stats(card: Dictionary, level: int) -> Array:
	var out := [["Élixir", str(card.cost)]]
	var row: Dictionary = {}
	if card.type == "troop":
		row = GameDB.character(card.unit)
	elif card.type == "building":
		row = GameDB.building(card.unit)
	if not row.is_empty():
		if row.has("Hitpoints"):
			out.append(["Points de vie", str(Rules.scaled(row.Hitpoints, card.rarity, level))])
		var dmg = row.get("Damage", GameDB.projectile(row.get("Projectile", "")).get("Damage"))
		if dmg != null:
			out.append(["Dégâts", str(Rules.scaled(dmg, card.rarity, level))])
		if row.has("HitSpeed"):
			out.append(["Vitesse d'attaque", "%.1f s" % (row.HitSpeed / 1000.0)])
		if row.has("Range"):
			out.append(["Portée", "%.1f" % (float(row.Range) / 1000.0)])
		if row.has("Speed"):
			var speed := int(row.Speed)
			out.append(["Vitesse", "Très rapide" if speed >= 120 else ("Rapide" if speed >= 90 else ("Moyenne" if speed >= 60 else "Lente"))])
		var count := Rules.num(card.data, "SummonNumber", 1)
		if count > 1:
			out.append(["Nombre", "×%d" % count])
	else:
		var p := GameDB.projectile(card.data.get("Projectile", ""))
		var a := GameDB.area_effect(card.data.get("AreaEffectObject", ""))
		var dmg = p.get("Damage", a.get("Damage"))
		if dmg != null:
			out.append(["Dégâts", str(Rules.scaled(dmg, card.rarity, level))])
		var radius = p.get("Radius", a.get("Radius"))
		if radius != null:
			out.append(["Rayon", "%.1f" % (float(radius) / 1000.0)])
	return out
