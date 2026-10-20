class_name HomeScreen
extends Control
## Accueil (onglet Combat) assemblé avec les éléments de l'accueil de la 16.4 : bandeau du joueur et
## boutons (Menu_topLayer_Banner), arène sur son halo, emplacements de coffres de la 1.9
## (main_screen_chest_bg), bloc de combat (deck, bouton Combat de UI_menu_arena, mode 1c1 / 2c2),
## recherche d'adversaire. Connexion au serveur ; le message « match » lance le combat.

signal battle_requested(options: Dictionary)

const CHEST_ICONS := {"Free": "wood", "Silver": "silver", "Gold": "gold", "Magic": "magical", "Giant": "giant",
	"Super": "super", "Epic": "epic", "Legendary": "legendary", "Crown": "king"}

var _mode := "1v1"
var _account := {}
var _queue_since := 0.0
var _queue_room := ""
var _queued := false

var _name_label: Label
var _clan_label: Label
var _trophy_label: Label
var _status: Label
var _arena: Control
var _arena_title: Label
var _arena_bar: Control
var _chest_row := Control.new()
var _free_chest := Control.new()
var _battle_button: Control
var _mode_button: Control
var _deck_button: Control
var _search: Control
var _search_time: Label
var _chest_timer := 0.0
var _float_t := 0.0


func _ready() -> void:
	if not get_parent() is Control:
		size = ScreenLayout.size()
	theme = Style.theme()
	_mode = Profile.get_value("mode", "1v1")
	_build()
	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_on_disconnected)
	Net.message.connect(_on_message)
	Player.changed.connect(_refresh)
	var testing := Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool:
		return a.begins_with("--host") or a.begins_with("--token") or a.begins_with("--page"))
	if not Profile.get_value("named", false) and not testing:
		_ask_name.call_deferred()
	Sounds.music("music_lobby_202610", "music_lobby_202610_a")
	if Net.is_online():
		_on_connected()
	else:
		_connect()
	_refresh()


func _exit_tree() -> void:
	Player.changed.disconnect(_refresh)
	Net.connected.disconnect(_on_connected)
	Net.disconnected.disconnect(_on_disconnected)
	Net.message.disconnect(_on_message)


func _process(delta: float) -> void:
	_chest_timer += delta
	if _chest_timer >= 1.0:
		_chest_timer = 0.0
		_build_chests()
	if _queued:
		var waited := int(Time.get_ticks_msec() / 1000.0 - _queue_since)
		_search_time.text = "%d:%02d" % [waited / 60, waited % 60]
	_float_t += delta
	if _arena.get_child_count() > 1:
		(_arena.get_child(1) as Node2D).position.y = _arena.get_meta("y0", 0.0) + sin(_float_t * 1.1) * 5.0


# --- Construction --------------------------------------------------------------------------------

