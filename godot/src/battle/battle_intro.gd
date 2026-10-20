class_name BattleIntro
extends CanvasLayer
## Intro de la 16.4 (pvp_battle_start) : joueur et adversaire, arène, « Combat ! ». Jouée une fois.

signal done

var me := {}
var enemy := {}
var arena_title := ""


func _ready() -> void:
	layer = 8
	var size := ScreenLayout.size()
	var clip := ScLibrary.create("ui", "pvp_battle_start") as ScMovieClip
	clip.position = size / 2
	clip.scale = Vector2.ONE * size.x / 640.0
	add_child(clip)
	for side in [["player", me], ["enemy", enemy]]:
		var info: Dictionary = side[1]
		clip.set_text(side[0] + "/name", info.get("name", ""))
		var clan: String = info.get("clan", "")
		clip.set_text(side[0] + "/clan", clan if clan != "" else GameDB.text("TID_NO_CLAN"))
		clip.set_sc_visible(side[0] + "/txt_visitor", false)
	clip.set_text("arena/arena_name", arena_title)
	clip.set_text("arena/arena_number", "")
	for hidden in ["league", "battle_type_icon", "mode"]:
		clip.set_sc_visible(hidden, false)
	clip.loop = false
	clip.play()
	Sounds.play("ui_menu_general", "big_horn_start_02_v2")
	await clip.finished
	finish()


func finish() -> void:
	if is_queued_for_deletion():
		return
	done.emit()
	queue_free()
