class_name BattleScreen
extends Node
## Écran de combat : vue (BattleView), HUD d'origine de la 16.4 (HUD_player, HUD_topRight,
## HUD_topLeft, HUD_rightMiddle), main de 4 cartes, élixir, pose par glisser-déposer ou
## toucher-toucher. Entraînement contre l'IA (1c1 ou 2c2), ou combat en ligne : `online` = message
## « match » du serveur, poses immédiates et retours en arrière (NetBattle), fin donnée par le serveur.

signal finished(result: Dictionary)

const DEPLOY_DELAY := 2             # ticks entre la pose et l'apparition (hors ligne)
const HAND_SLOT_SCALE := 0.8
const NEXT_SCALE := 0.45
const SNAP_CELLS := 2               # pose « aimantée » sur la case permise la plus proche
const RADIUS_INDICATOR_UNITS := 2950.0   # rayon représenté par spell_radius_blue

var deck: Array = ["Knight", "Archer", "Giant", "Musketeer", "MiniPekka", "Fireball", "Arrows", "HogRider"]
var opponent_deck: Array = ["Valkyrie", "Wizard", "Prince", "BabyDragon", "Witch", "Barbarians", "Zap", "Pekka"]
var card_level := 9                 # niveau affiché commun en entraînement (1 à 13)
var team_mode := false              # 2c2
var location := ""
var player := 0                     # joueur local dans la simulation
var opponent_name := "Entraînement"
var my_name := ""                   # vide : pseudo du joueur ; en 2c2 « moi & coéquipier »
var online := {}                    # message « match » du serveur (vide : entraînement)

var net: NetBattle
var _countdown: Label
var _intro: BattleIntro
var _emotes := Emotes.new()

var sim := BattleSim.new()
var view: BattleView
var _ais: Array[TrainingAI] = []
var _cycle: DeckCycle
var _hud: ScMovieClip
var _top: ScMovieClip
var _score: ScMovieClip
var _hand_views: Array[ScMovieClip] = []
var _next_view: ScMovieClip
var _hand_slots: Array[Vector2] = []
var _next_pos := Vector2.ZERO
var _hud_scale := 1.0
var _overlay := CanvasLayer.new()
var _acc := 0.0
var _ended := false
var _selected := -1
var _dragging := -1
var _drag_moved := false
var _press_pos := Vector2.ZERO
var _ghost: Node3D
var _ghost_label: Node2D
var _ghost_card := ""
var _forbidden: Node2D
var _elixir_geo := {}
var _crowns_heard := 0


