extends Node
## Contrôle des sons : chargement de quelques sons, d'événements d'effets et des musiques.


func _ready() -> void:
	var ok := 0
	var bad := []
	for f in ["ui_battle_general/royale_horn_01.ogg", "music_arena_general_battle/2min_loop_battle_01.ogg",
			"music_lobby_202610/music_lobby_202610_a.ogg"]:
		var s = Sounds._stream(f)
		if s:
			ok += 1
			print(f, " ", s.get_length(), " s")
		else:
			bad.append(f)
	var events: Dictionary = Sounds._events
	for path in events.keys().slice(0, 40):
		for f in events[path]:
			if Sounds._stream(f):
				ok += 1
			else:
				bad.append(f)
	print("SONS OK %d, manquants %s" % [ok, bad])
	get_tree().quit()
