class_name CardView
extends Control
## Carte de collection comme dans la 16.4 : spell_card_full (illustration, cadre de rareté, élixir),
## bandeau « Niveau N » à la couleur de la rareté, et sous la carte la jauge de cartes (flèche
## bleue, verte quand l'amélioration est possible). Non trouvée : grisée, arène de déblocage.
## Signal `pressed` au toucher.

signal pressed(card_id: String)

const HIDDEN := ["card_sale_tag", "card_boost_tag", "rarity_glow", "card_evolution_frame", "card_evolution",
	"frame_champion", "card_level_top", "card_level_small", "trade_count", "material_count", "card_name",
	"card_level", "new_tag"]
const RARITY_COLORS := {"Common": Color("3d78d6"), "Rare": Color("e3801c"), "Epic": Color("9433d6"),
	"Legendary": Color("2fb8c9")}

var card_id := ""
var with_progress := true
var _clip: ScMovieClip
var _art_h := 0.0
var _band: Control
var _band_label: Label
var _socle: Node2D
var _progress: ScMovieClip
var _locked_label: Label
var _press_at := Vector2.INF


## Illustration de la carte dans ui_spells.sc : celle de la 16.4, sinon celle de la 1.9.
static func icon_name(card: Dictionary) -> String:
	var icons := ScLibrary.get_library("ui_spells")
	for name in [card.get("icon", ""), card.data.get("IconFile", "")]:
		if name != "" and icons.has_export(name):
			return name
	return ""


## `width` : largeur de la carte à l'écran ; `progress` : jauge sous la carte.
static func make(id: String, width: float, progress := true) -> CardView:
	var v := CardView.new()
	v.card_id = id
	v.with_progress = progress
	v._build(width)
	return v


func _build(width: float) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var card := GameDB.card(card_id)
	_clip = ScLibrary.create("ui", "spell_card_full") as ScMovieClip
	for n in HIDDEN:
		_clip.set_sc_visible(n, false)
	var legendary: bool = card.rarity == "Legendary"
	_clip.set_sc_visible("frame", not legendary)
	_clip.set_sc_visible("frame_legendary", legendary)
	for f in ["frame", "frame_legendary"]:
		var frame := _clip.get_sc(f) as ScMovieClip
		if frame:
			frame.goto_and_stop(0)
	var icons := ScLibrary.get_library("ui_spells")
	var icon := CardView.icon_name(card)
	if icon != "":
		_clip.attach("card_image", icons.create_export(icon), true,
				ScLibrary.create("ui", "card_mask_legendary" if legendary else "card_mask_normal"))
	_clip.set_text("elixar_count/count", str(card.cost))
	var b := ScMovieClip.bounds_of(_clip.get_sc("frame"))
	var k := width / maxf(1.0, b.size.x)
	_clip.scale = Vector2.ONE * k
	_clip.position = -b.position * k
	add_child(_clip)
	_art_h = b.size.y * k
	# Bandeau du niveau, en bas de l'illustration.
	var band_h := _art_h * 0.17
	_band = ScUi.panel("ui_common", "bg_r6", Vector2(width * 0.84, band_h), RARITY_COLORS.get(card.rarity, Color.GRAY), 0.6)
	_band.position = Vector2(width * 0.08, _art_h * 0.79 - band_h / 2)
	add_child(_band)
	_band_label = ScUi.label("", int(band_h * 0.62))
	_band_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_band_label.size = _band.size
	_band.add_child(_band_label)
	_locked_label = ScUi.label("", int(width * 0.11), Color("d9b3ff"))
	_locked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locked_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_locked_label.position = Vector2(0, _art_h * 0.6)
	_locked_label.size = Vector2(width, _art_h * 0.4)
	add_child(_locked_label)
	var h := _art_h
	if with_progress:
		# Socle et jauge de la 16.4, dessinés dans le repère de la carte (sous l'illustration).
		_socle = ScUi.clip("ui_deck_builder", "card_item_progress_bg")
		_socle.transform = _clip.transform
		add_child(_socle)
		move_child(_socle, 0)
		_progress = ScUi.clip("ui_deck_builder", "card_item_progress") as ScMovieClip
		_progress.transform = _clip.transform
		add_child(_progress)
		var sb := ScMovieClip.bounds_of(_socle)
		h = (sb.end.y - b.position.y) * k
	custom_minimum_size = Vector2(width, h)
	size = custom_minimum_size
	refresh()


## Niveau, cartes possédées, verrou (carte pas encore trouvée), nouveauté.
func refresh() -> void:
	var card := GameDB.card(card_id)
	var owned := Player.has_card(card_id)
	var level := Player.card_level(card_id)
	_clip.set_sc_visible("lock", false)
	_band.visible = owned
	_band_label.text = GameDB.format("TID_LEVEL", {"LEVEL": GameDB.display_level(card.rarity, level)})
	_locked_label.visible = not owned
	if not owned:
		_locked_label.text = "Déblocage\nArène %d" % maxi(1, int(card.get("arena", 1)))
	modulate = Color.WHITE if owned else Color(0.6, 0.6, 0.65)
	_clip.modulate = Color.WHITE if owned else Color(0.75, 0.75, 0.75)
	if _progress == null:
		return
	var info := Player.upgrade_info(card_id)
	_progress.visible = owned
	_socle.visible = true
	var ratio := 1.0
	var ready := false
	if info.is_empty():
		_progress.set_text("card_count", "Max" if owned else "")
	else:
		ready = info.have >= info.cards
		ratio = clampf(float(info.have) / maxf(1, info.cards), 0.0, 1.0)
		_progress.set_text("card_count", "%d/%d" % [info.have, info.cards])
	for f in ["flow", "flow2"]:
		var flow := _progress.get_sc(f) as ScMovieClip
		if flow:
			flow.goto_and_stop(int(ratio * (flow.frames.size() - 1)))
	_progress.set_sc_visible("flow2", ready)
	_progress.set_sc_visible("flow", not ready)
	var arrow := _progress.get_sc("arrow_full") as ScMovieClip
	_progress.set_sc_visible("arrow_full", ready)
	if arrow and ready:
		arrow.play()


func _gui_input(event: InputEvent) -> void:
	# Les touchers arrivent aussi en clics émulés (project.godot) : on ne lit que les clics.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_at = event.position
		elif _press_at != Vector2.INF and event.position.distance_to(_press_at) < 20:
			_press_at = Vector2.INF
			pressed.emit(card_id)