func _ready() -> void:
	var size := ScreenLayout.size()
	var count := 4 if team_mode else 2
	var levels := []
	levels.resize(count)
	levels.fill(card_level)
	if not online.is_empty():
		var players: Array = online.players
		count = players.size()
		team_mode = count == 4
		player = online.you
		deck = online.deck
		location = online.location
		card_level = int(players[player].level)
		levels = players.map(func(p: Dictionary) -> int: return p.level)
		sim.setup(levels, players.map(func(p: Dictionary) -> int: return p.team))
		sim.apply_rules(online.get("rules", {}))
		var names := []
		var mates := [Profile.get_value("name", "Joueur")]
		for i in players.size():
			if players[i].team != players[player].team:
				names.append(players[i].name)
			elif i != player:
				mates.append(players[i].name)
		opponent_name = " & ".join(names)
		my_name = " & ".join(mates)
		net = NetBattle.new(sim, online)
		Net.message.connect(_on_net_message)
		Net.disconnected.connect(_on_disconnected)
	else:
		sim.setup(levels)
		if team_mode:
			opponent_name = "IA & IA"
	if my_name == "":
		my_name = Profile.get_value("name", "Joueur") + (" & IA" if team_mode and online.is_empty() else "")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--matchlen="):
			sim.match_ticks = int(a.get_slice("=", 1)) * 20
			sim.overtime_ticks = 10 * 20
	var arena: Dictionary = GameDB.arenas()[2]
	if location == "":
		location = arena.team if team_mode else arena.pvp
	_cycle = DeckCycle.new(deck, Time.get_ticks_usec())
	for p in range(1, count if net == null else 0):
		var mine := sim.team_of(p) == sim.team_of(player)
		_ais.append(TrainingAI.new(sim, p, deck if mine else opponent_deck, card_level, 1234 + p))

	_overlay.layer = 2
	_build_hud(size)
	view = BattleView.new(sim, sim.team_of(player))
	view.location = location
	view.hud_height = size.y - _hud_top()
	add_child(view)
	add_child(_overlay)
	_build_top(size)
	_emotes.view = view
	_emotes.layer = _overlay
	add_child(_emotes)
	_emotes.add_button(_overlay, _hud.position + (_next_pos + Vector2(-34, -150)) * _hud_scale, 76.0)
	_emotes.chosen.connect(func(index: int) -> void:
		_emotes.show(index, sim.team_of(player), _side(player))
		if net:
			Net.send({"t": "emote", "i": index}))
	sim.crowns_changed.connect(_update_score)
	_intro = BattleIntro.new()
	_intro.me = {"name": my_name}
	_intro.enemy = {"name": opponent_name}
	var arena_row := {}
	for a in GameDB.arenas():
		if a.pvp == location or a.team == location:
			arena_row = a
	_intro.arena_title = GameDB.arena_title(arena_row) if not arena_row.is_empty() else ""
	_intro.done.connect(func() -> void:
		_intro = null
		Sounds.play("ui_battle_general", "royale_horn_01"))
	add_child(_intro)
	if net:
		net.resynced.connect(func() -> void:
			view.resync()
			_update_score())
		_countdown = Label.new()
		_countdown.add_theme_font_override("font", load("res://assets/gen/font/supercell-magic_0.ttf"))
		_countdown.add_theme_font_size_override("font_size", 120)
		_countdown.add_theme_color_override("font_outline_color", Color.BLACK)
		_countdown.add_theme_constant_override("outline_size", 18)
		_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_countdown.size = Vector2(size.x, 160)
		_countdown.position = Vector2(0, size.y * 0.32)
		_overlay.add_child(_countdown)
	else:
		sim.battle_ended.connect(_on_end)


func _process(delta: float) -> void:
	if _ended:
		return
	if net:
		Net.poll()
		if not net.started():
			_countdown.text = "" if _intro else str(ceili((net.start_ms - Net.server_now()) / 1000.0))
		else:
			if _intro:
				_intro.finish()
			_countdown.visible = false
			net.update()
		_update_hud()
		return
	if _intro:
		_update_hud()
		return
	_acc = minf(_acc + delta, 0.2)
	while _acc >= Rules.TICK_MS / 1000.0:
		_acc -= Rules.TICK_MS / 1000.0
		for ai in _ais:
			ai.on_tick()
		sim.step()
		if _ended:
			return
	_update_hud()


# --- HUD -----------------------------------------------------------------------------------------

