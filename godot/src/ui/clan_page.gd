class_name ClanPage
extends Control
## Onglet Social de la 16.4 : carte du clan en haut (« Créez ou rejoignez un clan ! », ou le clan
## du joueur et sa discussion), panneau violet « Social » avec le classement des joueurs du serveur
## (en ligne ou non), et les boutons Combat amical (code entre amis) et Inviter un ami (codes
## d'invitation du serveur).

const PURPLE := Color("5a43c8")
const PURPLE_DARK := Color("4532a6")
const PURPLE_LIGHT := Color("6d58db")

var _top := Control.new()
var _rows := VBoxContainer.new()
var _chat_layer: Control


func _ready() -> void:
	var top := ScreenLayout.top() + TopBar.HEIGHT + 10
	var w := size.x - 40
	_top.position = Vector2(20, top)
	_top.size = Vector2(w, 190)
	add_child(_top)
	# Panneau « Social ».
	var panel_y := top + _top.size.y + 16
	var buttons_h := 96.0
	var panel := ScUi.panel("ui_common", "bg_r25", Vector2(w, size.y - panel_y - 16), PURPLE_DARK, 0.9)
	panel.position = Vector2(20, panel_y)
	add_child(panel)
	var inner := ScUi.panel("ui_common", "bg_r25", Vector2(w - 20, panel.size.y - 90 - buttons_h), PURPLE, 0.8)
	inner.position = Vector2(10, 74)
	panel.add_child(inner)
	var title := ScUi.label("Social", 30)
	title.position = Vector2(20, 18)
	panel.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 10)
	scroll.size = inner.size - Vector2(24, 20)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	inner.add_child(scroll)
	_rows.add_theme_constant_override("separation", 10)
	_rows.custom_minimum_size = Vector2(scroll.size.x, 0)
	scroll.add_child(_rows)
	var bw := (w - 20 - 12) / 2.0
	var friendly := ScUi.text_button("blue", "Combat amical", Vector2(bw, buttons_h - 14), _open_friendly, 22)
	friendly.position = Vector2(10, panel.size.y - buttons_h)
	panel.add_child(friendly)
	var invite := ScUi.text_button("green", "Inviter un ami", Vector2(bw, buttons_h - 14), _open_invites, 22)
	invite.position = Vector2(22 + bw, panel.size.y - buttons_h)
	panel.add_child(invite)
	Player.clan_changed.connect(_refresh_top)
	Player.changed.connect(_on_profile)
	Player.players_listed.connect(_show_players)
	Player.clans_listed.connect(_show_clan_list)
	_refresh_top()
	_on_profile()


func _exit_tree() -> void:
	Player.clan_changed.disconnect(_refresh_top)
	Player.changed.disconnect(_on_profile)
	Player.players_listed.disconnect(_show_players)
	Player.clans_listed.disconnect(_show_clan_list)


var _asked := false


func _on_profile() -> void:
	if Player.online() and not _asked:
		_asked = true
		Net.send({"t": "players"})
	_refresh_top()


func _notification(what: int) -> void:
	# Classement rafraîchi quand la page redevient visible (glissé jusqu'à elle).
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and Player.online():
		Net.send({"t": "players"})


# --- Carte du clan --------------------------------------------------------------------------------

func _refresh_top() -> void:
	for c in _top.get_children():
		c.queue_free()
	var w := _top.size.x
	var in_clan := not Player.clan.is_empty()
	var head := ScUi.panel("ui_common", "bg_r25", Vector2(w, 82), PURPLE, 0.8)
	_top.add_child(head)
	var icon := ScUi.fit_height(ScUi.clip("ui", "icon_menu_clan"), 96)
	ScUi.hide(ScUi.node_of(icon), ["icon_war", "icon_war_active", "live", "offline", "online"])
	icon.position = Vector2(4, -14)
	_top.add_child(icon)
	var title := ScUi.label(Player.clan.get("name", "") if in_clan else "Créez ou rejoignez un clan !", 26)
	title.position = Vector2(104, 0)
	title.size = Vector2(w - 116, 82)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true
	_top.add_child(title)
	var body := ScUi.panel("ui_common", "bg_r25", Vector2(w, 100), Color("eef2f8"), 0.8)
	body.position = Vector2(0, 86)
	_top.add_child(body)
	var text := ScUi.label("%d membres · discussion, demandes et dons" % Player.clan.get("members", []).size() if in_clan
			else "Trouvez ou créez un nouveau clan !", 18, Color("4a5470"), false)
	text.position = Vector2(20, 0)
	text.size = Vector2(w - 230, 100)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(text)
	var open := ScUi.text_button("purple", "Ouvrir" if in_clan else "Afficher", Vector2(180, 74),
			_open_chat if in_clan else _open_clan_list, 24)
	open.position = Vector2(w - 196, 13)
	body.add_child(open)


