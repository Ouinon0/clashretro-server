class_name BattleEndScreen
extends CanvasLayer
## Écran de fin de la 16.4 (ui_battle_end.sc : pvp_battle_end_new) : joueurs, couronnes qui
## apparaissent une à une, vainqueur ou égalité, trophées gagnés ou perdus, bouton OK.

signal closed

var result: Dictionary
var team_mode := false              # 2c2 : écran pvp_battle_end_2v2 (une équipe par bandeau)
var me: Dictionary
var enemy: Dictionary
var _screen: ScMovieClip
var _ok: Node2D


func _init(battle_result: Dictionary, player_info: Dictionary, enemy_info: Dictionary) -> void:
	result = battle_result
	me = player_info
	enemy = enemy_info
	layer = 10


func _ready() -> void:
	var size := ScreenLayout.size()
	var veil := ColorRect.new()
	veil.color = Color(0.03, 0.06, 0.14, 0.85)
	veil.size = size
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	_screen = ScLibrary.create("ui_battle_end", "pvp_battle_end_2v2" if team_mode else "pvp_battle_end_new") as ScMovieClip
	var area := _screen.get_sc("screen_area") as ScTextField
	var k := 1.0
	if area:
		var r := area.transform * Rect2(area.label.position, area.label.size)
		k = minf(size.x / r.size.x, (size.y - ScreenLayout.top()) / r.size.y)
	_screen.scale = Vector2.ONE * k
	_screen.position = Vector2(size.x / 2, size.y / 2 + ScreenLayout.top() / 2)
	add_child(_screen)
	# Bouton OK : « ok_btn_single » en 1c1 (ok_btn va avec « Rejouer »), « ok_btn » en 2c2.
	_ok = _screen.get_sc("ok_btn_single") if _screen.get_sc("ok_btn_single") else _screen.get_sc("ok_btn")
	for hidden in ["replay_btn", "taunt_enemy", "taunt_player", "again_btn", "loot_season",
			"player_01/league", "player_01/rating", "player_01/trophies_crown_rush", "player_01/crowns_crown_rush"]:
		_screen.set_sc_visible(hidden, false)
	if _ok.name != "ok_btn":
		_screen.set_sc_visible("ok_btn", false)
	_screen.set_sc_visible("draw", result.get("draw", false))
	_fill_player("player_01", me, result.get("crowns", 0), result.get("won", false))
	_fill_player("player_02", enemy, result.get("enemy_crowns", 0),
			not result.get("won", false) and not result.get("draw", false))
	var trophies: int = result.get("trophy_change", 0)
	_screen.set_sc_visible("player_01/trophies", trophies != 0)
	_screen.set_text("player_01/trophies/trophies", ("+%d" % trophies) if trophies > 0 else str(trophies))
	_screen.set_text("loot/TID_REWARD", "")
	_screen.play_range("score_start", "result_end")
	_show_rewards(size)


## Récompenses du serveur (or, coffre gagné ou emplacements pleins), sous les joueurs.
func _show_rewards(size: Vector2) -> void:
	var rewards: Dictionary = result.get("rewards", {})
	if rewards.is_empty():
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.size = Vector2(size.x, 110)
	row.position = Vector2(0, size.y * 0.66)
	add_child(row)
	if int(rewards.get("gold", 0)) > 0:
		row.add_child(Style.icon("ui", "icon_gold", 60))
		row.add_child(Style.title("+%d" % int(rewards.gold), 40))
	var chest: String = rewards.get("chest", "")
	if chest != "":
		row.add_child(Style.icon("ui_chest", ChestOpening.ICONS.get(chest, "Chest_iron"), 90))
	elif result.get("won", false):
		var full := Label.new()
		full.text = "Emplacements de coffres pleins"
		full.add_theme_color_override("font_color", Color("ffb08a"))
		row.add_child(full)


func _fill_player(path: String, info: Dictionary, crowns: int, winner: bool) -> void:
	_screen.set_text(path + "/player_name/name", info.get("name", ""))
	var clan: String = info.get("clan", "")
	_screen.set_text(path + "/player_name/clan", clan if clan != "" else GameDB.text("TID_NO_CLAN"))
	var clip := _screen.get_sc(path) as ScMovieClip
	if clip == null:
		return
	clip.play_range("appear_start", "winner_end" if winner else "appear_end")
	clip.set_sc_visible("winner_txt", winner)
	for i in range(1, 4):
		var crown := clip.get_sc("crown_%d" % i) as ScMovieClip
		clip.set_sc_visible("crown_%d" % i, i <= crowns)
		if crown == null or i > crowns:
			continue
		crown.goto_and_stop("crown_idle")
		get_tree().create_timer(0.5 + 0.3 * i).timeout.connect(func() -> void:
			crown.play_range("crown_appear_start", "crown_appear_end"))


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var button := _ok
	if button == null:
		return
	var local: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * event.position
	if ScMovieClip.bounds_of(button).grow(16).has_point(local):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()