func _build_hud(size: Vector2) -> void:
	_hud = ScLibrary.create("ui", "HUD_player") as ScMovieClip
	_hud.set_sc_visible("darken", false)
	_hud.set_sc_visible("elixir_warning", false)
	_hud.set_sc_visible("NextSpellTimer", false)
	_hud.set_sc_visible("ability_location", false)
	_hud.set_sc_visible("elixir_bar/elixirRequirementBar", false)
	_overlay.add_child(_hud)
	# Le HUD (carte suivante + planche) prend toute la largeur, posé sur la zone sûre du bas
	# (contour de la planche et de la carte suivante : le voile « darken » couvre tout l'écran).
	var next_field := _hud.get_sc("nextCard1") as ScTextField
	var next_title := _hud.get_sc("TID_NEXT_CARD") as ScMovieClip
	var bounds := (_hud.base_transform("panel") * ScMovieClip.bounds_of(_hud.get_sc("panel"))).merge(
			next_field.transform * Rect2(next_field.label.position, next_field.label.size)).merge(
			_hud.base_transform("TID_NEXT_CARD") * ScMovieClip.bounds_of(next_title))
	_hud_scale = (size.x - 12) / bounds.size.x
	_hud.scale = Vector2.ONE * _hud_scale
	# Bas de la barre d'élixir juste au-dessus de la zone sûre (comme la 16.4).
	var bar_bottom := (_hud.base_transform("elixir_bar") * ScMovieClip.bounds_of(_hud.get_sc("elixir_bar"))).end.y
	var low := maxf(bar_bottom, (next_field.transform * Rect2(next_field.label.position, next_field.label.size)).end.y)
	_hud.position = Vector2(6 - bounds.position.x * _hud_scale,
			size.y - ScreenLayout.bottom() - 18 - low * _hud_scale)
	# La planche est étirée jusqu'aux bords et sous la zone sûre.
	var panel := _hud.get_sc("panel")
	if panel:
		var pb := _hud.base_transform("panel") * ScMovieClip.bounds_of(panel)
		var left := -_hud.position.x / _hud_scale
		var right := (size.x - _hud.position.x) / _hud_scale
		var bottom := (size.y - _hud.position.y) / _hud_scale
		var kx := (right - left) / pb.size.x
		var ky := (bottom - pb.position.y) / pb.size.y
		_hud.set_sc_adjust("panel", Transform2D(0, Vector2(kx, ky), 0,
				Vector2(left - pb.position.x * kx, pb.position.y - pb.position.y * ky)))
	_build_hud_panel(size)
	var area := _hud.get_sc("cardArea") as ScTextField
	var rect := area.transform * Rect2(area.label.position, area.label.size)
	for i in 4:
		_hand_slots.append(Vector2(rect.position.x + rect.size.x * (i + 0.5) / 4.0, rect.get_center().y))
	var next := _hud.get_sc("nextCard1") as ScTextField
	_next_pos = (next.transform * Rect2(next.label.position, next.label.size)).get_center()
	_hud.set_text("TID_NEXT_CARD/TID_NEXT_CARD", GameDB.text("TID_NEXT_CARD"))
	for field in _hud.find_children("TID_MAX_ELIXIR", "", true, false):
		if field is ScTextField:
			field.set_text(GameDB.format("TID_MAX_ELIXIR", {"MAX_MANA": BattleSim.ELIXIR_MAX}))
	_refresh_hand()


## Planche bleue de la 16.4 (la « panel » du fichier n'est qu'un aplat recoloré par le jeu) :
## colonne foncée à gauche (emote, carte suivante), zone claire de la main à droite.
func _build_hud_panel(size: Vector2) -> void:
	_hud.set_sc_visible("panel", false)
	var top := _hud_top() + 8.0
	var next := _hud.get_sc("nextCard1") as ScTextField
	var split := _hud.position.x + (next.transform * Rect2(next.label.position, next.label.size)).end.x * _hud_scale + 14
	var bg := Control.new()
	bg.position = Vector2(0, top)
	bg.size = Vector2(size.x, size.y - top)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := ColorRect.new()
	base.color = Color("143a86")
	base.size = bg.size
	bg.add_child(base)
	var left := ScUi.panel("ui_common", "bg_r16", Vector2(split - 6, bg.size.y + 30), Color("1b4fae"), 0.8)
	left.position = Vector2(-4, 4)
	bg.add_child(left)
	var right := ScUi.panel("ui_common", "bg_r16", Vector2(size.x - split + 10, bg.size.y + 30), Color("2a6fe2"), 0.8)
	right.position = Vector2(split, 4)
	bg.add_child(right)
	var shine := ScUi.panel("ui_common", "bg_r16", Vector2(size.x - split - 6, 18), Color(1, 1, 1, 0.12), 0.5)
	shine.position = Vector2(split + 8, 10)
	bg.add_child(shine)
	_overlay.add_child(bg)
	_overlay.move_child(bg, _hud.get_index())


func _hud_top() -> float:
	var area := _hud.get_sc("cardArea") as ScTextField
	var rect := area.transform * Rect2(area.label.position, area.label.size)
	return _hud.position.y + (rect.position.y - 40.0) * _hud_scale


