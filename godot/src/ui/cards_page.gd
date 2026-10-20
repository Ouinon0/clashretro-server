class_name CardsPage
extends Control
## Onglet Cartes de la 16.4 : onglets « Decks » / « Collection » (deck_builder_top_tabs), deck de
## combat (8 cartes, élixir moyen, tours et niveau du roi), collection (trouvées, puis cartes à
## trouver grisées). Toucher une carte la soulève avec ses boutons (Infos, Utiliser, Améliorer) ;
## « Utiliser » attend le choix de la carte du deck à remplacer.

const COLUMNS := 4
const GAP := 14.0

var _tabs: ScMovieClip
var _scroll := ScrollContainer.new()
var _list := VBoxContainer.new()
var _view := "deck"
var _card_w := 150.0
var _swap_card := ""
var _selection: Control


func _ready() -> void:
	var w := size.x
	_card_w = (w - 48 - (COLUMNS - 1) * GAP) / COLUMNS
	var top := ScreenLayout.top() + TopBar.HEIGHT + 4
	var tabs := ScUi.fit_width(ScUi.clip("ui_deck_builder", "deck_builder_top_tabs"), w * 0.9)
	_tabs = ScUi.node_of(tabs)
	for t in ["tab1", "tab2"]:
		for n in ["notification_purple", "notification_green", "notification_red"]:
			_tabs.set_sc_visible(t + "/" + n, false)
	tabs.position = Vector2((w - tabs.size.x) / 2, top)
	add_child(tabs)
	for pair in [["tab1", "deck"], ["tab2", "collection"]]:
		var hit := Control.new()
		hit.size = Vector2(tabs.size.x / 2, tabs.size.y)
		hit.position = Vector2(0 if pair[0] == "tab1" else tabs.size.x / 2, 0)
		tabs.add_child(hit)
		ScUi.make_button(hit, func() -> void: _show(pair[1]), "menu_click_06", false)
	_scroll.position = Vector2(0, top + tabs.size.y + 4)
	_scroll.size = Vector2(w, size.y - _scroll.position.y)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 40)
	_scroll.add_child(margin)
	_list.add_theme_constant_override("separation", 16)
	margin.add_child(_list)
	Player.changed.connect(_rebuild)
	_show("deck")


func _exit_tree() -> void:
	Player.changed.disconnect(_rebuild)


func _show(view: String) -> void:
	_view = view
	_tabs.get_sc("tab1").goto_and_stop(0 if view == "deck" else 1)
	_tabs.get_sc("tab2").goto_and_stop(0 if view == "collection" else 1)
	_scroll.scroll_vertical = 0
	_rebuild()


func _rebuild() -> void:
	_close_selection()
	for c in _list.get_children():
		c.queue_free()
	if _view == "deck":
		_build_deck()
	else:
		_build_collection()


# --- Deck ----------------------------------------------------------------------------------------

func _build_deck() -> void:
	_list.add_child(_band("Deck de combat", "icon_cards"))
	if _swap_card != "":
		var hint := ScUi.label("Touche la carte à remplacer", 26, Color("ffe14d"))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(hint)
	var deck := Player.deck()
	var grid := _grid()
	for id in deck:
		var v := _card(id)
		grid.add_child(v)
		if _swap_card != "":
			_wiggle(v)
	_list.add_child(grid)
	# Élixir moyen.
	var avg := 0.0
	for id in deck:
		avg += GameDB.card(id).cost
	avg /= maxf(1, deck.size())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var pill := ScUi.panel("ui_common", "bg_r50", Vector2(170, 56), Color(0.05, 0.12, 0.3, 0.85), 0.5)
	var drop := ScUi.fit_height(ScUi.clip("ui", "spell_card_full/elixar_count"), 46)
	ScUi.hide(ScUi.node_of(drop), ["count"])
	drop.position = Vector2(8, 5)
	pill.add_child(drop)
	var avg_label := ScUi.label("%.1f" % avg, 28)
	avg_label.position = Vector2(60, 6)
	avg_label.size = Vector2(100, 44)
	avg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.add_child(avg_label)
	row.add_child(pill)
	_list.add_child(row)
	# Tours : roi au niveau du joueur et princesses.
	var towers := ScUi.fit_width(ScUi.clip("ui_deck_builder", "deck_builder_towers"), size.x - 48)
	var t := ScUi.node_of(towers)
	ScUi.hide(t, ["cosmetics_button", "princess_towers", "towers/king_progress"])
	ScUi.set_any_text(t, "towers/king_tower", str(int(Player.profile.get("level", 1))))
	_list.add_child(towers)


# --- Collection ----------------------------------------------------------------------------------

func _build_collection() -> void:
	var deck := Player.deck()
	var cards := GameDB.cards.duplicate()
	cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := ["Common", "Rare", "Epic", "Legendary"].find(a.rarity)
		var rb := ["Common", "Rare", "Epic", "Legendary"].find(b.rarity)
		return ra < rb if ra != rb else (a.cost < b.cost if a.cost != b.cost else a.id < b.id))
	var owned := cards.filter(func(c: Dictionary) -> bool: return Player.has_card(c.id))
	var header := ScUi.panel("ui_common", "bg_r25", Vector2(size.x - 48, 96), Color(0.04, 0.1, 0.24, 0.8), 0.6)
	var title := ScUi.label(GameDB.text("TID_COLLECTION_CARDS") if GameDB.text("TID_COLLECTION_CARDS") != "TID_COLLECTION_CARDS" else "Cartes possédées", 28)
	title.position = Vector2(20, 10)
	header.add_child(title)
	var found := ScUi.label("Trouvé(es) : %d/%d" % [owned.size(), cards.size()], 20, Color("d48cff"))
	found.position = Vector2(20, 54)
	header.add_child(found)
	_list.add_child(header)
	if _swap_card != "":
		var hint := ScUi.label("Retourne dans Decks pour choisir la carte à remplacer", 20, Color("ffe14d"))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(hint)
	_list.add_child(_divider("Trouvées"))
	var grid := _grid()
	for c in owned:
		if not c.id in deck:
			grid.add_child(_card(c.id))
	_list.add_child(grid)
	var missing := cards.filter(func(c: Dictionary) -> bool: return not Player.has_card(c.id))
	if not missing.is_empty():
		_list.add_child(_divider("Non trouvées"))
		var locked := _grid()
		for c in missing:
			locked.add_child(_card(c.id))
		_list.add_child(locked)


