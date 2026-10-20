class_name MainMenu
extends Control
## Menu principal de la 16.4 : fond à losanges, barre du haut commune (TopBar), pages côte à côte
## (Boutique, Cartes, Combat, Clan, Événements) qui glissent au doigt, barre d'onglets du bas
## (menu_bottom_* de ui.sc : l'onglet choisi s'élargit et affiche son nom).

signal battle_requested(options: Dictionary)

const NAV_HEIGHT := 118.0
const TABS := [["icon_menu_shop", "TID_TAB_SHOP", "Boutique"], ["icon_menu_cards", "TID_TAB_CARDS", "Cartes"],
	["icon_menu_battle", "TID_TAB_BATTLE", "Combat"], ["icon_menu_clan", "TID_TAB_SOCIAL", "Social"],
	["icon_menu_tornament", "TID_TAB_EVENTS", "Événements"]]
const BATTLE_PAGE := 2
const SELECTED_WIDTH := 1.55        # largeur de l'onglet choisi / largeur d'un autre onglet

static var last_page := BATTLE_PAGE

var top_bar := TopBar.new()
var _pages: Array[Control] = []
var _strip := Control.new()
var _nav := Control.new()
var _tabs: Array[Dictionary] = []
var _page := BATTLE_PAGE
var _swipe_from := Vector2.INF
var _swiping := false
var _strip_from := 0.0


func _ready() -> void:
	size = ScreenLayout.size()
	theme = Style.theme()
	add_child(ScUi.menu_background(size))
	var page_size := Vector2(size.x, size.y - NAV_HEIGHT - ScreenLayout.bottom())
	_strip.size = Vector2(size.x * TABS.size(), page_size.y)
	add_child(_strip)
	var home := HomeScreen.new()
	home.battle_requested.connect(func(o: Dictionary) -> void: battle_requested.emit(o))
	var pages: Array[Control] = [ShopPage.new(), CardsPage.new(), home, ClanPage.new(), EventsPage.new()]
	for i in pages.size():
		var page: Control = pages[i]
		page.position = Vector2(size.x * i, 0)
		page.size = page_size
		page.clip_contents = true
		_strip.add_child(page)
		_pages.append(page)
	add_child(top_bar)
	top_bar.shop_requested.connect(func() -> void: show_page(0, true))
	_build_nav()
	Player.changed.connect(_update_badges)
	_update_badges()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--page="):          # test : page affichée au départ
			last_page = int(arg.get_slice("=", 1))
	show_page(last_page, false)
	Player.celebrate.connect(func(_k: String, _v: Variant) -> void: _show_celebrations())
	_show_celebrations()
	Player.notice.connect(_on_notice)
	Player.chest_opened.connect(func(content: Dictionary) -> void:
		var opening := ChestOpening.new()
		opening.content = content
		add_child(opening))


func _exit_tree() -> void:
	Player.notice.disconnect(_on_notice)


## Annonce de l'admin (ou refus du serveur) : fenêtre par-dessus tout.
func _on_notice(text: String) -> void:
	var popup := Popup16.make("Message du serveur", size.x - 60)
	popup.content.add_child(Popup16.text(text, 26))
	popup.content.add_child(Popup16.buttons([["OK", "blue", popup.close]]))
	add_child(popup)


## Annonces en attente (reçues pendant un combat ou à l'instant), les plus anciennes au-dessus.
func _show_celebrations() -> void:
	for item in Player.celebrations:
		var c := Celebration.new()
		c.kind = item[0]
		c.value = item[1]
		add_child(c)
	Player.celebrations.clear()


# --- Onglets du bas ------------------------------------------------------------------------------