func _build_top(size: Vector2) -> void:
	var k := size.x / 640.0
	_top = ScLibrary.create("ui", "HUD_topRight") as ScMovieClip
	_top.goto_and_stop(0)
	_top.scale = Vector2.ONE * k
	_top.position = Vector2(size.x - 6, 6 + ScreenLayout.top())
	_top.set_sc_visible("elixirRegen", false)
	_overlay.add_child(_top)
	var enemy := ScLibrary.create("ui", "HUD_topLeft") as ScMovieClip
	enemy.scale = Vector2.ONE * k
	enemy.position = Vector2(6, 6 + ScreenLayout.top())
	enemy.set_sc_visible("darken", false)
	enemy.set_text("enemyName/txt", opponent_name)
	enemy.set_text("enemyClan/txt", GameDB.text("TID_NO_CLAN"))
	enemy.set_text("enemyTrophies/txt", "")
	_overlay.add_child(enemy)
	_score = ScLibrary.create("ui", "HUD_rightMiddle") as ScMovieClip
	_score.scale = Vector2.ONE * k
	_score.position = Vector2(size.x - 44 * k, view.map.center.y)
	for c in ["cheer_button_blue", "cheer_button_red", "enemy_signal", "player_signal"]:
		_score.set_sc_visible(c, false)
	for star in ["starPlayer", "starEnemy"]:
		var clip := _score.get_sc(star) as ScMovieClip
		if clip:
			clip.goto_and_stop(0)
	_overlay.add_child(_score)
	_update_score()


func _refresh_hand() -> void:
	for v in _hand_views:
		v.queue_free()
	_hand_views.clear()
	for i in 4:
		var v := _card_view(_cycle.hand[i])
		v.scale = Vector2.ONE * HAND_SLOT_SCALE
		v.position = _hand_slots[i] + (Vector2(0, -16) if i == _selected else Vector2.ZERO)
		v.modulate.a = 0.35 if i == _dragging and _drag_moved else 1.0
		_hud.add_child(v)
		_hand_views.append(v)
	if _next_view:
		_next_view.queue_free()
	_next_view = _card_view(_cycle.next_card())
	_next_view.scale = Vector2.ONE * NEXT_SCALE
	_next_view.position = _next_pos
	_hud.add_child(_next_view)


func _card_view(card_id: String) -> ScMovieClip:
	var card := GameDB.card(card_id)
	var v := ScLibrary.create("ui", "spell_card_ingame") as ScMovieClip
	var legendary: bool = card.rarity == "Legendary"
	# Éléments de la 16.4 hors périmètre (Évolutions, Champions, élixir sombre) : masqués.
	for extra in ["frame_champion", "card_evolution_frame", "card_evolution", "dark_elixir_count"]:
		v.set_sc_visible(extra, false)
	v.set_sc_visible("frame", not legendary)
	v.set_sc_visible("frame_legendary", legendary)
	var frame := v.get_sc("frame_legendary" if legendary else "frame") as ScMovieClip
	if frame:
		frame.goto_and_stop(0)
	var icons := ScLibrary.get_library("ui_spells")
	var icon := CardView.icon_name(card)
	if icon != "":
		v.attach("card_image", icons.create_export(icon), true,
				ScLibrary.create("ui", "card_mask_legendary" if legendary else "card_mask_normal"))
	v.set_text("elixar_count/count", str(card.cost))
	return v


func _update_hud() -> void:
	var e := sim.elixir(player)
	_layout_elixir_bar(e)
	_hud.set_text("elixir_bar/elixirBarLeftNumbers/elixirAmount/txt", str(int(e)))
	var max_label := _hud.get_sc("elixir_bar/elixirBarLeftNumbers/TID_MAX_ELIXIR")
	if max_label:
		max_label.visible = int(e) >= 10
	for i in _hand_views.size():
		var ok := e >= sim.card_cost(_cycle.hand[i])
		_hand_views[i].modulate = Color.WHITE if ok else Color(0.55, 0.55, 0.55)
		if i == _dragging and _drag_moved:
			_hand_views[i].modulate.a = 0.35
	var left := maxi(0, sim.time_left_ticks()) / 20
	_top.set_text("timeLeft/txt", "%d:%02d" % [left / 60, left % 60])
	_top.set_sc_visible("elixirRegen", sim.tick >= sim.match_ticks - 60 * 20)
	_top.set_text("TID_TIME_LEFT/TID_TIME_LEFT_vcenter", GameDB.text("TID_OVERTIME" if sim.overtime else "TID_TIME_LEFT"))
	_update_music(left)


var _countdown_said := -1


## Musique du combat (2 min, dernière minute, 30 s, prolongation) et compte à rebours des 10 s.
func _update_music(left: int) -> void:
	if sim.overtime:
		Sounds.music("music_arena_general_battle", "sudden_death_01")
	elif left <= 30:
		Sounds.music("music_arena_general_battle", "30_sec_music_loop_01")
	elif left <= 60:
		Sounds.music("music_arena_general_battle", "60_sec_music_loop_01")
	else:
		Sounds.music("music_arena_general_battle", "2min_loop_battle_01")
	if left <= 10 and left > 0 and left != _countdown_said:
		_countdown_said = left
		Sounds.play("ui_battle_general", "%d_cd_02" % left)