# --- Classement -----------------------------------------------------------------------------------

func _show_players(list: Array) -> void:
	for c in _rows.get_children():
		c.queue_free()
	var online := list.filter(func(p: Dictionary) -> bool: return p.online)
	_rows.add_child(_divider("En ligne (%d)" % online.size()))
	_rows.add_child(_divider("Classement"))
	var rank := 1
	for p: Dictionary in list:
		_rows.add_child(_player_row(p, rank))
		rank += 1


func _divider(text: String) -> Control:
	var box := Control.new()
	var w := _rows.custom_minimum_size.x
	box.custom_minimum_size = Vector2(w, 40)
	var l := ScUi.label(text, 20, Color("e6e0ff"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(w, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	for side in [0, 1]:
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.35)
		line.size = Vector2(w * 0.24, 3)
		line.position = Vector2(20 if side == 0 else w * 0.76 - 20, 19)
		box.add_child(line)
	return box


func _player_row(p: Dictionary, rank: int) -> Control:
	var w := _rows.custom_minimum_size.x
	var me: bool = p.get("me", false)
	var row := ScUi.panel("ui_common", "bg_r16", Vector2(w, 72), Color("f2b736") if me else PURPLE_LIGHT, 0.7)
	var r := ScUi.label(str(rank), 22, Color.WHITE)
	r.position = Vector2(12, 0)
	r.size = Vector2(40, 72)
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(r)
	if p.online:
		var dot := ScUi.panel("ui_common", "bg_round", Vector2(16, 16), Color("39d353"), 0.12)
		dot.position = Vector2(56, 12)
		row.add_child(dot)
	var name := ScUi.label(str(p.name), 22)
	name.position = Vector2(76, 8)
	name.size = Vector2(w - 260, 30)
	name.clip_text = true
	row.add_child(name)
	var sub := ScUi.label(("%s · niv. %d" % [p.clan, int(p.level)]) if str(p.clan) != "" else "Niv. %d" % int(p.level), 15,
			Color(1, 1, 1, 0.8), false)
	sub.position = Vector2(76, 40)
	row.add_child(sub)
	var pill := ScUi.panel("ui_common", "bg_r50", Vector2(130, 46), Color(0, 0, 0, 0.3), 0.4)
	pill.position = Vector2(w - 146, 13)
	row.add_child(pill)
	var trophy := ScUi.fit_height(ScUi.clip("ui", "UI_icon_trophy"), 40)
	trophy.position = Vector2(-10, 3)
	pill.add_child(trophy)
	var t := ScUi.label(str(int(p.trophies)), 22, Color.WHITE)
	t.position = Vector2(34, 0)
	t.size = Vector2(90, 46)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(t)
	return row


# --- Clans : liste et création ---------------------------------------------------------------------

var _clan_popup: Popup16


func _open_clan_list() -> void:
	if not Player.online():
		return
	_clan_popup = Popup16.make("Clans", size.x - 40)
	var col := _clan_popup.content
	col.add_child(Popup16.text("Crée ton clan :", 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name := Popup16.field("")
	name.placeholder_text = "Nom du clan"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	row.add_child(ScUi.text_button("green", "Créer", Vector2(150, 72), func() -> void:
		if name.text.strip_edges().length() >= 3:
			Net.send({"t": "clan_create", "name": name.text})
			_clan_popup.close(), 24))
	col.add_child(row)
	col.add_child(Popup16.text("Ou rejoins un clan :", 22))
	var list := VBoxContainer.new()
	list.name = "ClanList"
	list.add_theme_constant_override("separation", 10)
	col.add_child(list)
	ScUi.popup(self, _clan_popup)
	Net.send({"t": "clans"})


func _show_clan_list(clans: Array) -> void:
	if not is_instance_valid(_clan_popup):
		return
	var list := _clan_popup.content.get_node_or_null("ClanList") as VBoxContainer
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	if clans.is_empty():
		list.add_child(Popup16.text("Aucun clan pour l'instant : crée le premier !", 20))
	for c: Dictionary in clans:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := Popup16.text("%s (%d)" % [c.name, int(c.members)], 22)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var id: String = c.id
		row.add_child(ScUi.text_button("blue", "Rejoindre", Vector2(190, 64), func() -> void:
			Net.send({"t": "clan_join", "id": id})
			_clan_popup.close(), 20))
		list.add_child(row)


# --- Discussion du clan --------------------------------------------------------------------------------

func _open_chat() -> void:
	_chat_layer = ClanChat.new()
	ScUi.popup(self, _chat_layer)


# --- Combat amical, invitations -------------------------------------------------------------------------

func _open_friendly() -> void:
	if not Net.is_online():
		return
	var mode: String = Profile.get_value("mode", "1v1")
	var popup := Popup16.make("Combat amical", size.x - 60)
	var col := popup.content
	col.add_child(Popup16.text("Choisissez le même code entre amis (%s) :" % ("2 contre 2" if mode == "2v2" else "1 contre 1")))
	var code := Popup16.field(Profile.get_value("room", str(randi_range(1000, 9999))))
	col.add_child(code)
	col.add_child(Popup16.buttons([["Annuler", "blue", popup.close], ["Jouer", "green", func() -> void:
		var room := code.text.strip_edges()
		if room == "":
			return
		Profile.set_value("room", room)
		popup.close()
		Net.send({"t": "queue", "mode": mode, "room": room})
		var menu := get_parent().get_parent() if get_parent() else null
		if menu is MainMenu:
			menu.show_page(MainMenu.BATTLE_PAGE, true)]]))
	ScUi.popup(self, popup)


func _open_invites() -> void:
	if not Net.is_online():
		return
	var popup := Popup16.make("Inviter un ami", size.x - 40)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 12)
	popup.content.add_child(holder)
	holder.add_child(Popup16.text("Chargement…", 22))
	var show := func(info: Dictionary) -> void:
		if not is_instance_valid(holder):
			return
		for c in holder.get_children():
			c.queue_free()
		var host: String = Profile.get_value("server", "").get_slice(":", 0)
		var base := "http://%s:%d/i/" % [host, int(info.get("http_port", 19341))]
		if str(info.get("mode", "")) != "invite":
			holder.add_child(Popup16.text("Ce serveur est ouvert : ton ami installe l'appli et indique l'adresse %s dans Paramètres." % host, 22))
		var list: Array = info.get("list", [])
		for i: Dictionary in list:
			var used: Array = i.get("used_by", [])
			var line := "%s — %s" % [i.code, ("utilisée par " + ", ".join(used)) if not used.is_empty() else ("valable" if i.usable else "expirée")]
			holder.add_child(Popup16.text(line, 22))
			if i.usable:
				var code: String = i.code
				holder.add_child(Popup16.buttons([["Copier le lien", "blue", func() -> void:
					DisplayServer.clipboard_set(base + code)
					Sounds.ui("button_click_02")]], 70))
		var left := int(info.get("quota", 0)) - list.size()
		if left > 0:
			holder.add_child(Popup16.text("Invitations restantes : %d" % left, 20))
			holder.add_child(Popup16.buttons([["Créer une invitation", "green", func() -> void:
				Net.send({"t": "invite_create"})]]))
		elif list.is_empty():
			holder.add_child(Popup16.text("L'admin du serveur gère les invitations.", 20))
		holder.add_child(Popup16.text("Ton ami ouvre le lien : il y trouve l'appli et son code.", 18, Color("5a6480")))
	Player.invites_listed.connect(show)
	popup.tree_exited.connect(func() -> void: Player.invites_listed.disconnect(show))
	ScUi.popup(self, popup)
	Net.send({"t": "invites"})