## Bandeau bleu de titre à icône (« Deck de combat »).
func _band(text: String, icon_name: String) -> Control:
	var band := ScUi.panel("ui_common", "bg_r6", Vector2(size.x - 48, 70), Color("2a74e0"), 0.6)
	var shine := ScUi.panel("ui_common", "bg_r6", Vector2(size.x - 56, 30), Color(1, 1, 1, 0.14), 0.4)
	shine.position = Vector2(4, 4)
	band.add_child(shine)
	var icon := ScUi.fit_height(ScUi.clip("ui_deck_builder", icon_name), 84)
	icon.position = Vector2(14, -10)
	band.add_child(icon)
	var label := ScUi.label(text, 30)
	label.position = Vector2(110, 0)
	label.size = Vector2(band.size.x - 120, 70)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band.add_child(label)
	return band


func _divider(text: String) -> Control:
	var d := ScUi.fit_width(ScUi.clip("ui", "collection_card_divider"), size.x - 48)
	ScUi.set_text(ScUi.node_of(d), "TID_UNLOCK_AT_ARENA", text)
	return d


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", int(GAP))
	grid.add_theme_constant_override("v_separation", 18)
	return grid


func _card(id: String) -> CardView:
	var v := CardView.make(id, _card_w)
	v.pressed.connect(func(card_id: String) -> void: _on_card(card_id, v))
	return v


static func _wiggle(v: Control) -> void:
	v.pivot_offset = v.custom_minimum_size / 2
	var t := v.create_tween().set_loops()
	t.tween_property(v, "rotation_degrees", 2.5, 0.12)
	t.tween_property(v, "rotation_degrees", -2.5, 0.12)


# --- Sélection d'une carte ------------------------------------------------------------------------

func _on_card(id: String, view: CardView) -> void:
	var deck := Player.deck()
	if _swap_card != "":
		if id in deck:
			var new_deck := deck.duplicate()
			new_deck[new_deck.find(id)] = _swap_card
			Player.set_deck(new_deck)
			Sounds.ui("card_fly_in_06")
		_swap_card = ""
		_rebuild()
		return
	if not Player.has_card(id):
		_open_info(id)
		return
	_open_selection(id, view)


## Carte soulevée et ses boutons, comme card_selected_panel de la 16.4 ; le reste est assombri.
func _open_selection(id: String, view: CardView) -> void:
	_close_selection()
	var layer := Control.new()
	layer.size = ScreenLayout.size()
	ScUi.popup(self, layer)
	_selection = layer
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.size = layer.size
	layer.add_child(shade)
	ScUi.make_button(shade, _close_selection, "", false)
	var origin := view.global_position
	var w := _card_w * 1.12
	var buttons: Array = [["Infos", "blue", func() -> void:
		_close_selection()
		_open_info(id)]]
	var up := Player.upgrade_info(id)
	if not up.is_empty() and up.have >= up.cards:
		buttons.append(["Améliorer\n%d" % up.gold, "orange", func() -> void:
			_close_selection()
			_open_info(id)])
	if not id in Player.deck():
		buttons.append(["Utiliser", "green", func() -> void:
			_close_selection()
			_swap_card = id
			_show("deck")])
	var panel_h := w * 1.3 + buttons.size() * 74 + 24
	var panel := ScUi.panel("ui_common", "bg_r25", Vector2(w + 24, panel_h), Color("2d6fd6"), 0.6)
	var px := clampf(origin.x - 12 - (w - _card_w) / 2, 8, layer.size.x - w - 32)
	var py := clampf(origin.y - 16, ScreenLayout.top() + TopBar.HEIGHT, layer.size.y - panel_h - 140)
	panel.position = Vector2(px, py)
	layer.add_child(panel)
	var big := CardView.make(id, w, false)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.position = Vector2(12, 12)
	panel.add_child(big)
	var name := ScUi.label(GameDB.text(GameDB.card(id).name), 18)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.position = Vector2(0, big.position.y + big.size.y * 0.6)
	name.size = Vector2(panel.size.x, 24)
	panel.add_child(name)
	for i in buttons.size():
		var b: Array = buttons[i]
		var btn := ScUi.text_button(b[1], b[0], Vector2(w, 64), b[2], 20)
		btn.position = Vector2(12, big.position.y + big.size.y + 10 + i * 74)
		panel.add_child(btn)
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2.ONE * 0.85
	panel.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(panel, "scale", Vector2.ONE, 0.15)
	Sounds.ui("menu_click_06")


func _close_selection() -> void:
	if is_instance_valid(_selection):
		_selection.queue_free()
	_selection = null


func _open_info(id: String) -> void:
	var popup := CardPopup.new()
	popup.card_id = id
	popup.in_deck = id in Player.deck()
	popup.use_requested.connect(func() -> void:
		_swap_card = id
		_show("deck"))
	ScUi.popup(self, popup)
