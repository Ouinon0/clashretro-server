class_name ClanChat
extends Control
## Discussion du clan en plein écran (violet de la 16.4) : messages, demandes de cartes avec
## « Donner », saisie, « Demander » (communes et rares possédées), membres et départ du clan.

const PURPLE := Color("4532a6")

var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _input: LineEdit


func _ready() -> void:
	size = ScreenLayout.size()
	var bg := ColorRect.new()
	bg.color = Color("2b1f6e")
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var top := ScreenLayout.top()
	var head := ScUi.panel("ui_common", "bg_r16", Vector2(size.x, top + 96), PURPLE, 0.6)
	head.position = Vector2(0, -16)
	add_child(head)
	var title := ScUi.label(Player.clan.get("name", "Clan"), 32)
	title.position = Vector2(24, top + 10)
	title.size = Vector2(size.x - 320, 60)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true
	add_child(title)
	var members := ScUi.text_button("blue", "%d membres" % Player.clan.get("members", []).size(), Vector2(200, 60), _show_members, 20)
	members.position = Vector2(size.x - 290, top + 10)
	add_child(members)
	var x := ScUi.fit_height(ScUi.clip("ui_common", "btn_close"), 58)
	x.position = Vector2(size.x - 76, top + 12)
	add_child(x)
	ScUi.make_button(x, queue_free)
	var bottom_h := 100.0 + ScreenLayout.bottom()
	_scroll.position = Vector2(16, top + 92)
	_scroll.size = Vector2(size.x - 32, size.y - top - 92 - bottom_h)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	_list.add_theme_constant_override("separation", 10)
	_list.custom_minimum_size = Vector2(_scroll.size.x, 0)
	_scroll.add_child(_list)
	var bar := ScUi.panel("ui_common", "bg_r16", Vector2(size.x, bottom_h + 20), PURPLE, 0.6)
	bar.position = Vector2(0, size.y - bottom_h)
	add_child(bar)
	var ask := ScUi.text_button("orange", "Demander", Vector2(170, 72), _pick_request, 20)
	ask.position = Vector2(12, 14)
	bar.add_child(ask)
	_input = Popup16.field("")
	_input.placeholder_text = "Message"
	_input.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_input.position = Vector2(192, 14)
	_input.size = Vector2(size.x - 192 - 162, 72)
	_input.text_submitted.connect(func(_t: String) -> void: _send())
	bar.add_child(_input)
	var send := ScUi.text_button("green", "Envoyer", Vector2(140, 72), _send, 20)
	send.position = Vector2(size.x - 152, 14)
	bar.add_child(send)
	Player.clan_changed.connect(_refresh)
	Player.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	Player.clan_changed.disconnect(_refresh)
	Player.changed.disconnect(_refresh)


func _refresh() -> void:
	if Player.clan.is_empty():
		queue_free()
		return
	for c in _list.get_children():
		c.queue_free()
	for m: Dictionary in Player.clan.get("chat", []):
		_list.add_child(_message(m))
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _send() -> void:
	if _input.text.strip_edges() != "":
		Net.send({"t": "clan_say", "text": _input.text})
		_input.text = ""


func _message(m: Dictionary) -> Control:
	var w := _list.custom_minimum_size.x
	var mine: bool = int(m.get("from", -1)) == int(Player.profile.get("id", -2))
	if m.k == "info":
		var l := ScUi.label(str(m.text), 18, Color(1, 1, 1, 0.7), false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(w, 30)
		return l
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var who := ScUi.label(str(m.get("name", "")), 20, Color("ffd94a"))
	col.add_child(who)
	if m.k == "msg":
		var l := ScUi.label(str(m.text), 21, Color("2c3a57"), false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(w * 0.78 - 32, 0)
		col.add_child(l)
		who.label_settings.font_color = Color("4a3bb0")
		who.label_settings.outline_size = 0
		who.label_settings.shadow_size = 0
		who.label_settings.shadow_color = Color(0, 0, 0, 0)
	else:
		# Demande de cartes : carte, progression, « Donner ».
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		col.add_child(row)
		var card := CardView.make(m.card, 96, false)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(card)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 8)
		row.add_child(info)
		info.add_child(ScUi.label("Demande : %d / %d" % [int(m.got), int(m.need)], 22))
		if not mine and not m.get("closed", false):
			var have := int(Player.profile.get("cards", {}).get(m.card, {"n": 0}).n)
			var id := int(m.id)
			var give := ScUi.text_button("green" if have > 0 else "blue", "Donner (%d)" % have, Vector2(220, 64), func() -> void:
				if have > 0:
					Net.send({"t": "clan_donate", "id": id})
					Sounds.ui("donate_01"), 20)
			info.add_child(give)
	var bw := w * 0.78 if m.k == "msg" else w
	var box := Control.new()
	var h := col.get_combined_minimum_size().y + 28
	box.custom_minimum_size = Vector2(w, h)
	var bubble := ScSlice.make("ui_common", "bg_r25", Color("f2f4fb") if m.k == "msg" else Color("6d58db"), 0.6)
	bubble.size = Vector2(bw, h)
	bubble.position.x = w - bw if mine else 0.0
	box.add_child(bubble)
	col.position = Vector2(bubble.position.x + 16, 14)
	box.add_child(col)
	return box


## Choix de la carte à demander : communes et rares possédées.
func _pick_request() -> void:
	var popup := Popup16.make("Demander des cartes", size.x - 30)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var cw := (size.x - 30 - 60 - 30) / 4.0
	for c in GameDB.cards:
		if c.rarity in ["Common", "Rare"] and Player.profile.get("cards", {}).has(c.id):
			var v := CardView.make(c.id, cw, false)
			var id: String = c.id
			v.pressed.connect(func(_id: String) -> void:
				Net.send({"t": "clan_request", "card": id})
				popup.close())
			grid.add_child(v)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(size.x - 90, minf(size.y * 0.6, grid.get_combined_minimum_size().y + 20))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(grid)
	popup.content.add_child(scroll)
	add_child(popup)


func _show_members() -> void:
	var popup := Popup16.make("Membres", size.x - 60)
	for m: Dictionary in Player.clan.get("members", []):
		var l := Popup16.text("%s%s — %d trophées" % [m.name, " (chef)" if m.leader else "", int(m.trophies)], 22)
		popup.content.add_child(l)
	popup.content.add_child(Popup16.buttons([["Quitter le clan", "red", func() -> void:
		Net.send({"t": "clan_leave"})
		popup.close()
		queue_free()]]))
	add_child(popup)
