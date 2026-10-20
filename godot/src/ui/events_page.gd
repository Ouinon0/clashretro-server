class_name EventsPage
extends Control
## Onglet Événements : actualités et événements programmés par l'admin du serveur (bonus d'or et de
## cartes, modes de jeu : double / triple élixir, niveaux de tournoi, mort subite), avec le temps
## restant et un bouton « Jouer » pour les modes (file d'attente propre à l'événement).

const COLORS := {"blue": Color("2a6fe2"), "purple": Color("8b3fd9"), "gold": Color("d99a1f"),
	"green": Color("2e9e46"), "red": Color("c9343e")}
const MODE_NAMES := {"double_elixir": "Double élixir", "triple_elixir": "Triple élixir",
	"tournament": "Niveaux de tournoi", "sudden_death": "Mort subite", "draft_free": "Combat libre"}

var _list := VBoxContainer.new()
var _timers: Array = []             # [Label, instant, préfixe]


func _ready() -> void:
	var top := ScreenLayout.top() + TopBar.HEIGHT + 6
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, top)
	scroll.size = Vector2(size.x, size.y - top)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_bottom", 40)
	scroll.add_child(margin)
	_list.add_theme_constant_override("separation", 18)
	margin.add_child(_list)
	Player.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	Player.changed.disconnect(_refresh)


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 30 != 0:
		return
	var now := Player.server_now()
	for t in _timers:
		(t[0] as Label).text = t[2] + ShopPage._left(int(t[1]) - now)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_timers.clear()
	var inner := size.x - 40
	var title := ScUi.fit_width(ScUi.clip("ui", "shop_divider"), inner)
	ScUi.set_text(ScUi.node_of(title), "txt", "Événements")
	_list.add_child(title)
	if not Player.online():
		_list.add_child(_note("Connecte-toi à un serveur pour voir ses événements."))
		return
	var now := Player.server_now()
	var events: Array = Player.profile.get("events", [])
	if events.is_empty():
		_list.add_child(_note("Aucun événement pour l'instant. L'admin du serveur peut en programmer."))
	for e: Dictionary in events:
		_list.add_child(_event_card(e, inner, now))
	var news: Array = Player.profile.get("news", [])
	if not news.is_empty():
		var div := ScUi.fit_width(ScUi.clip("ui", "shop_divider"), inner)
		ScUi.set_text(ScUi.node_of(div), "txt", "Actualités")
		_list.add_child(div)
		var items := news.duplicate()
		items.reverse()
		for n: Dictionary in items:
			_list.add_child(_news_card(n, inner))


func _note(text: String) -> Label:
	var l := ScUi.label(text, 22, Color(1, 1, 1, 0.8), false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(size.x - 60, 0)
	return l


func _event_card(e: Dictionary, w: float, now: int) -> Control:
	var color: Color = COLORS.get(str(e.get("color", "blue")), COLORS.blue)
	var started := int(e.get("starts", 0)) <= now
	var mode := str(e.get("mode", ""))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var t := ScUi.label(str(e.get("title", "")), 30)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(w - 40, 0)
	col.add_child(t)
	var when := ScUi.label("", 19, Color(1, 1, 1, 0.85), false)
	col.add_child(when)
	if started:
		if int(e.get("ends", 0)) > 0:
			_timers.append([when, int(e.ends), "Fin dans : "])
		else:
			when.text = "En cours"
	else:
		_timers.append([when, int(e.starts), "Commence dans : "])
	if str(e.get("message", "")) != "":
		var m := ScUi.label(str(e.message), 21, Color.WHITE, false)
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.custom_minimum_size = Vector2(w - 40, 0)
		col.add_child(m)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 10)
	chips.add_theme_constant_override("v_separation", 8)
	chips.custom_minimum_size = Vector2(w - 40, 0)
	if int(e.get("gold_percent", 100)) != 100:
		chips.add_child(_chip("Or ×%s" % _factor(int(e.gold_percent)), "icon_gold"))
	if int(e.get("cards_percent", 100)) != 100:
		chips.add_child(_chip("Cartes ×%s" % _factor(int(e.cards_percent)), ""))
	if mode != "":
		chips.add_child(_chip("%s · %s" % [MODE_NAMES.get(mode, mode), "2 contre 2" if e.get("team", "") == "2v2" else "1 contre 1"], ""))
	if chips.get_child_count() > 0:
		col.add_child(chips)
	if mode != "" and started:
		var play := ScUi.text_button("green", "Jouer", Vector2(260, 84), func() -> void:
			Net.send({"t": "queue", "mode": "ev:" + str(e.id)})
			var menu := get_parent().get_parent() if get_parent() else null
			if menu is MainMenu:
				menu.show_page(MainMenu.BATTLE_PAGE, true), 32)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(w - 40, 90)
		play.position = Vector2((w - 40 - 260) / 2, 4)
		holder.add_child(play)
		col.add_child(holder)
	return _framed(col, w, color)


func _news_card(n: Dictionary, w: float) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var t := ScUi.label(str(n.get("title", "")), 26)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(w - 40, 0)
	col.add_child(t)
	var d := ScUi.label(Time.get_date_string_from_unix_time(int(n.get("at", 0))), 17, Color(1, 1, 1, 0.65), false)
	col.add_child(d)
	if str(n.get("text", "")) != "":
		var m := ScUi.label(str(n.text), 21, Color.WHITE, false)
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.custom_minimum_size = Vector2(w - 40, 0)
		col.add_child(m)
	return _framed(col, w, Color("1d3d78"))


## Contenu posé sur un panneau arrondi de la couleur donnée (hauteur selon le contenu).
func _framed(content: Control, w: float, color: Color) -> Control:
	var box := Control.new()
	var h := content.get_combined_minimum_size().y + 40
	box.custom_minimum_size = Vector2(w, h)
	var bg := ScSlice.make("ui_common", "bg_r25", color, 0.8)
	bg.size = Vector2(w, h)
	box.add_child(bg)
	content.position = Vector2(20, 20)
	box.add_child(content)
	content.resized.connect(func() -> void:
		var nh := content.get_combined_minimum_size().y + 40
		box.custom_minimum_size.y = nh
		bg.size.y = nh)
	return box


func _chip(text: String, icon: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if icon != "":
		row.add_child(ScUi.fit_height(ScUi.clip("ui", icon), 26))
	var l := ScUi.label(text, 19, Color("ffe14d"))
	row.add_child(l)
	var w := ScTextField.font_for("Supercell-Magic").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 34
	if icon != "":
		w += 30
	var box := ScUi.panel("ui_common", "bg_r50", Vector2(w, 40), Color(0, 0, 0, 0.35), 0.4)
	row.position = Vector2(12, 6)
	box.add_child(row)
	return box


static func _factor(percent: int) -> String:
	return str(percent / 100) if percent % 100 == 0 else ("%.1f" % (percent / 100.0)).replace(".", ",")