## Barre d'élixir assemblée par le code (comme le jeu ; même géométrie qu'en 1.9) : repère local
## de « elixir_bar », 10 points d'élixir = 40,2 unités chacun à partir de x = −1,45 ; le corps
## (7,19 de large) est étiré, l'extrémité et le flux suivent, les séparateurs sont posés à chaque point.
const ELIXIR_LEFT := -1.45
const ELIXIR_STEP := 40.2
const ELIXIR_BODY_W := 7.19


func _layout_elixir_bar(e: float) -> void:
	var bar := _hud.get_sc("elixir_bar") as ScMovieClip
	if bar == null:
		return
	if _elixir_geo.is_empty():
		for n in ["bar_end", "bar_tip", "bar_flow"] + range(1, 10).map(func(i: int) -> String: return "d%d" % i):
			_elixir_geo[n] = bar.base_transform(n).origin.x
		bar.set_sc_visible("ghost", false)
	var tip := ELIXIR_LEFT + ELIXIR_STEP * e
	var k := maxf(0.001, ELIXIR_STEP * e / ELIXIR_BODY_W)
	bar.set_sc_adjust("bar_body", Transform2D(0, Vector2(k, 1), 0, Vector2(ELIXIR_LEFT - ELIXIR_LEFT * k, 0)))
	for n in ["bar_end", "bar_flow", "bar_tip"]:
		bar.set_sc_adjust(n, Transform2D(0, Vector2(tip - _elixir_geo[n], 0)))
	bar.set_sc_visible("bar_tip", e < 10.0)
	bar.set_sc_visible("bar_flow", e < 10.0)
	for i in range(1, 10):
		var n := "d%d" % i
		bar.set_sc_adjust(n, Transform2D(0, Vector2(ELIXIR_LEFT + ELIXIR_STEP * i - 0.4 - _elixir_geo[n], 0)))


func _update_score() -> void:
	var team := sim.team_of(player)
	var total: int = sim.crowns[0] + sim.crowns[1]
	if total > _crowns_heard:
		Sounds.play("ui_battle_general", ["1st_crown_01", "2nd_crown_01", "3rd_crown_01"][clampi(total - 1, 0, 2)])
	_crowns_heard = total
	_score.set_text("scorePlayer/txt", str(sim.crowns[team]))
	_score.set_text("scoreEnemy/txt", str(sim.crowns[1 - team]))


# --- Pose des cartes -----------------------------------------------------------------------------

func _hand_slot_at(pos: Vector2) -> int:
	for i in _hand_views.size():
		var local := _hand_views[i].get_global_transform_with_canvas().affine_inverse() * pos
		if Rect2(-64, -88, 128, 176).has_point(local):
			return i
	return -1


func _in_arena(pos: Vector2) -> bool:
	return pos.y < _hud_top()


func _input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if _ended:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT or event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			var slot := _hand_slot_at(pos)
			if slot >= 0:
				_dragging = slot
				_drag_moved = false
				_press_pos = pos
				get_viewport().set_input_as_handled()
			elif _selected >= 0 and _in_arena(pos):
				_show_ghost(_selected, pos)
			return
		if _dragging >= 0:
			var slot := _dragging
			_dragging = -1
			if _drag_moved and _in_arena(pos):
				_deploy(slot, pos)
			elif not _drag_moved:
				_selected = -1 if _selected == slot else slot
			_hide_ghost()
			_refresh_hand()
			get_viewport().set_input_as_handled()
		elif _selected >= 0 and _in_arena(pos):
			_deploy(_selected, pos)
			_hide_ghost()
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		if _dragging < 0:
			return
		var pos: Vector2 = event.position
		if not _drag_moved and pos.distance_to(_press_pos) > 12:
			_drag_moved = true
			_selected = -1
			_refresh_hand()
		if _drag_moved:
			if _in_arena(pos):
				_show_ghost(_dragging, pos)
			else:
				_hide_ghost()
		get_viewport().set_input_as_handled()