func _build() -> void:
	var k := ScUi.k()
	var top := ScreenLayout.top() + TopBar.HEIGHT

	# Bandeau du joueur : nom, clan, trophées ; boutons social / actualités / menu.
	var strip := ScUi.clip("ui", "Menu_topLayer_Banner/profile_strip") as ScMovieClip
	var button := strip.get_sc("profile_button") as ScMovieClip
	var buttons := strip.get_sc("buttons") as ScMovieClip
	for n in [button, buttons]:
		n.get_parent().remove_child(n)
		n.transform = Transform2D.IDENTITY
	strip.free()
	# Bannière de combat du joueur (personnalisable), nom, clan et trophées dessous.
	var banner_box := ScUi.fit_width(ScUi.banner(Profile.get_value("banner_bg", "green"), Profile.get_value("banner_fg", "yellow")), size.x * 0.56)
	banner_box.position = Vector2(-size.x * 0.03, top + 4)
	add_child(banner_box)
	button.free()
	var profile_box := Control.new()
	profile_box.position = Vector2(0, banner_box.position.y + banner_box.size.y - 4)
	profile_box.size = Vector2(size.x * 0.6, 74)
	add_child(profile_box)
	_name_label = ScUi.label("", 30)
	_name_label.position = Vector2(20, 0)
	_name_label.size = Vector2(240, 40)
	profile_box.add_child(_name_label)
	_clan_label = ScUi.label("", 19, Color("c9d6ea"), false)
	_clan_label.position = Vector2(22, 40)
	profile_box.add_child(_clan_label)
	var pill := ScUi.panel("ui_common", "bg_r50", Vector2(150, 44), Color(0.04, 0.1, 0.24, 0.75), 0.5)
	pill.position = Vector2(270, 4)
	profile_box.add_child(pill)
	var trophy := ScUi.fit_height(ScUi.clip("ui", "UI_icon_trophy"), 52)
	trophy.position = Vector2(256, -2)
	profile_box.add_child(trophy)
	_trophy_label = ScUi.label("", 26, Color("ffd94a"))
	_trophy_label.position = Vector2(310, 4)
	_trophy_label.size = Vector2(104, 44)
	_trophy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_trophy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	profile_box.add_child(_trophy_label)
	ScUi.make_button(banner_box, func() -> void: ScUi.popup(self, ProfilePopup.new()))
	ScUi.make_button(profile_box, func() -> void: ScUi.popup(self, ProfilePopup.new()))
	for n in ["button_list_menu/notification", "btn_achievement/notification", "btn_achievement/notification_meetup",
			"btn_achievement/icon_live", "btn_achievement/gold", "button_social/notification", "button_social/friends_online"]:
		buttons.set_sc_visible(n, false)
	var x := size.x - 12
	for pair in [["button_list_menu", _open_menu], ["btn_achievement", _open_news], ["button_social", _open_social]]:
		var b := buttons.get_sc(pair[0]) as ScMovieClip
		b.get_parent().remove_child(b)
		b.transform = Transform2D.IDENTITY
		var box := ScUi.element(b, 1.1)
		x -= box.size.x
		box.position = Vector2(x, top + 12)
		x -= 8
		add_child(box)
		ScUi.make_button(box, pair[1])
	buttons.free()
	_status = ScUi.label("", 18, Color(1, 1, 1, 0.75), false)
	_status.position = Vector2(16, profile_box.position.y + profile_box.size.y + 2)
	_status.size = Vector2(size.x * 0.6, 24)
	add_child(_status)

	# Bloc de combat, en bas de la page.
	var panel_h := 150.0
	var panel_y := size.y - panel_h - 12
	var panel := ScUi.panel("ui_common", "bg_r50", Vector2(size.x - 28, panel_h - 18), Color("1c2f5a"), 0.8)
	panel.position = Vector2(14, panel_y + 18)
	add_child(panel)
	var rim := ScUi.panel("ui_common", "bg_r50", Vector2(size.x - 40, panel_h - 30), Color("27467f"), 0.75)
	rim.position = Vector2(20, panel_y + 22)
	add_child(rim)
	_deck_button = Control.new()
	_deck_button.size = Vector2(panel_h * 0.62, panel_h * 0.78)
	_deck_button.position = Vector2(40, panel_y + (panel_h - _deck_button.size.y) / 2 + 9)
	add_child(_deck_button)
	ScUi.make_button(_deck_button, func() -> void: _go_page(1))
	var play := ScUi.clip("ui", "UI_menu_arena/play_arena")
	ScUi.hide(play, ["cost"])
	_battle_button = ScUi.fit_height(play, panel_h * 0.92)
	_battle_button.position = Vector2((size.x - _battle_button.size.x) / 2, panel_y + (panel_h - _battle_button.size.y) / 2 + 2)
	add_child(_battle_button)
	ScUi.make_button(_battle_button, _on_battle_pressed, "attack_button_01")
	_mode_button = Control.new()
	_mode_button.size = Vector2(panel_h * 0.8, panel_h * 0.8)
	_mode_button.position = Vector2(size.x - 30 - _mode_button.size.x, panel_y + (panel_h - _mode_button.size.y) / 2 + 9)
	add_child(_mode_button)
	ScUi.make_button(_mode_button, func() -> void:
		if _queued:
			return
		_mode = "2v2" if _mode == "1v1" else "1v1"
		Profile.set_value("mode", _mode)
		_refresh())

	# Coffres : 4 emplacements au-dessus du bloc de combat.
	var slot_h := 150.0 * k
	_chest_row.position = Vector2(20, panel_y - slot_h - 14)
	_chest_row.size = Vector2(size.x - 40, slot_h)
	add_child(_chest_row)

	# Arène au centre, sur son halo ; nom et barre de trophées dessous.
	var area_top := _status.position.y + 10
	var area_bottom := _chest_row.position.y - 70
	_arena = Control.new()
	_arena.position = Vector2(0, area_top)
	_arena.size = Vector2(size.x, area_bottom - area_top)
	_arena.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_arena)
	# Halo derrière l'arène (cercles concentriques, plus clair au centre).
	var glow := Control.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = _arena.size
	var radius := minf(size.x * 0.52, _arena.size.y * 0.55)
	glow.draw.connect(func() -> void:
		for i in 28:
			var t := 1.0 - i / 28.0
			glow.draw_circle(glow.size / 2, radius * t, Color(0.62, 0.9, 1.0, 0.045 + 0.03 * (1.0 - t))))
	_arena.add_child(glow)
	_arena.add_child(Node2D.new())
	ScUi.make_button(_arena, func() -> void: ScUi.popup(self, ProfilePopup.new()), "press_arena_01")
	_arena_title = ScUi.label("", 30)
	_arena_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arena_title.position = Vector2(0, area_bottom + 4)
	_arena_title.size = Vector2(size.x, 36)
	add_child(_arena_title)

	# Coffre gratuit, à droite du bandeau (à la place du Pass de la 16.4).
	_free_chest.position = Vector2(size.x - 128, top + 116)
	_free_chest.size = Vector2(110, 120)
	add_child(_free_chest)
	ScUi.make_button(_free_chest, func() -> void:
		if int(Player.profile.get("free_chests", 0)) > 0:
			Net.send({"t": "free_chest"}))

	# Recherche d'adversaire : bandeau de la 16.4 au-dessus du bouton.
	_search = ScUi.fit_width(ScUi.clip("ui", "UI_menu_arena/match_making"), size.x * 0.7)
	_search.position = Vector2((size.x - _search.size.x) / 2, _chest_row.position.y - _search.size.y - 4)
	_search.visible = false
	add_child(_search)
	_search_time = ScUi.label("", 26)
	_search_time.position = Vector2(_search.position.x, _search.position.y + _search.size.y - 30)
	_search_time.size = Vector2(_search.size.x, 30)
	_search_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_search_time.visible = false
	add_child(_search_time)