func _build_nav() -> void:
	_nav.position = Vector2(0, size.y - NAV_HEIGHT - ScreenLayout.bottom())
	_nav.size = Vector2(size.x, NAV_HEIGHT + ScreenLayout.bottom())
	_nav.clip_contents = true
	add_child(_nav)
	var floor_bg := ColorRect.new()
	floor_bg.color = Color("1b2433")
	floor_bg.size = _nav.size
	_nav.add_child(floor_bg)
	for i in TABS.size():
		var tab := {}
		var holder := Control.new()
		holder.clip_contents = true
		_nav.add_child(holder)
		tab.holder = holder
		for kind in ["bg", "selected"]:
			var bg := ScUi.clip("ui", "menu_bottom_tab_bg" if kind == "bg" else "menu_bottom_tab_selected")
			ScUi.hide(bg, ["tutorial_grad"])
			holder.add_child(bg)
			tab[kind] = bg
		var icon_node := ScUi.clip("ui", TABS[i][0])
		ScUi.hide(icon_node, ["icon_war", "icon_war_active", "live", "offline", "online"])
		var icon := ScUi.fit_height(icon_node, NAV_HEIGHT * 0.66)
		holder.add_child(icon)
		tab.icon = icon
		var label := ScUi.label(TABS[i][2], 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(label)
		tab.label = label
		var badge := _badge()
		holder.add_child(badge)
		tab.badge = badge
		var index := i
		ScUi.make_button(holder, func() -> void: show_page(index, true), "menu_click_06")
		_tabs.append(tab)
	for i in TABS.size() - 1:
		var divider := ScUi.clip("ui", "menu_bottom_divider")
		_nav.add_child(divider)
		_tabs[i].divider = divider


## Pastille rouge à nombre (notifications des onglets).
static func _badge() -> Label:
	var badge := ScUi.label("", 20)
	var dot := StyleBoxFlat.new()
	dot.bg_color = Color("e8173a")
	dot.border_color = Color(1, 1, 1, 0.9)
	dot.set_border_width_all(2)
	dot.set_corner_radius_all(16)
	dot.content_margin_left = 9
	dot.content_margin_right = 9
	dot.content_margin_top = 1
	badge.add_theme_stylebox_override("normal", dot)
	badge.visible = false
	return badge


func _layout_nav(animate: bool) -> void:
	var unit := size.x / (TABS.size() - 1 + SELECTED_WIDTH)
	var x := 0.0
	for i in _tabs.size():
		var tab: Dictionary = _tabs[i]
		var selected := i == _page
		var w := unit * (SELECTED_WIDTH if selected else 1.0)
		var holder: Control = tab.holder
		var rect := Rect2(x, 0, w, _nav.size.y)
		if animate:
			var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			t.tween_property(holder, "position", rect.position, 0.18)
			t.tween_property(holder, "size", rect.size, 0.18)
		else:
			holder.position = rect.position
			holder.size = rect.size
		_fill_tab(tab, rect.size, selected)
		if tab.has("divider"):
			var d: Node2D = tab.divider
			d.scale = Vector2(ScUi.k(), _nav.size.y / 257.0)
			d.position = Vector2(x + w, _nav.size.y * 0.38)
			d.visible = i != _page and i + 1 != _page
		x += w


func _fill_tab(tab: Dictionary, s: Vector2, selected: bool) -> void:
	for kind in ["bg", "selected"]:
		var bg: Node2D = tab[kind]
		var b := ScMovieClip.bounds_of(bg)
		bg.scale = Vector2(s.x * 1.02 / b.size.x, ScUi.k())
		bg.position = Vector2(s.x / 2 - b.get_center().x * bg.scale.x, -(b.end.y - 257.0) * ScUi.k() - 4)
		bg.visible = (kind == "selected") == selected
		bg.modulate = Color(0.62, 0.78, 1.05) if kind == "bg" else Color.WHITE
	var icon: Control = tab.icon
	var lift := -10.0 if selected else 0.0
	icon.scale = Vector2.ONE * (1.12 if selected else 0.92)
	icon.pivot_offset = icon.size / 2
	icon.position = Vector2((s.x - icon.size.x) / 2, (NAV_HEIGHT - icon.size.y) / 2 + lift - (8 if selected else 0))
	var label: Label = tab.label
	label.visible = selected
	label.size = Vector2(s.x, 26)
	label.position = Vector2(0, NAV_HEIGHT - 34)
	var badge: Label = tab.badge
	badge.position = Vector2(s.x / 2 + 14, 4)


## Pastilles : cartes à améliorer (onglet Cartes), offres encore achetables (Boutique).
func _update_badges() -> void:
	if not Player.online():
		return
	var upgrades := 0
	for id in Player.profile.cards:
		var up := Player.upgrade_info(id)
		if not up.is_empty() and up.have >= up.cards and int(Player.profile.gold) >= up.gold:
			upgrades += 1
	var offers := 0
	for o in Player.profile.get("shop", []):
		if int(o.bought) == 0 and int(Player.profile.gold) >= int(o.price):
			offers += 1
	for pair in [[0, offers], [1, upgrades]]:
		var badge: Label = _tabs[pair[0]].badge
		badge.visible = pair[1] > 0
		badge.text = str(pair[1])


func show_page(page: int, animate: bool) -> void:
	page = clampi(page, 0, TABS.size() - 1)
	if animate and page != _page:
		Sounds.ui("menu_swipe_09")
	_page = page
	last_page = page
	var target := Vector2(-size.x * page, 0)
	if animate:
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(_strip, "position", target, 0.25)
	else:
		_strip.position = target
	_layout_nav(animate)


# --- Glissé horizontal entre les pages -------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _overlay_open():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.y < _nav.position.y and event.position.y > top_bar.size.y:
			_swipe_from = event.position
			_strip_from = _strip.position.x
			_swiping = false
		elif not event.pressed and _swipe_from != Vector2.INF:
			if _swiping:
				var dx: float = event.position.x - _swipe_from.x
				show_page(_page - (1 if dx > size.x * 0.18 else (-1 if dx < -size.x * 0.18 else 0)), true)
			_swipe_from = Vector2.INF
			_swiping = false
	elif event is InputEventMouseMotion and _swipe_from != Vector2.INF:
		var d: Vector2 = event.position - _swipe_from
		if not _swiping and absf(d.x) > 36 and absf(d.x) > absf(d.y) * 1.6:
			_swiping = true
		if _swiping:
			_strip.position.x = clampf(_strip_from + d.x, -size.x * (TABS.size() - 1), 0)
			get_viewport().set_input_as_handled()


## Une fenêtre (popup, ouverture de coffre…) recouvre le menu : pas de glissé.
func _overlay_open() -> bool:
	for c in get_children():
		if c is Control and c.get_index() > _nav.get_index() and c.visible and c != top_bar:
			return true
	return false
