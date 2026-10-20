class_name ScUi
extends RefCounted
## Interface de la 16.4 faite de ses propres exports .sc : chaque élément est posé dans un Control
## à sa taille, à l'échelle des écrans du jeu (largeur de référence STAGE_WIDTH = largeur de
## l'écran). Boutons enfoncés au toucher comme dans le jeu, panneaux 9-slice étirés.

const STAGE_WIDTH := 780.0          # largeur des écrans de la 16.4 (main_screen_bg, UI_menu_arena)
const TITLE_FONT := "res://assets/gen/font/supercell-magic_0.ttf"
const BODY_FONT := "res://assets/gen/font/sc_ccbackbeatregular.ttf"
const TAP_SLOP := 24.0              # déplacement au-delà duquel un toucher devient un glissé


## Échelle des éléments .sc à l'écran.
static func k() -> float:
	return ScreenLayout.size().x / STAGE_WIDTH


## Export `export_name` de `lib`, ou enfant détaché « export/chemin/enfant ».
static func clip(lib: String, path: String) -> Node2D:
	var library := ScLibrary.get_library(lib)
	var root_name := path.get_slice("/", 0)
	if not library.has_export(root_name):
		return Node2D.new()
	var node := library.create_export(root_name)
	if not "/" in path:
		return node
	var part := (node as ScMovieClip).get_sc(path.substr(path.find("/") + 1))
	if part == null:
		node.free()
		return Node2D.new()
	part.get_parent().remove_child(part)
	part.transform = Transform2D.IDENTITY
	part.visible = true
	node.free()
	return part


## Élément .sc dans un Control à sa taille (coin haut-gauche = coin du contour), échelle
## `scale` × k(). Le nœud .sc est l'enfant 0 (`ScUi.node_of`).
static func element(node: Node2D, scale := 1.0, bounds := Rect2()) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := scale * k()
	var b := bounds if bounds.size != Vector2.ZERO else ScMovieClip.visible_bounds(node)
	node.scale = Vector2.ONE * s
	node.position = -b.position * s
	holder.size = b.size * s
	holder.custom_minimum_size = holder.size
	holder.add_child(node)
	return holder


static func node_of(holder: Control) -> ScMovieClip:
	return holder.get_child(0) as ScMovieClip if holder.get_child_count() > 0 else null


## Élément de hauteur `height` (px écran), proportions gardées.
static func fit_height(node: Node2D, height: float) -> Control:
	var b := ScMovieClip.visible_bounds(node)
	return element(node, height / maxf(1.0, b.size.y) / k(), b)


## Élément de largeur `width` (px écran), proportions gardées.
static func fit_width(node: Node2D, width: float) -> Control:
	var b := ScMovieClip.visible_bounds(node)
	return element(node, width / maxf(1.0, b.size.x) / k(), b)


## Panneau 9-slice (bg_r*, btn_*, bg_popup_* de ui_common…) étiré à `size` px ; `corner` règle
## l'échelle des coins (1 = taille du jeu).
static func panel(lib: String, export_name: String, size: Vector2, color := Color.WHITE, corner := 1.0) -> Control:
	var node := clip(lib, export_name)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = size
	holder.custom_minimum_size = size
	var s := corner * k()
	node.scale = Vector2.ONE * s
	if node is ScMovieClip and (node as ScMovieClip).scaling_grid.size != Vector2.ZERO:
		(node as ScMovieClip).set_slice_rect(Rect2(Vector2.ZERO, size / s))
	else:                               # pas de grille : simple étirement
		var b := ScMovieClip.bounds_of(node)
		node.scale = size / b.size
		node.position = -b.position * node.scale
	node.modulate = color
	holder.add_child(node)
	return holder


## Texte aux polices du jeu : titre (Supercell-Magic, contour et ombre) ou corps.
static func label(text: String, font_size: int, color := Color.WHITE, title := true) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = ScTextField.font_for("Supercell-Magic" if title else "SC CCBackBeat")
	ls.font_size = font_size
	ls.font_color = color
	if title:
		ls.outline_size = maxi(4, font_size / 5)
		ls.outline_color = Color(0, 0, 0, 0.95)
		ls.shadow_color = Color(0, 0, 0, 0.95)
		ls.shadow_size = 0
		ls.shadow_offset = Vector2(0, maxf(2.0, font_size / 10.0))
	l.label_settings = ls
	return l