## Emplacements de coffres (état du serveur) : coffre, minuteur ou « Ouvrir » / « Déverrouiller ».
func _build_chests() -> void:
	for c in _chest_row.get_children():
		c.queue_free()
	_build_free_chest()
	if not Player.online():
		return
	var chests: Array = Player.profile.get("chests", [])
	var w := (_chest_row.size.x - 3 * 12) / 4.0
	for i in Progression.SLOTS:
		var slot := ScUi.panel("ui_main_screen_royals", "main_screen_chest_bg", Vector2(w, _chest_row.size.y))
		slot.position = Vector2(i * (w + 12), 0)
		_chest_row.add_child(slot)
		if i >= chests.size():
			var empty := ScUi.label("Emplacement libre", 15, Color(1, 1, 1, 0.45), false)
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.size = slot.size
			slot.add_child(empty)
			continue
		var chest: Dictionary = chests[i]
		var left := Player.chest_seconds_left(chest)
		var ready: bool = chest.state == "ready" or (chest.state == "unlocking" and left <= 0)
		var icon := ScUi.fit_height(ScUi.clip("ui_chest", "chest_item_" + CHEST_ICONS.get(chest.type, "silver")), slot.size.y * 0.52)
		icon.position = Vector2((w - icon.size.x) / 2, slot.size.y * 0.2)
		slot.add_child(icon)
		var text := ScUi.label("Ouvrir" if ready else (_time(left) if chest.state == "unlocking" else _time(int(chest.get("seconds", 0)))), 20,
				Color("ffe14d") if ready else Color.WHITE)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.position = Vector2(0, slot.size.y * 0.72)
		text.size = Vector2(w, 30)
		slot.add_child(text)
		if chest.state == "locked":
			var hint := ScUi.label("Déverrouiller", 14, Color(1, 1, 1, 0.8), false)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.position = Vector2(0, 6)
			hint.size = Vector2(w, 22)
			slot.add_child(hint)
		var index := i
		ScUi.make_button(slot, func() -> void:
			Net.send({"t": "chest_unlock" if chest.state == "locked" else "chest_open", "slot": index}),
			"tap_locked_chest_01" if chest.state == "locked" else "tap_open_lootbox_01")


