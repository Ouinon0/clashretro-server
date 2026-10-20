class_name Rules
extends RefCounted
## Unités et conversions de la simulation. Distances en millièmes de case (1000 = 1 case),
## temps en millisecondes dans les données, en ticks (20 par seconde) dans la simulation.

const TICK_MS := 50
const ARENA_W := 18000
const ARENA_H := 32000
const RIVER_Y := 16000
const RIVER_HALF := 1000            # rivière sur 2 cases
const BRIDGES_X := [3500, 14500]
const BRIDGE_HALF := 1000


static func scaled(value, rarity: String, level: int) -> int:
	return int(value) * GameDB.power_percent(rarity, level) / 100 if value != null else 0


## Entier d'une colonne (absente → `fallback`, 0 compris si `zero_is_empty`).
static func num(row: Dictionary, key: String, fallback := 0, zero_is_empty := true) -> int:
	var v = row.get(key)
	if v == null or v is String or (zero_is_empty and int(v) == 0):
		return fallback
	return int(v)


static func flag(row: Dictionary, key: String) -> bool:
	return row.get(key, false) == true


static func ms_to_ticks(ms) -> int:
	return int(ms) / TICK_MS if ms != null else 0


## Vitesse des données (60 = « moyenne » = 1 case par seconde) en unités par tick.
static func speed_per_tick(speed) -> int:
	return int(speed) * 1000 * TICK_MS / 60000 if speed != null else 0
