class_name Emotes
extends Node
## Emotes du combat : 4 stickers du roi (emotes_king_01_dl : emote1…4, avec leur son) et les
## 6 phrases de la 1.9 (TID_EMOTE1…6). Bouton dans le HUD, sélecteur, bulle au-dessus de la
## tour du roi de l'équipe de l'émetteur. En ligne, le serveur relaie (1 emote / 2 s par joueur).

signal chosen(index: int)

const STICKERS := 4                 # indices 0-3 : stickers ; 4-9 : phrases
const SOUNDS := ["king_happy_01_dl", "king_mad_01_dl", "king_crying_01_dl", "king_laughter_01_dl"]
const COOLDOWN_MS := 2000

var view: BattleView
var layer: CanvasLayer
var _selector: Control
var _last := -COOLDOWN_MS


## Bouton d'emote (icône du roi) à la position donnée, dans `parent`.
func add_button(parent: Node, at: Vector2, size: float) -> void:
	var button := Style.icon("emotes_king_01_dl", "icon1", size)
	button.position = at
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_toggle_selector(at))
	parent.add_child(button)


func _toggle_selector(at: Vector2) -> void:
	if _selector:
		_selector.queue_free()
		_selector = null
		return
	_selector = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.12, 0.26, 0.95)
	box.border_color = Color("6b9be6")
	box.set_border_width_all(3)
	box.set_corner_radius_all(20)
	box.set_content_margin_all(14)
	_selector.add_theme_stylebox_override("panel", box)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_selector.add_child(grid)
	for i in STICKERS:
		var icon := Style.icon("emotes_king_01_dl", "icon%d" % (i + 1), 96)
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		var index := i
		icon.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed:
				_pick(index))
		grid.add_child(icon)
	for i in 6:
		var b := Style.button(GameDB.text("TID_EMOTE%d" % (i + 1)), Style.BLUE, 20)
		b.custom_minimum_size = Vector2(0, 64)
		var index := STICKERS + i
		b.pressed.connect(func() -> void: _pick(index))
		grid.add_child(b)
	layer.add_child(_selector)
	await get_tree().process_frame
	if _selector:
		_selector.position = Vector2(12, at.y - _selector.size.y - 12)


func _pick(index: int) -> void:
	if _selector:
		_selector.queue_free()
		_selector = null
	if Time.get_ticks_msec() - _last < COOLDOWN_MS:
		return
	_last = Time.get_ticks_msec()
	chosen.emit(index)


## Bulle d'emote au-dessus de la tour du roi de l'équipe `team` (côté `side` en 2c2 : -1, 0, 1).
func show(index: int, team: int, side := 0) -> void:
	var king_y := 29000 if team == 0 else 3000
	var at := view.map.to_screen(9000 + side * 3500, king_y) + Vector2(0, -4.2 * view.map.cell_px())
	var holder := Node2D.new()
	holder.position = at
	layer.add_child(holder)
	if index < STICKERS:
		var lib := ScLibrary.get_library("emotes_king_01_dl")
		var clip := lib.create_export("emote%d" % (index + 1)) as ScMovieClip
		clip.scale = Vector2.ONE * view.map.sc_scale * 0.9
		clip.loop = false
		clip.play()
		holder.add_child(clip)
		Sounds.play("emotes", SOUNDS[index])
	else:
		var bubble := Label.new()
		bubble.text = GameDB.text("TID_EMOTE%d" % (index - STICKERS + 1))
		bubble.add_theme_font_override("font", load(Style.TITLE_FONT))
		bubble.add_theme_font_size_override("font_size", 30)
		bubble.add_theme_color_override("font_color", Style.DARK)
		bubble.add_theme_constant_override("outline_size", 0)
		var box := StyleBoxFlat.new()
		box.bg_color = Color.WHITE
		box.set_corner_radius_all(22)
		box.set_content_margin_all(16)
		box.shadow_color = Color(0, 0, 0, 0.4)
		box.shadow_size = 6
		bubble.add_theme_stylebox_override("normal", box)
		holder.add_child(bubble)
		await get_tree().process_frame
		bubble.position = -bubble.size / 2
		Sounds.play("ui_menu_general", "speech_bubble_tut_03")
	holder.scale = Vector2(0.5, 0.5)
	var t := create_tween()
	t.tween_property(holder, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.4)
	t.tween_property(holder, "modulate:a", 0.0, 0.3)
	t.tween_callback(holder.queue_free)