## Coffre gratuit (jusqu'à 2 en réserve) : compteur ou temps avant le prochain.
func _build_free_chest() -> void:
	for c in _free_chest.get_children():
		c.queue_free()
	_free_chest.visible = Player.online()
	if not Player.online():
		return
	var count := int(Player.profile.get("free_chests", 0))
	var icon := ScUi.fit_height(ScUi.clip("ui_chest", "chest_item_wood"), 80)
	icon.position = Vector2((_free_chest.size.x - icon.size.x) / 2, 0)
	_free_chest.add_child(icon)
	var next := int(Player.profile.get("free_next", 0)) - int(Player.profile.get("now", 0))
	var text := ScUi.label("Gratuit" if count > 0 else _time(maxi(0, next)), 18,
			Color("ffe14d") if count > 0 else Color.WHITE)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.position = Vector2(-10, 82)
	text.size = Vector2(_free_chest.size.x + 20, 26)
	_free_chest.add_child(text)
	if count > 1:
		var badge := MainMenu._badge()
		badge.text = str(count)
		badge.visible = true
		badge.position = Vector2(_free_chest.size.x - 30, -6)
		_free_chest.add_child(badge)


static func _time(seconds: int) -> String:
	if seconds >= 3600:
		return "%dh %02dmin" % [seconds / 3600, seconds % 3600 / 60]
	if seconds >= 60:
		return "%dmin" % (seconds / 60)
	return "%ds" % seconds


func _refresh() -> void:
	if Player.online():
		_account = Player.profile
	var name: String = _account.get("name", Profile.get_value("name", "Joueur"))
	var trophies: int = _account.get("trophies", 0)
	_name_label.text = name
	_clan_label.text = Player.clan.get("name", GameDB.text("TID_NO_CLAN"))
	_trophy_label.text = str(trophies)
	_build_chests()
	# Mode : coupe des trophées (1c1) ou écusson 2c2.
	for c in _mode_button.get_children():
		c.queue_free()
	var mode_icon := ScUi.fit_height(ScUi.clip("ui_main_screen_royals", "button_mode_trophy_road_mode_ladder") if _mode == "1v1"
			else ScUi.clip("ui_main_screen_royals", "icon_clan_royals2v2_battle"), _mode_button.size.y)
	mode_icon.position = (_mode_button.size - mode_icon.size) / 2
	_mode_button.add_child(mode_icon)
	_battle_button.modulate = Color.WHITE if Net.is_online() else Color(0.6, 0.6, 0.6)
	# Bouton du deck : première carte du deck (comme le sélecteur de deck de la 16.4).
	for c in _deck_button.get_children():
		c.queue_free()
	var deck_cards := Player.deck()
	if not deck_cards.is_empty():
		var card := CardView.make(deck_cards[0], _deck_button.size.x, false)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_deck_button.add_child(card)
		var num := MainMenu._badge()
		num.text = "1"
		num.visible = true
		num.position = Vector2(_deck_button.size.x - 22, _deck_button.size.y - 30)
		_deck_button.add_child(num)
	# Arène des trophées du joueur (diorama de ui_arena.sc).
	var arena: Dictionary = GameDB.arenas()[0]
	for a in GameDB.arenas():
		if trophies >= a.trophies:
			arena = a
	_arena_title.text = GameDB.arena_title(arena)
	var holder: Node2D = _arena.get_child(1)
	for c in holder.get_children():
		c.queue_free()
	var lib := ScLibrary.get_library("ui_arena")
	var export_name := "arena_%02d" % int(arena.number) if int(arena.number) < 10 else "arena_legendary"
	if lib.has_export(export_name):
		var clip := lib.create_export(export_name)
		var b := ScMovieClip.bounds_of(clip)
		var k := minf(size.x * 0.68 / b.size.x, _arena.size.y * 0.85 / b.size.y)
		clip.scale = Vector2.ONE * k
		clip.position = _arena.size / 2 - b.get_center() * k
		holder.add_child(clip)
	_arena.set_meta("y0", 0.0)


