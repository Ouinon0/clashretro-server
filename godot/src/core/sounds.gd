extends Node
## Sons et musiques de la 16.4 (tools/fmod_export.py : assets/gen/sfx, data/sounds.json).
## play_event : événement FMOD d'un effet (une variante au hasard) ; play(banque, nom) : son
## d'interface ; music(banque, nom) : musique en boucle (fondu). Réglages son / musique du profil.

const DIR := "res://assets/gen/sfx/"
const DATA := "res://assets/gen/data/sounds.json"
const VOICES := 14

var _events := {}
var _players: Array[AudioStreamPlayer] = []
var _music := AudioStreamPlayer.new()
var _music_name := ""
var _cache := {}
var suppressed := false             # rattrapage d'un combat en ligne : rien n'est joué


func _ready() -> void:
	if FileAccess.file_exists(DATA):
		_events = JSON.parse_string(FileAccess.get_file_as_string(DATA)).get("events", {})
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music.volume_db = -6.0
	add_child(_music)


func sound_on() -> bool:
	return Profile.get_value("sound", true)


func music_on() -> bool:
	return Profile.get_value("music", true)


## Événement d'un effet (« soundbanks/card_common_knight/card_common_knight_hit »).
func play_event(path: String, volume_db := 0.0) -> void:
	var files: Array = _events.get(path, [])
	if files.is_empty():
		return
	_play_file(files[randi() % files.size()], volume_db)


## Son d'interface par banque et nom d'échantillon (« ui_battle_general », « 1st_crown_01 »).
func play(bank: String, sample: String, volume_db := 0.0) -> void:
	_play_file(bank + "/" + sample + ".ogg", volume_db)


## Son des menus (banque ui_menu_general : button_click_02, menu_swipe_09…).
func ui(sample: String) -> void:
	play("ui_menu_general", sample, -4.0)


func _play_file(file: String, volume_db: float) -> void:
	if suppressed or not sound_on():
		return
	var stream := _stream(file)
	if stream == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return


func _stream(file: String) -> AudioStream:
	if not _cache.has(file):
		var path := DIR + file
		_cache[file] = load(path) if ResourceLoader.exists(path) else null
	return _cache[file]


## Musique en boucle ; même morceau : rien ne change.
func music(bank: String, sample: String) -> void:
	var name := bank + "/" + sample + ".ogg"
	if name == _music_name or not music_on():
		return
	_music_name = name
	var stream := _stream(name)
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	_music.stream = stream
	_music.volume_db = -30.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", -6.0, 0.8)


func stop_music() -> void:
	_music_name = ""
	if _music.playing:
		var t := create_tween()
		t.tween_property(_music, "volume_db", -40.0, 0.5)
		t.tween_callback(_music.stop)