## Case visée (centre de case) d'un point de l'écran.
func _snap(pos: Vector2) -> Vector2i:
	var at := view.map.to_arena(pos)
	return Vector2i(clampi(at.x / 1000 * 1000 + 500, 500, Rules.ARENA_W - 500),
			clampi(at.y / 1000 * 1000 + 500, 500, Rules.ARENA_H - 500))


## Moitié du joueur ; les sorts partout ; la moitié adverse d'un couloir dont la tour est tombée.
func _valid_position(card_id: String, at: Vector2i) -> bool:
	if at.x < 0 or at.x > Rules.ARENA_W or at.y < 0 or at.y > Rules.ARENA_H:
		return false
	var card := GameDB.card(card_id)
	if card.type == "spell" or Rules.flag(card.data, "CanDeployOnEnemySide"):   # sorts, Mineur
		return true
	var team := sim.team_of(player)
	var own_half := at.y >= Rules.RIVER_Y + Rules.RIVER_HALF if team == 0 else at.y <= Rules.RIVER_Y - Rules.RIVER_HALF
	if own_half:
		return true
	var lane := 0 if at.x < 9000 else 1
	for e in sim.entities:
		if e.kind == BattleSim.Kind.TOWER and e.team != team and not e.king and e.lane == lane:
			return false
	var pocket := at.y >= 5000 if team == 0 else at.y <= Rules.ARENA_H - 5000
	return pocket and absi(at.y - Rules.RIVER_Y) > Rules.RIVER_HALF


func _nearest_valid(card_id: String, at: Vector2i) -> Vector2i:
	if _valid_position(card_id, at):
		return at
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dx in range(-SNAP_CELLS, SNAP_CELLS + 1):
		for dy in range(-SNAP_CELLS, SNAP_CELLS + 1):
			var c := at + Vector2i(dx * 1000, dy * 1000)
			var d := Vector2(dx, dy).length()
			if d < best_d and d <= SNAP_CELLS + 0.5 and _valid_position(card_id, c):
				best = c
				best_d = d
	return best


func _deploy(slot: int, pos: Vector2) -> void:
	var card_id: String = _cycle.hand[slot]
	var at := _nearest_valid(card_id, _snap(pos))
	if at.x < 0:
		return
	if sim.elixir(player) < sim.card_cost(card_id):
		var warning := _hud.get_sc("elixir_warning") as ScMovieClip
		if warning:
			warning.visible = true
			_hud.set_text("elixir_warning/txt_anim/TID_MANA_BAR_FULL_NOTIFICATION_vcenter", GameDB.text("TID_NOT_ENOUGH_MANA"))
			warning.play_range(0, 29)
		return
	if net:
		if not net.started() or net.catching_up():
			return
		net.deploy(card_id, _level_of(card_id), at.x, at.y)
	else:
		sim.schedule(sim.tick + DEPLOY_DELAY, player, card_id, _level_of(card_id), at.x, at.y)
	_cycle.play(slot)
	_selected = -1
	_refresh_hand()
	Sounds.play("ui_battle_general", "summon_own_07")


## Aperçu : unités transparentes à leur place (ou rayon du sort), nom et coût, zone interdite.
func _show_ghost(slot: int, pos: Vector2) -> void:
	var card_id: String = _cycle.hand[slot]
	var aimed := _snap(pos)
	var at := _nearest_valid(card_id, aimed)
	if at.x < 0:
		at = aimed
	if _ghost_card != card_id:
		_hide_ghost()
		_ghost_card = card_id
		_build_ghost(card_id)
		if GameDB.card(card_id).type != "spell":
			_show_forbidden(card_id)
	_ghost.position = view.map.to_world(at.x, at.y)
	_ghost_label.position = view.map.to_screen(at.x, at.y) + Vector2(0, -2.6 * view.map.cell_px())
	var ok := _valid_position(card_id, at)
	for unit in _ghost.get_children():
		if unit is Node2D:
			continue
		for mesh: GeometryInstance3D in unit.find_children("*", "GeometryInstance3D", true, false):
			mesh.transparency = 0.45 if ok else 0.75
	_ghost_label.modulate = Color.WHITE if ok else Color(1, 0.45, 0.45)