func _set_queued(on: bool) -> void:
	_queued = on
	_search.visible = on
	_search_time.visible = on
	var play := ScUi.node_of(_battle_button)
	if play:
		play.goto_and_stop(1 if on else 0)


# --- Réseau --------------------------------------------------------------------------------------

func _connect() -> void:
	var host: String = Profile.get_value("server", "127.0.0.1")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--host="):
			host = arg.get_slice("=", 1)
	_status.text = "Connexion à %s…" % host
	Net.connect_to(host.get_slice(":", 0), int(host.get_slice(":", 1)) if ":" in host else Protocol.PORT)


func _on_connected() -> void:
	var token: String = Profile.get_value("token", "")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--token="):            # test : reprendre un compte existant
			token = arg.get_slice("=", 1)
	Net.send({"t": "hello", "v": Protocol.VERSION, "name": Profile.get_value("name", "Joueur"),
		"token": token, "code": Profile.get_value("code", "")})


func _on_disconnected() -> void:
	_status.text = "Hors ligne — entraînement seulement"
	_set_queued(false)
	_refresh()
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if is_inside_tree() and not Net.is_online():
			_connect())


func _on_message(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"welcome":
			_account = msg
			Profile.set_value("token", msg.token)
			_status.text = ""
			_refresh()
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--auto-queue="):     # test : file d'attente sans toucher
					_mode = arg.get_slice("=", 1)
					_on_battle()
		"queued":
			_queue_since = Time.get_ticks_msec() / 1000.0
			_queue_room = str(msg.get("room", ""))
			_set_queued(true)
		"cancelled":
			_set_queued(false)
		"match":
			_set_queued(false)
			battle_requested.emit({"online": msg})
		"error":
			match msg.get("code", ""):
				"version":
					_status.text = "Serveur : version différente de l'appli"
				"access":
					_status.text = "Code d'accès requis (Menu → Paramètres)"
				"invite":
					_status.text = "Invitation requise"
					_ask_invite()
				"banned", "kicked":
					_status.text = "Compte suspendu"
				"event":
					_status.text = "Cet événement est terminé"
				_:
					_status.text = "Erreur du serveur"


func _on_battle_pressed() -> void:
	if _queued:
		Net.send({"t": "cancel"})
		_set_queued(false)
	else:
		_on_battle()


func _on_battle(room := "") -> void:
	if not Net.is_online():
		return
	Net.send({"t": "queue", "mode": _mode, "room": room})


# --- Menus ---------------------------------------------------------------------------------------

## Menu (☰) de la 16.4 : camp d'entraînement, combat amical, paramètres.
func _open_menu() -> void:
	var items := [["Camp d'entraînement", "icon_btn_training", func() -> void:
			battle_requested.emit({"training": true, "team_mode": _mode == "2v2"})],
		["Combat amical", "icon_menu_friendly_rules", _open_friendly],
		["Paramètres", "", _open_settings]]
	ScUi.popup(self, MenuPopup.make(items, Vector2(size.x - 24, ScreenLayout.top() + TopBar.HEIGHT + 70)))


func _open_news() -> void:
	_go_page(4)


func _open_social() -> void:
	_go_page(3)


func _go_page(page: int) -> void:
	var menu := get_parent().get_parent() if get_parent() else null
	if menu is MainMenu:
		menu.show_page(page, true)


## Combat amical : un code partagé entre amis (le même pour tous), dans le mode choisi.
func _open_friendly() -> void:
	if not Net.is_online():
		return
	var popup := Popup16.make("Combat amical (%s)" % ("2c2" if _mode == "2v2" else "1c1"), size.x - 60)
	var col := popup.content
	col.add_child(Popup16.text("Choisissez le même code entre amis :"))
	var code := Popup16.field(Profile.get_value("room", str(randi_range(1000, 9999))))
	col.add_child(code)
	col.add_child(Popup16.buttons([["Annuler", "blue", popup.close], ["Jouer", "green", func() -> void:
		var room := code.text.strip_edges()
		if room == "":
			return
		Profile.set_value("room", room)
		popup.close()
		_on_battle(room)]]))
	ScUi.popup(self, popup)


## Premier lancement : choix du pseudo (le reste se règle plus tard dans Paramètres).
func _ask_name() -> void:
	var popup := Popup16.make("Bienvenue !", size.x - 60, false)
	var col := popup.content
	col.add_child(Popup16.text("Choisis ton pseudo :"))
	var edit := Popup16.field(Profile.get_value("name", ""))
	edit.max_length = 16
	col.add_child(edit)
	col.add_child(Popup16.text("Code d'invitation (si le serveur en demande un) :"))
	var code := Popup16.field(Profile.get_value("code", ""))
	col.add_child(code)
	col.add_child(Popup16.buttons([["C'est parti", "green", func() -> void:
		var name := edit.text.strip_edges()
		if name.length() < 2:
			return
		Profile.set_value("name", name)
		Profile.set_value("named", true)
		Profile.set_value("code", code.text.strip_edges().to_upper())
		popup.close()
		if Net.is_online():
			_on_connected()
		_refresh()]]))
	ScUi.popup(self, popup)


## Le serveur demande une invitation pour créer le compte.
func _ask_invite() -> void:
	var popup := Popup16.make("Invitation", size.x - 60)
	popup.content.add_child(Popup16.text("Ce serveur est sur invitation. Saisis le code reçu d'un ami ou de l'admin :"))
	var code := Popup16.field(Profile.get_value("code", ""))
	popup.content.add_child(code)
	popup.content.add_child(Popup16.buttons([["Valider", "green", func() -> void:
		Profile.set_value("code", code.text.strip_edges().to_upper())
		popup.close()
		if Net.is_online():
			_on_connected()]]))
	ScUi.popup(self, popup)


func _open_settings() -> void:
	var popup := Popup16.make("Paramètres", size.x - 60)
	var col := popup.content
	var fields := {}
	for f in [["name", "Pseudo", Profile.get_value("name", "")], ["server", "Serveur (adresse[:port])",
			Profile.get_value("server", "127.0.0.1")], ["code", "Code d'invitation (nouveau compte)",
			Profile.get_value("code", "")]]:
		col.add_child(Popup16.text(f[1]))
		var edit := Popup16.field(f[2])
		col.add_child(edit)
		fields[f[0]] = edit
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 16)
	toggles.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(toggles)
	for t in [["sound", "Sons"], ["music", "Musique"]]:
		var on: bool = Profile.get_value(t[0], true)
		var b := ScUi.text_button("blue" if on else "red", "%s : %s" % [t[1], "oui" if on else "non"], Vector2(250, 70), func() -> void:
			var now: bool = not Profile.get_value(t[0], true)
			Profile.set_value(t[0], now)
			if t[0] == "music":
				if now:
					Sounds.music("music_lobby_202610", "music_lobby_202610_a")
				else:
					Sounds.stop_music()
			popup.close()
			_open_settings(), 22)
		toggles.add_child(b)
	col.add_child(Popup16.buttons([["OK", "green", func() -> void:
		var name: String = fields.name.text.strip_edges().left(16)
		if name != "":
			Profile.set_value("name", name)
		Profile.set_value("code", fields.code.text.strip_edges().to_upper())
		var server: String = fields.server.text.strip_edges()
		var changed: bool = server != Profile.get_value("server", "")
		Profile.set_value("server", server)
		popup.close()
		if changed or not Net.is_online():
			Net.close()
			_connect()
		_refresh()]]))
	ScUi.popup(self, popup)
