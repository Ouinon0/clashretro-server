extends Node
## Règles du jeu (1.9.2) : assets/gen/data/game.json, produit par tools/build_gamedata.py.
## Cartes désignées par leur nom d'origine (« Knight », « Fireball »…), y compris sur le réseau.

const PATH := "res://assets/gen/data/game.json"
const ARENAS_PATH := "res://assets/gen/data/arenas.json"  # tools/build_arenas.py
const TEXTS_PATH := "res://assets/gen/data/texts.json"    # textes de l'interface (1.9.2 + 16.4)
const EFFECTS_PATH := "res://assets/gen/data/effects.json"  # effets et particules de la 16.4

var cards: Array = []              # ordre du jeu d'origine (troupes, bâtiments, sorts)
var _cards := {}
var _models := {}                  # personnage → modèle 3D (assets/gen/units/<modèle>.glb)
var _db := {}
var _arenas := {}
var _texts := {}
var _effects := {}
var language := "fr"


func _ready() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("Règles introuvables : %s (lancer tools/build_gamedata.py)" % PATH)
		return
	# JSON ne connaît que des flottants : on remet les entiers en int (simulation en entiers).
	_db = _ints(JSON.parse_string(f.get_as_text()))
	cards = _db.cards
	for c in cards:
		_cards[c.id] = c
		if c.has("model"):
			_models[c.unit] = c.model
	_models["PrincessTower"] = "princess"
	if OS.get_locale_language() != "fr":
		language = "en"
	if FileAccess.file_exists(TEXTS_PATH):
		_texts = JSON.parse_string(FileAccess.get_file_as_string(TEXTS_PATH))


static func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v):
		return int(v)
	if v is Array:
		return v.map(_ints)
	if v is Dictionary:
		for k in v:
			v[k] = _ints(v[k])
	return v


func card(id: String) -> Dictionary:
	return _cards.get(id, {})


## Modèle 3D d'un personnage ("" si l'unité n'en a pas dans la 16.4).
func model(character_name: String) -> String:
	return _models.get(character_name, "")


## Apparence de la 16.4 d'un objet (FileName, exports, ombres, effets), {} si inconnue.
func visual(name: String) -> Dictionary:
	return _db.get("visuals", {}).get(name, {})


func character(name: String) -> Dictionary:
	return _db.characters.get(name, {})


func building(name: String) -> Dictionary:
	return _db.buildings.get(name, {})


func projectile(name: String) -> Dictionary:
	return _db.projectiles.get(name, {})


func area_effect(name: String) -> Dictionary:
	return _db.area_effects.get(name, {})


func buff(name: String) -> Dictionary:
	return _db.buffs.get(name, {})


func global_int(key: String, fallback: int) -> int:
	return int(_db.globals.get(key, fallback))


## Arènes de la 1.9 dans l'ordre des trophées (id, number, trophies, name, pvp, team).
func arenas() -> Array:
	var list: Array = _db.arenas.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.trophies < b.trophies)
	return list


## Table brute de game.json (exp_levels, chests, chest_order…).
func table(name: String) -> Variant:
	return _db.get(name)


## Nom d'une arène : « Arène 3 : Arène des barbares » (numéro et nom du jeu).
func arena_title(arena: Dictionary) -> String:
	var name := text(arena.get("subtitle", ""))
	return text(arena.name) + (" : " + name if name != "" and name != arena.get("subtitle", "") else "")


func rarity(name: String) -> Dictionary:
	return _db.rarities.get(name, _db.rarities.Common)


## Multiplicateur (en %) d'une statistique au niveau `level` de la rareté (0 = premier niveau).
func power_percent(rarity_name: String, level: int) -> int:
	var power: Array = rarity(rarity_name).power
	return 100 if level <= 0 else int(power[mini(level - 1, power.size() - 1)])


## Niveau relatif à la rareté d'un niveau affiché (échelle commune 1 à 13), borné à la rareté.
func relative_level(rarity_name: String, display: int) -> int:
	var r := rarity(rarity_name)
	return clampi(display - 1 - int(r.relative_level), 0, int(r.levels) - 1)


## Niveau affiché (échelle commune 1 à 13) d'un niveau relatif à la rareté.
func display_level(rarity_name: String, level: int) -> int:
	return level + 1 + int(rarity(rarity_name).relative_level)


## Décor d'un lieu de la 16.4 (« PvP_barbarian ») : fond, décors, ombres.
func arena_layout(location: String) -> Dictionary:
	if _arenas.is_empty() and FileAccess.file_exists(ARENAS_PATH):
		_arenas = _ints(JSON.parse_string(FileAccess.get_file_as_string(ARENAS_PATH)))
	return _arenas.get(location, {})


## Effet de la 16.4 (legacy_vfx) : RenderableComponents, EnemyVersion, Loop, ShakeScreen…
func effect(name: String) -> Dictionary:
	_load_effects()
	return _effects.effects.get(name, {})


## Émetteur de particules de la 16.4.
func emitter(name: String) -> Dictionary:
	_load_effects()
	return _effects.emitters.get(name, {})


func _load_effects() -> void:
	if _effects.is_empty():
		_effects = {"effects": {}, "emitters": {}}
		if FileAccess.file_exists(EFFECTS_PATH):
			_effects = JSON.parse_string(FileAccess.get_file_as_string(EFFECTS_PATH))


func text(tid: String) -> String:
	var t: Dictionary = _texts.get(tid, _db.texts.get(tid, {}))
	return t.get(language, t.get("en", tid))


## Texte avec valeurs : « <NOM> » dans le texte d'origine est remplacé par values.NOM.
func format(tid: String, values: Dictionary) -> String:
	var s := text(tid)
	for k in values:
		s = s.replace("<%s>" % k, str(values[k]))
	return s