func _build_ghost(card_id: String) -> void:
	var card := GameDB.card(card_id)
	var data: Dictionary = card.data
	var enemy := false
	_ghost = Node3D.new()
	view.add_world_child(_ghost)
	_ghost_label = Node2D.new()
	_overlay.add_child(_ghost_label)
	if card.type == "spell":
		var radius := Rules.num(data, "Radius")
		radius = Rules.num(GameDB.projectile(data.get("Projectile", "")), "Radius", radius)
		radius = Rules.num(GameDB.area_effect(data.get("AreaEffectObject", "")), "Radius", radius)
		var circle := ScLibrary.create("effects", "spell_radius_blue")
		circle.scale = Vector2.ONE * maxf(0.3, radius / RADIUS_INDICATOR_UNITS) * view.map.sc_scale
		circle.position = Vector2(0, 2.6 * view.map.cell_px())
		_ghost_label.add_child(circle)
	else:
		var unit_name: String = card.unit
		var count := Rules.num(data, "SummonNumber", 1) if card.type == "troop" else 1
		var radius := Rules.num(data, "SummonRadius", 700 if count > 1 else 0)
		var row := GameDB.character(unit_name) if card.type == "troop" else GameDB.building(unit_name)
		var team := sim.team_of(player)
		for i in count:
			var offset := sim._formation(i, count, radius)
			var dy: int = -offset.y if team == 0 else offset.y
			var unit := UnitView.new()
			_ghost.add_child(unit)
			unit.setup({"id": -1, "name": unit_name, "air": Rules.num(row, "FlyingHeight") > 0,
					"radius": Rules.num(row, "CollisionRadius", 500), "data": row}, enemy)
			unit.position = view.map.to_world(9000 + offset.x, 16000 + dy) - view.map.to_world(9000, 16000)
	var label := ScLibrary.create("ui", "spell_placement_text") as ScMovieClip
	label.set_text("txt", GameDB.text(card.name))
	var level := _level_of(card_id)
	label.set_text("level", GameDB.format("TID_LEVEL", {"LEVEL": GameDB.display_level(card.rarity, level)}))
	label.set_text("mana/txt", str(card.cost))
	label.scale = Vector2.ONE * view.map.sc_scale * 0.8
	_ghost_label.add_child(label)


func _hide_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _ghost_label:
		_ghost_label.queue_free()
		_ghost_label = null
	if _forbidden:
		_forbidden.queue_free()
		_forbidden = null
	_ghost_card = ""


## Cases interdites, dessinées au sol avec les pièces d'origine (deployArea_*).
func _show_forbidden(card_id: String) -> void:
	_forbidden = Node2D.new()
	_forbidden.modulate.a = 0.85
	var blocked := {}
	var river := {}
	for tx in 18:
		for ty in 32:
			var at := Vector2i(tx * 1000 + 500, ty * 1000 + 500)
			if absi(at.y - Rules.RIVER_Y) <= Rules.RIVER_HALF:
				river[Vector2i(tx, ty)] = true
			elif not _valid_position(card_id, at):
				blocked[Vector2i(tx, ty)] = true
	var s := -1 if view.map.flipped else 1
	var is_blocked := func(c: Vector2i) -> bool:
		return c.x < 0 or c.x >= 18 or c.y < 0 or c.y >= 32 or blocked.has(c) or river.has(c)
	var base := ScLibrary.create("ui", "deployArea_base")
	var piece := ScMovieClip.bounds_of(base).size
	base.free()
	var cell_scale := Vector2(ArenaMap.CELL_X, ArenaMap.CELL_Y) * view.map.sc_scale / piece
	for c in blocked:
		var up: bool = is_blocked.call(c + Vector2i(0, -s))
		var down: bool = is_blocked.call(c + Vector2i(0, s))
		var left: bool = is_blocked.call(c + Vector2i(-s, 0))
		var right: bool = is_blocked.call(c + Vector2i(s, 0))
		var pieces: Array[String] = []
		if not up and not left:
			pieces.append("deployArea_corner_leftTop")
		elif not up and not right:
			pieces.append("deployArea_corner_rightTop")
		elif not down and not left:
			pieces.append("deployArea_corner_leftBottom")
		elif not down and not right:
			pieces.append("deployArea_corner_rightBottom")
		else:
			pieces.append("deployArea_base")
		var corner := pieces[0] != "deployArea_base"
		if not up and not (corner and pieces[0].ends_with("Top")):
			pieces.append("deployArea_side_top")
		if not down and not (corner and pieces[0].ends_with("Bottom")):
			pieces.append("deployArea_side_bottom")
		if not left and not (corner and pieces[0].contains("left")):
			pieces.append("deployArea_side_left")
		if not right and not (corner and pieces[0].contains("right")):
			pieces.append("deployArea_side_right")
		if up and left and not is_blocked.call(c + Vector2i(-s, -s)):
			pieces.append("deployArea_innerCorner_topLeft")
		if up and right and not is_blocked.call(c + Vector2i(s, -s)):
			pieces.append("deployArea_innerCorner_topRight")
		if down and left and not is_blocked.call(c + Vector2i(-s, s)):
			pieces.append("deployArea_innerCorner_bottomLeft")
		if down and right and not is_blocked.call(c + Vector2i(s, s)):
			pieces.append("deployArea_innerCorner_bottomRight")
		var at := view.map.to_screen(c.x * 1000 + 500, c.y * 1000 + 500)
		for name in pieces:
			var node := ScLibrary.create("ui", name)
			node.position = at
			node.scale = cell_scale
			_forbidden.add_child(node)
	view.add_ground_child(_forbidden)