## Rend un Control cliquable : enfoncement à l'appui, `action` au relâcher sans glissé.
static func make_button(ctrl: Control, action: Callable, sound := "button_click_02", animate := true) -> Control:
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	var state := {"at": Vector2.INF}
	ctrl.gui_input.connect(func(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
			if e is InputEventMouseMotion and state.at != Vector2.INF and e.position.distance_to(state.at) > TAP_SLOP:
				state.at = Vector2.INF
				if animate:
					_press(ctrl, false)
			return
		if e.pressed:
			state.at = e.position
			if animate:
				_press(ctrl, true)
		else:
			var tap: bool = state.at != Vector2.INF and e.position.distance_to(state.at) <= TAP_SLOP
			state.at = Vector2.INF
			if animate:
				_press(ctrl, false)
			if tap and ctrl.is_visible_in_tree():
				if sound != "":
					Sounds.ui(sound)
				action.call())
	return ctrl


static func _press(ctrl: Control, down: bool) -> void:
	ctrl.pivot_offset = ctrl.size / 2
	var t := ctrl.create_tween()
	t.tween_property(ctrl, "scale", Vector2.ONE * (0.92 if down else 1.0), 0.06 if down else 0.12)


## Bouton du jeu : fond 9-slice btn_<couleur>_big de ui_common et texte titre centré.
static func text_button(color: String, text: String, size: Vector2, action: Callable, font_size := 0) -> Control:
	var b := panel("ui_common", "btn_%s_big" % color, size, Color.WHITE, size.y / 54.0 / k() * 0.9)
	var l := label(text, font_size if font_size > 0 else int(size.y * 0.36))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(size.x, size.y * 0.9)
	l.clip_text = true
	b.add_child(l)
	return make_button(b, action)


## Cache des enfants (chemins) d'un clip.
static func hide(node: Node2D, paths: Array) -> void:
	if node is ScMovieClip:
		for p in paths:
			(node as ScMovieClip).set_sc_visible(p, false)


## Texte d'un champ (chemin) d'un clip.
static func set_text(node: Node2D, path: String, text: String) -> void:
	if node is ScMovieClip:
		(node as ScMovieClip).set_text(path, text)


## Ouvre une fenêtre par-dessus tout le menu (et non dans la page qui la demande, rognée).
static func popup(from: Node, window: Control) -> void:
	var host: Node = from
	while host.get_parent() != null and not (host is MainMenu) and not (host.get_parent() is Window):
		host = host.get_parent()
	host.add_child(window)


## Texte du premier champ trouvé sous `path` (champs sans nom d'instance).
static func set_any_text(node: Node2D, path: String, text: String) -> void:
	var holder: Node = (node as ScMovieClip).get_sc(path) if node is ScMovieClip and path != "" else node
	if holder == null:
		return
	if holder is ScTextField:
		holder.set_text(text)
		return
	for n in holder.find_children("*", "Node2D", true, false):
		if n is ScTextField:
			n.set_text(text)
			return


## Bannière de combat de la 16.4 (ui_battle_banners) : ruban `bg` (blue, green, purple, yellow,
## red) et emblème `fg` (green = épées, purple = couronnes, yellow = cible).
const BANNER_BGS := ["green", "blue", "purple", "yellow", "red"]
const BANNER_FGS := ["yellow", "purple", "green"]


static func banner(bg := "green", fg := "yellow") -> Node2D:
	var root := clip("ui_battle_banners", "battle_banner_main_screen") as ScMovieClip
	if root == null:
		return Node2D.new()
	hide(root, ["shadow", "badges", "badges_editor", "badges_profile"])
	var lib := ScLibrary.get_library("ui_battle_banners")
	var bg_name := "banner_bg_" + (bg if bg in ["blue", "red"] else "default_" + bg)
	if lib.has_export(bg_name):
		root.attach("banner_bg", lib.create_export(bg_name))
	if lib.has_export("banner_fg_default_" + fg):
		root.attach("banner_fg", lib.create_export("banner_fg_default_" + fg))
	return root


## Fond des menus de la 16.4 : losanges bleus (motif de main_screen_bg) répétés, dégradé sombre
## en haut et en bas, halo central.
static func menu_background(size: Vector2) -> Control:
	var root := Control.new()
	root.size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = true
	var tile_node := clip("ui_main_screen_royals", "main_screen_bg/background")
	var tb := ScMovieClip.bounds_of(tile_node)
	tile_node.free()
	var s := k() * 0.9
	var step := tb.size * s
	var tiles := Node2D.new()
	root.add_child(tiles)
	for y in range(0, int(ceil(size.y / step.y)) + 1):
		for x in range(0, int(ceil(size.x / step.x)) + 1):
			var t := clip("ui_main_screen_royals", "main_screen_bg/background")
			t.scale = Vector2.ONE * s
			t.position = Vector2(x, y) * step - tb.position * s
			tiles.add_child(t)
	var grad := clip("ui_main_screen_royals", "main_screen_bg/gradient")
	var gb := ScMovieClip.bounds_of(grad)
	grad.scale = Vector2(size.x / gb.size.x, size.y / gb.size.y)
	grad.position = -gb.position * grad.scale
	root.add_child(grad)
	return root
