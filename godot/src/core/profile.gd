class_name Profile
extends RefCounted
## Réglages et compte enregistrés sur l'appareil (user://profile.json) : pseudo, jeton du serveur,
## adresse du serveur, deck.

const PATH := "user://profile.json"
const DEFAULT_DECK := ["Knight", "Archer", "Giant", "Musketeer", "MiniPekka", "Fireball", "Arrows", "HogRider"]

static var data := {}


static func get_value(key: String, fallback: Variant = null) -> Variant:
	_load()
	return data.get(key, fallback)


static func set_value(key: String, value: Variant) -> void:
	_load()
	data[key] = value
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


static func deck() -> Array:
	var d: Array = get_value("deck", DEFAULT_DECK)
	return d if d.size() == 8 else DEFAULT_DECK.duplicate()


static func _load() -> void:
	if not data.is_empty():
		return
	if FileAccess.file_exists(PATH):
		var v = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if v is Dictionary:
			data = v
	if data.is_empty():
		data = {"name": "Joueur%d" % (randi() % 10000)}