# --- Fin ---------------------------------------------------------------------------------------

## Niveau (relatif à la rareté) d'une carte du joueur : celui du serveur en ligne, sinon le
## niveau d'entraînement commun.
func _level_of(card_id: String) -> int:
	if online.has("levels"):
		return int(online.levels.get(card_id, 0))
	return GameDB.relative_level(GameDB.card(card_id).rarity, card_level)


## Côté de la bulle d'emote d'un joueur : centre en 1c1, gauche / droite en 2c2.
func _side(p: int) -> int:
	if not team_mode:
		return 0
	var first := true
	for i in sim.players.size():
		if sim.team_of(i) == sim.team_of(p):
			if i == p:
				return -1 if first else 1
			first = false
	return 0


func _on_net_message(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"emote":
			if int(msg.p) != player:
				_emotes.show(int(msg.i), sim.team_of(int(msg.p)), _side(int(msg.p)))
		"cmd":
			net.on_command(msg)
		"end":
			Net.message.disconnect(_on_net_message)
			Net.disconnected.disconnect(_on_disconnected)
			_on_end(int(msg.winner), msg)


## Connexion perdue en combat : retour à l'accueil, qui se reconnecte ; le serveur garde le combat
## 30 s et y renvoie le joueur (journal des poses rejoué en silence).
func _on_disconnected() -> void:
	if _ended:
		return
	_ended = true
	Net.message.disconnect(_on_net_message)
	var label := Style.title("Connexion perdue… reconnexion", 36)
	label.size = Vector2(ScreenLayout.size().x, 60)
	label.position = Vector2(0, ScreenLayout.size().y * 0.42)
	_overlay.add_child(label)
	await get_tree().create_timer(1.0).timeout
	finished.emit({"reconnect": true})


## Quitter le combat : en ligne c'est un abandon (le serveur donne la victoire à l'autre équipe).
func leave() -> void:
	if net and not _ended:
		Net.send({"t": "leave"})
	elif not _ended:
		_on_end(1 - sim.team_of(player))


func _on_end(winner: int, server := {}) -> void:
	_ended = true
	Sounds.stop_music()
	Sounds.play("music_jingle_general", "big_horn_end_02_v2")
	_hide_ghost()
	var team := sim.team_of(player)
	var crowns: Array = server.get("crowns", sim.crowns)
	var result := {"won": winner == team, "draw": winner < 0, "crowns": crowns[team],
		"enemy_crowns": crowns[1 - team], "trophies": server.get("trophies", -1),
		"rewards": server.get("rewards", {})}
	await get_tree().create_timer(1.2).timeout
	var screen := BattleEndScreen.new(result, {"name": my_name}, {"name": opponent_name})
	screen.team_mode = team_mode
	if not online.is_empty():
		var before: int = online.players[player].get("trophies", 0)
		if result.trophies >= 0:
			result.trophy_change = result.trophies - before
	add_child(screen)
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		Sounds.play("music_jingle_general", "scroll_draw_01" if result.draw else ("scroll_win_02" if result.won else "scroll_lose_01")))
	await screen.closed
	finished.emit(result)
