class_name BattleSim
extends RefCounted
## Simulation déterministe d'un combat (entiers uniquement, 20 ticks/s), règles de la 1.9.2 (GameDB).
## Équipe 0 = en bas (y élevé), équipe 1 = en haut. Joueurs : 1 par équipe (1c1) ou 2 (2c2), chacun
## avec son élixir ; les tours sont celles de l'équipe. Tous les clients exécutent les mêmes commandes
## aux mêmes ticks et obtiennent donc le même résultat (checksum() pour le vérifier).

signal entity_spawned(e: Dictionary)
signal entity_removed(e: Dictionary)
signal projectile_spawned(p: Dictionary)
signal projectile_hit(p: Dictionary)
signal area_effect(a: Dictionary)
signal attack_started(e: Dictionary)
signal damaged(target: Dictionary, damage: int, attacker_data: Dictionary)
signal crowns_changed
signal battle_ended(winner: int)

enum Kind { TROOP, BUILDING, TOWER }
enum State { DEPLOYING, IDLE, MOVING, ATTACKING }

const MATCH_TICKS := 180 * 20
const DOUBLE_ELIXIR_TICKS := 120 * 20
const OVERTIME_TICKS := 60 * 20

var match_ticks := MATCH_TICKS        # réduit seulement par l'option de test --matchlen
var overtime_ticks := OVERTIME_TICKS
const ELIXIR_MAX := 10
const ELIXIR_START := 5

var tick := 0
var entities: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var areas: Array[Dictionary] = []
var crowns := [0, 0]
var mana_regen_ms := 2800           # élixir en ms de régénération accumulées (2800 ms = 1)
var ended := false
var winner := -1
var overtime := false
## Un dictionnaire par joueur : team, mana_ms, regen_percent (PNJ du tutoriel : plus lent),
## played (cartes jouées, journal), last_card (Miroir : {id, level}), king_level.
var players: Array[Dictionary] = []

var _next_id := 1
var _pending: Array = []            # commandes en attente : [tick, joueur, carte, niveau, x, y]
var _owner := -1                    # joueur à qui appartient ce qui est en cours de création
var _rng := 12345                   # générateur déterministe (Cimetière)
## Vrai pendant un recalcul (retour en arrière du réseau) : aucun signal d'affichage, sauf la fin.
var silent := false


## `king_levels` : niveau de roi de chaque joueur ; `teams` : équipe de chaque joueur
## (par défaut alternées : [0, 1] en 1c1, [0, 1, 0, 1] en 2c2). En 2c2, chaque tour de princesse a
## le niveau de son joueur (gauche : le premier de l'équipe), la tour du roi le plus haut des deux.
func setup(king_levels: Array, teams: Array = []) -> void:
	mana_regen_ms = GameDB.global_int("MANA_REGEN_MS", 28000) / 10
	if teams.is_empty():
		teams = range(king_levels.size()).map(func(i: int) -> int: return i % 2)
	for i in king_levels.size():
		players.append({"team": teams[i], "mana_ms": ELIXIR_START * mana_regen_ms, "regen_percent": 100,
				"played": [], "last_card": {}, "king_level": king_levels[i]})
	for team in 2:
		var levels: Array = players.filter(func(p: Dictionary) -> bool: return p.team == team) \
				.map(func(p: Dictionary) -> int: return p.king_level)
		var top := team == 1
		_add_tower("PrincessTower", team, 3500, 6500 if top else 25500, levels[0])
		_add_tower("PrincessTower", team, 14500, 6500 if top else 25500, levels[-1])
		_add_tower("KingTower", team, 9000, 3000 if top else 29000, levels.max())


## Règles d'un combat d'événement : elixir_percent (vitesse de l'élixir, tous les joueurs),
## start_elixir. Même appel sur le serveur et chez chaque client.
func apply_rules(rules: Dictionary) -> void:
	for p in players:
		p.regen_percent = int(rules.get("elixir_percent", 100))
		if rules.has("start_elixir"):
			p.mana_ms = clampi(int(rules.start_elixir), 0, ELIXIR_MAX) * mana_regen_ms


func team_of(player: int) -> int:
	return players[player].team


func elixir(player: int) -> float:
	return minf(ELIXIR_MAX, float(players[player].mana_ms) / mana_regen_ms)


func time_left_ticks() -> int:
	return (match_ticks + (overtime_ticks if overtime else 0)) - tick


# --- Commandes ---------------------------------------------------------------------------------

## Programme la pose d'une carte (ignorée si l'élixir manque au moment de l'exécution).
func schedule(at_tick: int, player: int, card_id: String, level: int, x: int, y: int) -> void:
	_pending.append([maxi(at_tick, tick), player, card_id, level, x, y])
	_pending.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))


## Déplace une pose encore en attente (écho du serveur avec un autre tick) ; false si déjà jouée.
func reschedule(player: int, old_tick: int, x: int, y: int, new_tick: int) -> bool:
	for cmd in _pending:
		if cmd[0] == maxi(old_tick, 0) and cmd[1] == player and cmd[4] == x and cmd[5] == y:
			_pending.erase(cmd)
			schedule(new_tick, player, cmd[2], cmd[3], x, y)
			return true
	return false


func card_cost(card_id: String) -> int:
	return int(GameDB.card(card_id).get("cost", 0))


func can_afford(player: int, card_id: String) -> bool:
	return elixir(player) >= card_cost(card_id)


func _execute(cmd: Array) -> void:
	var player: int = cmd[1]
	var p: Dictionary = players[player]
	var team: int = p.team
	var card_id: String = cmd[2]
	var entry := GameDB.card(card_id)
	if entry.is_empty():
		return
	var level: int = cmd[3]
	var mana_cost: int = entry.cost
	# Miroir : rejoue la dernière carte du joueur, un niveau au-dessus et 1 élixir de plus.
	var mirror := Rules.flag(entry.data, "Mirror")
	if mirror:
		if p.last_card.is_empty():
			return
		card_id = p.last_card.id
		entry = GameDB.card(card_id)
		level = p.last_card.level + 1
		mana_cost = entry.cost + 1
	var cost := mana_cost * mana_regen_ms
	if p.mana_ms < cost:
		return
	p.mana_ms -= cost
	if not cmd[2] in p.played:
		p.played.append(cmd[2])
	if not mirror:
		p.last_card = {"id": card_id, "level": level}
	var x: int = clampi(cmd[4], 0, Rules.ARENA_W)
	var y: int = clampi(cmd[5], 0, Rules.ARENA_H)
	var card: Dictionary = entry.data
	var rarity: String = entry.rarity
	_owner = player
	if entry.type == "troop":
		var count := Rules.num(card, "SummonNumber", 1)
		var radius := Rules.num(card, "SummonRadius", 700 if count > 1 else 0)
		for i in count:
			var offset := _formation(i, count, radius)
			var dy: int = -offset.y if team == 0 else offset.y
			_spawn_troop(card.get("SummonCharacter", ""), team, x + offset.x, y + dy, level, rarity, true)
		var second: String = card.get("SummonCharacterSecond", "")
		if second != "":
			for i in Rules.num(card, "SummonCharacterSecondCount", 1):
				_spawn_troop(second, team, x, y, level, rarity, true)
	elif entry.type == "building":
		_spawn_building(card.get("SummonCharacter", card.Name), team, x, y, level, rarity)
	else:
		_cast_spell(card, team, x, y, level, rarity)
	_owner = -1


## Positions d'une formation (Archères côte à côte, Gobelins en triangle, Squelettes en cercle).
## Calcul en entiers (sinus de Bhaskara) pour rester identique sur toutes les plateformes.
func _formation(i: int, count: int, radius: int) -> Vector2i:
	if count == 1:
		return Vector2i.ZERO
	if count == 2:
		return Vector2i(-radius if i == 0 else radius, 0)
	if count > 6:
		# Grande horde (Armée de squelettes) : disque plein en tournesol (angle d'or ≈ 137°), comme
		# le jeu ; en cercle, on voyait un anneau le temps que les collisions les resserrent.
		var r := maxi(radius, 280 * _isqrt(count)) * _isqrt(1000000 * (2 * i + 1) / (2 * count)) / 1000
		var golden := (137 * i + 90) % 360
		return Vector2i(r * _cos1000(golden) / 1000, r * _sin1000(golden) / 1000)
	var deg := (360 * i / count + 90) % 360
	return Vector2i(radius * _cos1000(deg) / 1000, radius * _sin1000(deg) / 1000)


## sin(deg) × 1000 en entiers (approximation de Bhaskara I, erreur < 0,2 %).
static func _sin1000(deg: int) -> int:
	deg = posmod(deg, 360)
	var sign := 1
	if deg >= 180:
		deg -= 180
		sign = -1
	var p := deg * (180 - deg)
	return sign * 4000 * p / (40500 - p)


static func _cos1000(deg: int) -> int:
	return _sin1000(deg + 90)


# --- Création ----------------------------------------------------------------------------------

func _base_entity(kind: int, row: Dictionary, team: int, x: int, y: int, level: int, rarity: String) -> Dictionary:
	var e := {
		"id": _next_id, "kind": kind, "name": row.Name, "data": row, "team": team, "owner": _owner, "x": x, "y": y,
		"level": level, "rarity": rarity, "state": State.IDLE, "target": -1, "cooldown": 0, "windup": -1,
		"hp": Rules.scaled(row.get("Hitpoints"), rarity, level), "dir": 9 if team == 1 else 1,
		"radius": Rules.num(row, "CollisionRadius", 500),
		"mass": Rules.num(row, "Mass", 4),
		"range": Rules.num(row, "Range", 500),
		"sight": Rules.num(row, "SightRange", 5500),
		"hit_ticks": maxi(1, Rules.ms_to_ticks(row.get("HitSpeed"))),
		"load_ticks": Rules.ms_to_ticks(row.get("LoadTime")),
		"damage": Rules.scaled(row.get("Damage"), rarity, level),
		"area": Rules.num(row, "AreaDamageRadius"),
		"projectile": row.get("Projectile", ""),
		"air": Rules.num(row, "FlyingHeight") > 0,
		"hits_air": Rules.flag(row, "AttacksAir"),
		"hits_ground": Rules.flag(row, "AttacksGround") or kind == Kind.TOWER,
		"buildings_only": Rules.flag(row, "TargetOnlyBuildings"),
		"speed": Rules.speed_per_tick(row.get("Speed")),
		"deploy": 0, "life": -1, "spawn_timer": -1, "active": true,
		"buffs": {}, "act_acc": 0, "spawn_acc": 0,
		"shield": Rules.scaled(row.get("ShieldHitpoints"), rarity, level),
		"charge_range": Rules.num(row, "ChargeRange"), "charge_dist": 0, "charging": false,
		"damage_special": Rules.scaled(row.get("DamageSpecial"), rarity, level),
		"lock_ticks": 0, "kamikaze": Rules.flag(row, "Kamikaze"),
		"jump": Rules.flag(row, "JumpEnabled"), "self_aoe": Rules.flag(row, "SelfAsAoeCenter"),
		"multi": Rules.num(row, "MultipleTargets", 1),
		"buff_on_damage": row.get("BuffOnDamage", ""),
		"buff_on_damage_ticks": Rules.ms_to_ticks(row.get("BuffOnDamageTime")),
		"tower_pct": 100 + Rules.num(row, "CrownTowerDamagePercent", 0, false),
		"mana_amount": Rules.num(row, "ManaCollectAmount"),
		"mana_ticks": Rules.ms_to_ticks(row.get("ManaGenerateTimeMs")), "mana_timer": 0,
	}
	e.max_hp = e.hp
	_next_id += 1
	return e


func _spawn_troop(char_name: String, team: int, x: int, y: int, level: int, rarity: String, deploy: bool) -> void:
	var row := GameDB.character(char_name)
	if row.is_empty():
		return
	var e := _base_entity(Kind.TROOP, row, team, x, y, level, rarity)
	if deploy:
		e.deploy = maxi(1, Rules.ms_to_ticks(row.get("DeployTime", 1000)))
		e.state = State.DEPLOYING
	_setup_spawner(e, row)
	entities.append(e)
	if not silent:
		entity_spawned.emit(e)
	var spawn_area: String = row.get("SpawnAreaObject", "")
	if spawn_area != "" and deploy:
		_create_area(GameDB.area_effect(spawn_area), spawn_area, team, x, y, level, rarity)


func _spawn_building(building_name: String, team: int, x: int, y: int, level: int, rarity: String) -> void:
	var row := GameDB.building(building_name)
	if row.is_empty():
		return
	var e := _base_entity(Kind.BUILDING, row, team, x, y, level, rarity)
	e.deploy = maxi(1, Rules.ms_to_ticks(row.get("DeployTime", 1000)))
	e.state = State.DEPLOYING
	e.speed = 0
	e.hits_ground = Rules.num(row, "Damage") > 0 or row.get("Projectile", "") != ""
	e.hits_air = Rules.flag(row, "AttacksAir")
	if Rules.num(row, "LifeTime") > 0:
		e.life = Rules.ms_to_ticks(row.get("LifeTime"))
		e.life_total = maxi(1, e.life)
		e.decay_acc = 0
	_setup_spawner(e, row)
	entities.append(e)
	if not silent:
		entity_spawned.emit(e)


func _add_tower(tower_name: String, team: int, x: int, y: int, king_level: int) -> void:
	var row := GameDB.building(tower_name)
	var level := maxi(0, king_level - 1)
	var e := _base_entity(Kind.TOWER, row, team, x, y, level, "Common")
	e.speed = 0
	e.hits_air = true
	e.hits_ground = true
	e.damage = Rules.scaled(GameDB.projectile(row.get("Projectile", "")).get("Damage", 0), "Common", level)
	e.king = tower_name == "KingTower"
	e.active = not e.king
	e.lane = 0 if x < 9000 else 1
	entities.append(e)
	if not silent:
		entity_spawned.emit(e)


func _setup_spawner(e: Dictionary, row: Dictionary) -> void:
	var spawn: String = row.get("SpawnCharacter", "")
	# Certains bâtiments n'ont qu'une pause entre deux rafales (Cabane de gobelins, Pierre tombale).
	if spawn != "" and (Rules.num(row, "SpawnInterval") > 0 or Rules.num(row, "SpawnPauseTime") > 0):
		e.spawn = spawn
		e.spawn_count = Rules.num(row, "SpawnNumber", 1)
		e.spawn_interval = maxi(1, Rules.ms_to_ticks(Rules.num(row, "SpawnInterval")))
		# Rafale (Sorcière : 3 squelettes à 0,3 s d'écart puis 6,4 s de pause) ou groupe à intervalle fixe.
		e.spawn_pause = Rules.ms_to_ticks(Rules.num(row, "SpawnPauseTime"))
		e.spawn_left = e.spawn_count
		e.spawn_timer = Rules.ms_to_ticks(row.get("SpawnStartTime")) + e.deploy


func _cast_spell(card: Dictionary, team: int, x: int, y: int, level: int, rarity: String) -> void:
	# Flèches : le projectile qui frappe est CustomFirstProjectile (ArrowsSpell) ; Projectile
	# (ArrowsSpellDeco, sans dégâts) n'est que la volée décorative dessinée par la vue.
	var proj: String = card.get("CustomFirstProjectile", "")
	if proj == "":
		proj = card.get("Projectile", "")
	if proj != "":
		var p_row := GameDB.projectile(proj)
		# Bûche : posée au point visé, elle roule vers l'adversaire.
		var rolling: String = p_row.get("SpawnProjectile", "")
		if Rules.flag(card, "SpellAsDeploy") and rolling != "":
			_launch_rolling(GameDB.projectile(rolling), team, x, y, level, rarity)
			return
		var king := _tower(team, true)
		var from := Vector2i(king.x if king else x, king.y if king else y)
		var radius := Rules.num(p_row, "Radius", Rules.num(card, "Radius"))
		var dmg := Rules.scaled(p_row.get("Damage", 0), rarity, level)
		_launch(team, from.x, from.y, -1, x, y, p_row, dmg, radius, rarity, level)
		return
	var area_name: String = card.get("AreaEffectObject", "")
	if area_name != "":
		_create_area(GameDB.area_effect(area_name), area_name, team, x, y, level, rarity)


## Zone d'effet (area_effect_objects.csv) : dégâts, buffs, éclairs sur les plus gros, invocations.
func _create_area(a_row: Dictionary, area_name: String, team: int, x: int, y: int, level: int, rarity: String) -> void:
	if a_row.is_empty():
		return
	var life_ms := Rules.num(a_row, "LifeDuration", 50) + Rules.num(a_row, "LifeDurationIncreasePerLevel") * level
	var buff_ms := Rules.num(a_row, "BuffTime") + Rules.num(a_row, "BuffTimeIncreasePerLevel") * level
	var proj := GameDB.projectile(a_row.get("Projectile", ""))
	var a := {"aid": _next_id, "team": team, "x": x, "y": y, "data": a_row, "name": area_name, "level": level, "rarity": rarity,
		"radius": Rules.num(a_row, "Radius", 2500),
		"damage": Rules.scaled(a_row.get("Damage", 0), rarity, level),
		"tower_pct": 100 + Rules.num(a_row, "CrownTowerDamagePercent", 0, false),
		"life": maxi(1, Rules.ms_to_ticks(life_ms)),
		"hit_ticks": Rules.ms_to_ticks(Rules.num(a_row, "HitSpeed")),
		"timer": 0, "buff": a_row.get("Buff", ""), "buff_ticks": maxi(1, Rules.ms_to_ticks(buff_ms)),
		"only_enemies": Rules.flag(a_row, "OnlyEnemies"), "only_own": Rules.flag(a_row, "OnlyOwnTroops"),
		"ignore_buildings": Rules.flag(a_row, "IgnoreBuildings"),
		"air": Rules.flag(a_row, "HitsAir"), "ground": Rules.flag(a_row, "HitsGround"),
		"biggest": Rules.flag(a_row, "HitBiggestTargets"), "projectile": proj, "hit_ids": [],
		"spawn": a_row.get("SpawnCharacter", ""),
		"spawn_ticks": Rules.ms_to_ticks(Rules.num(a_row, "SpawnInterval")),
		"spawn_delay": Rules.ms_to_ticks(Rules.num(a_row, "SpawnInitialDelay")),
		"clone": Rules.flag(a_row, "Clone")}
	_next_id += 1
	if not a.air and not a.ground:
		a.air = true
		a.ground = true
	areas.append(a)
	if not silent:
		area_effect.emit(a)


# --- Boucle ------------------------------------------------------------------------------------

func step() -> void:
	if ended:
		return
	while not _pending.is_empty() and _pending[0][0] <= tick:
		_execute(_pending.pop_front())
	var regen := 2 if tick >= match_ticks - 60 * 20 else 1
	for p in players:
		p.mana_ms = mini(p.mana_ms + Rules.TICK_MS * regen * p.regen_percent / 100, ELIXIR_MAX * mana_regen_ms)
	for e in entities.duplicate():
		if e.hp > 0:
			_update_entity(e)
	_separate()
	for p in projectiles.duplicate():
		_update_projectile(p)
	for a in areas.duplicate():
		_update_area(a)
	_remove_dead()
	tick += 1
	_check_end()


func _update_entity(e: Dictionary) -> void:
	if e.deploy > 0:
		e.deploy -= 1
		if e.deploy == 0:
			e.state = State.IDLE
		return
	_update_buffs(e)
	if e.hp <= 0:
		return
	if e.life > 0:
		e.life -= 1
		# Perte linéaire de max_hp sur toute la durée de vie (accumulateur exact en entiers).
		e.decay_acc += e.max_hp
		e.hp -= e.decay_acc / e.life_total
		e.decay_acc %= e.life_total
		if e.life == 0:
			e.hp = 0
			return
	# Rythme d'action (Rage > 100 %, ralentissement < 100 %, gel = 0) appliqué aux minuteurs.
	var act_steps := _steps(e, "act_acc", _buff_pct(e, "HitSpeedMultiplier"))
	if e.mana_ticks > 0:
		e.mana_timer += 1
		if e.mana_timer >= e.mana_ticks:
			e.mana_timer = 0
			var p: Dictionary = players[e.owner] if e.owner >= 0 else players[e.team]
			p.mana_ms = mini(p.mana_ms + e.mana_amount * mana_regen_ms, ELIXIR_MAX * mana_regen_ms)
	if e.spawn_timer >= 0:
		e.spawn_timer -= _steps(e, "spawn_acc", _buff_pct(e, "SpawnSpeedMultiplier"))
		if e.spawn_timer <= 0:
			_owner = e.owner
			var dy: int = 600 if e.team == 1 else -600
			if e.spawn_pause > 0:
				var i: int = e.spawn_count - e.spawn_left
				var offset := _formation(i, e.spawn_count, 700)
				_spawn_troop(e.spawn, e.team, e.x + offset.x, e.y + offset.y + (dy if e.kind != Kind.TROOP else 0), e.level, e.rarity, false)
				e.spawn_left -= 1
				if e.spawn_left <= 0:
					e.spawn_left = e.spawn_count
					e.spawn_timer = e.spawn_pause
				else:
					e.spawn_timer = e.spawn_interval
			else:
				e.spawn_timer = e.spawn_interval
				for i in e.spawn_count:
					_spawn_troop(e.spawn, e.team, e.x + (i - e.spawn_count / 2) * 400, e.y + (dy if e.kind != Kind.TROOP else 0), e.level, e.rarity, false)
			_owner = -1
	if not e.active:
		return
	if act_steps == 0 and _buff_pct(e, "SpeedMultiplier") == 0:
		e.charging = false
		e.charge_dist = 0
		return
	if e.damage <= 0 and e.projectile == "":
		_move_towards_lane(e)
		return

	var target := _find(e.target)
	if target.is_empty() or target.hp <= 0 or not _can_target(e, target) \
			or (e.kind != Kind.TROOP and _dist(e, target) > e.range + e.radius + target.radius):
		target = _acquire(e)
		e.target = target.id if not target.is_empty() else -1
		e.windup = -1
		e.lock_ticks = 0

	if target.is_empty():
		e.state = State.IDLE
		if e.kind == Kind.TROOP:
			_move_towards_lane(e)
		return

	var reach: int = e.range + e.radius + target.radius
	if _dist(e, target) > reach:
		e.windup = -1
		e.lock_ticks = 0
		if e.kind == Kind.TROOP:
			_move_to(e, target.x, target.y)
		return

	e.state = State.ATTACKING
	e.lock_ticks += 1
	_face(e, target.x, target.y)
	if e.cooldown > 0:
		e.cooldown = maxi(0, e.cooldown - act_steps)
		return
	if e.windup < 0:
		e.windup = e.load_ticks
		if not silent:
			attack_started.emit(e)
	if e.windup > 0:
		e.windup = maxi(0, e.windup - act_steps)
		return
	e.windup = -1
	e.cooldown = e.hit_ticks - e.load_ticks
	var damage: int = _attack_damage(e)
	var targets := [target]
	if e.multi > 1:
		targets.append_array(_extra_targets(e, target, e.multi - 1))
	for t in targets:
		if e.projectile != "":
			var p_row := GameDB.projectile(e.projectile)
			var dmg: int = damage if damage > 0 else Rules.scaled(p_row.get("Damage", 0), e.rarity, e.level)
			var radius := Rules.num(p_row, "Radius")
			_launch(e.team, e.x, e.y, t.id, t.x, t.y, p_row, dmg, radius, e.rarity, e.level, e.data)
		elif e.area > 0:
			var cx: int = e.x if e.self_aoe else t.x
			var cy: int = e.y if e.self_aoe else t.y
			_damage_area(e.team, cx, cy, e.area, damage, e.tower_pct, e.hits_air, true, e.buff_on_damage, e.buff_on_damage_ticks)
		else:
			_hit(t, damage * e.tower_pct / 100 if t.kind == Kind.TOWER else damage, e.team)
			if e.buff_on_damage != "":
				_apply_buff(t, e.buff_on_damage, e.buff_on_damage_ticks, e.team, e.level, e.rarity)
			if not silent:
				damaged.emit(t, damage, e.data)
	e.charging = false
	e.charge_dist = 0
	if e.kamikaze:
		e.hp = 0


## Dégâts du coup : charge (DamageSpecial), montée de l'Enfer (VariableDamage2/3 selon la durée sur la cible).
func _attack_damage(e: Dictionary) -> int:
	if e.charging and e.damage_special > 0:
		return e.damage_special
	var row: Dictionary = e.data
	var t1 := Rules.ms_to_ticks(Rules.num(row, "VariableDamageTime1"))
	if t1 > 0:
		var t2 := Rules.ms_to_ticks(Rules.num(row, "VariableDamageTime2"))
		if e.lock_ticks >= t1 + t2:
			return Rules.scaled(row.get("VariableDamage3"), e.rarity, e.level)
		if e.lock_ticks >= t1:
			return Rules.scaled(row.get("VariableDamage2"), e.rarity, e.level)
	return e.damage


## Cibles supplémentaires (Électro-sorcier : 2), les plus proches à portée.
func _extra_targets(e: Dictionary, first: Dictionary, count: int) -> Array:
	var found: Array = []
	for t in entities:
		if found.size() >= count:
			break
		if t.id != first.id and _can_target(e, t) and _dist(e, t) <= e.range + e.radius + t.radius:
			found.append(t)
	return found


## Nombre de pas d'action ce tick pour un rythme en % (100 = 1 pas, 135 = parfois 2, 0 = aucun).
func _steps(e: Dictionary, key: String, pct: int) -> int:
	e[key] += pct
	var n: int = e[key] / 100
	e[key] -= n * 100
	return n


func _can_target(e: Dictionary, t: Dictionary) -> bool:
	if t.team == e.team or t.hp <= 0 or t.deploy > 0:
		return false
	if e.buildings_only and t.kind == Kind.TROOP:
		return false
	if t.air:
		return e.hits_air
	return e.hits_ground


func _acquire(e: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 1 << 40
	var sight: int = maxi(e.sight, e.range)
	for t in entities:
		if not _can_target(e, t):
			continue
		var d := _dist(e, t)
		var limit: int = sight + t.radius if e.kind == Kind.TROOP else e.range + e.radius + t.radius
		if e.buildings_only and t.kind != Kind.TROOP:
			limit = 1 << 40  # les géants & co. visent le bâtiment le plus proche, où qu'il soit
		if d <= limit and d < best_d:
			best = t
			best_d = d
	return best


## Sans cible en vue, une troupe avance vers la tour de son couloir (puis la tour du roi).
func _move_towards_lane(e: Dictionary) -> void:
	if e.kind != Kind.TROOP or e.speed <= 0:
		return
	var lane := 0 if e.x < 9000 else 1
	var goal := {}
	for t in entities:
		if t.team != e.team and t.kind == Kind.TOWER and t.hp > 0 and not t.king and t.lane == lane:
			goal = t
	if goal.is_empty():
		goal = _tower(1 - e.team, true)
	if goal:
		_move_to(e, goal.x, goal.y)


func _move_to(e: Dictionary, tx: int, ty: int) -> void:
	e.state = State.MOVING
	var gx := tx
	var gy := ty
	# Les troupes au sol traversent la rivière par le pont le plus proche.
	var walks: bool = not e.air and not e.jump   # le Chevaucheur saute la rivière
	var crossing: bool = walks and ((e.y > Rules.RIVER_Y + Rules.RIVER_HALF and ty < Rules.RIVER_Y + Rules.RIVER_HALF) \
			or (e.y < Rules.RIVER_Y - Rules.RIVER_HALF and ty > Rules.RIVER_Y - Rules.RIVER_HALF))
	var on_river: bool = absi(e.y - Rules.RIVER_Y) <= Rules.RIVER_HALF + 200
	if walks and (crossing or on_river):
		var bridge: int = Rules.BRIDGES_X[0] if absi(e.x - Rules.BRIDGES_X[0]) < absi(e.x - Rules.BRIDGES_X[1]) else Rules.BRIDGES_X[1]
		if absi(e.x - bridge) > Rules.BRIDGE_HALF - 300:
			gx = bridge
			gy = Rules.RIVER_Y + (Rules.RIVER_HALF + 300) * (1 if e.y > Rules.RIVER_Y else -1)
		else:
			gx = clampi(tx, bridge - Rules.BRIDGE_HALF + 300, bridge + Rules.BRIDGE_HALF - 300) if on_river else bridge
			gy = ty if not crossing else Rules.RIVER_Y + (Rules.RIVER_HALF + 400) * (-1 if e.y > Rules.RIVER_Y else 1)
	var dx: int = gx - e.x
	var dy: int = gy - e.y
	var d := _isqrt(dx * dx + dy * dy)
	var speed: int = e.speed * _buff_pct(e, "SpeedMultiplier") / 100
	if e.charge_range > 0:
		e.charge_dist += speed
		if e.charge_dist >= e.charge_range * 10:
			e.charging = true
		if e.charging:
			speed = speed * Rules.num(e.data, "ChargeSpeedMultiplier", 200) / 100
	if d <= speed or d == 0:
		e.x = gx
		e.y = gy
	else:
		e.x += dx * speed / d
		e.y += dy * speed / d
	_face(e, gx, gy)
	e.x = clampi(e.x, 0, Rules.ARENA_W)
	e.y = clampi(e.y, 0, Rules.ARENA_H)


## Direction de 1 (vers le haut) à 9 (vers le bas), négative si vers la gauche (miroir des sprites).
func _face(e: Dictionary, tx: int, ty: int) -> void:
	var dx: int = tx - e.x
	var dy: int = ty - e.y
	if dx == 0 and dy == 0:
		return
	var angle := atan2(float(absi(dx)), float(-dy))  # 0 = haut, PI = bas
	var index := 1 + int(round(angle / PI * 8.0))
	e.dir = -index if dx < 0 and index > 1 and index < 9 else index


## Les unités qui se chevauchent s'écartent, les plus lourdes poussent les plus légères.
func _separate() -> void:
	var movers := entities.filter(func(e: Dictionary) -> bool: return e.kind == Kind.TROOP and e.hp > 0)
	for i in movers.size():
		var a: Dictionary = movers[i]
		for j in range(i + 1, movers.size()):
			var b: Dictionary = movers[j]
			if a.air != b.air:
				continue
			var dx: int = b.x - a.x
			var dy: int = b.y - a.y
			var min_d: int = (a.radius + b.radius) * 8 / 10
			if absi(dx) >= min_d or absi(dy) >= min_d:
				continue
			var d := _isqrt(dx * dx + dy * dy)
			if d >= min_d:
				continue
			if d == 0:
				dx = 1 if a.id < b.id else -1
				d = 1
			var push := (min_d - d) / 2
			var total: int = a.mass + b.mass
			a.x -= dx * push * b.mass / total / d * 2
			a.y -= dy * push * b.mass / total / d * 2
			b.x += dx * push * a.mass / total / d * 2
			b.y += dy * push * a.mass / total / d * 2
	for e in entities:
		if e.kind == Kind.TOWER or e.kind == Kind.BUILDING:
			continue
		for b in entities:
			if (b.kind == Kind.TOWER or b.kind == Kind.BUILDING) and b.hp > 0 and not e.air:
				var dx: int = e.x - b.x
				var dy: int = e.y - b.y
				var min_d: int = b.radius + e.radius / 2
				var d := _isqrt(dx * dx + dy * dy)
				if d < min_d and d > 0:
					e.x = b.x + dx * min_d / d
					e.y = b.y + dy * min_d / d


# --- Projectiles, zones, dégâts ------------------------------------------------------------------

func _launch(team: int, x: int, y: int, target_id: int, tx: int, ty: int, row: Dictionary, damage: int,
		radius: int, rarity: String, level: int, source := {}) -> void:
	var p := {"pid": _next_id, "team": team, "x": x, "y": y, "target": target_id, "tx": tx, "ty": ty, "data": row,
		"buff": row.get("TargetBuff", ""), "buff_ticks": Rules.ms_to_ticks(Rules.num(row, "BuffTime")),
		"pushback": Rules.num(row, "Pushback"), "source": source,
		"name": row.get("Name", ""), "damage": damage, "radius": radius,
		"speed": maxi(1, Rules.speed_per_tick(row.get("Speed", 600))),
		"homing": target_id >= 0 and Rules.flag(row, "Homing"),
		"tower_pct": 100 + Rules.num(row, "CrownTowerDamagePercent", 0, false),
		"spawn": row.get("SpawnCharacter", ""), "level": level, "rarity": rarity,
		"air": Rules.flag(row, "AoeToAir") or radius == 0,
		"ground": true}
	_next_id += 1
	projectiles.append(p)
	if not silent:
		projectile_spawned.emit(p)


func _update_projectile(p: Dictionary) -> void:
	if p.get("rolling", false):
		_update_rolling(p)
		return
	if p.homing:
		var t := _find(p.target)
		if not t.is_empty() and t.hp > 0:
			p.tx = t.x
			p.ty = t.y
	var dx: int = p.tx - p.x
	var dy: int = p.ty - p.y
	var d := _isqrt(dx * dx + dy * dy)
	if d > p.speed:
		p.x += dx * p.speed / d
		p.y += dy * p.speed / d
		return
	p.x = p.tx
	p.y = p.ty
	projectiles.erase(p)
	if not silent:
		projectile_hit.emit(p)
	if p.radius > 0:
		_damage_area(p.team, p.x, p.y, p.radius, p.damage, p.tower_pct, true, true, p.buff, p.buff_ticks, p.pushback)
	else:
		var t := _find(p.target)
		if not t.is_empty() and t.hp > 0:
			_hit(t, p.damage * p.tower_pct / 100 if t.kind == Kind.TOWER else p.damage, p.team)
			if p.buff != "":
				_apply_buff(t, p.buff, p.buff_ticks, p.team, p.level, p.rarity)
	if p.spawn != "":
		var count := Rules.num(p.data, "SpawnCharacterCount", 1)
		for i in count:
			var offset := _formation(i, count, 500)
			_spawn_troop(p.spawn, p.team, p.x + offset.x, p.y + offset.y, p.level, p.rarity, false)


## Bûche : rouleau rectangulaire qui avance tout droit et touche chaque ennemi au sol une fois.
func _launch_rolling(row: Dictionary, team: int, x: int, y: int, level: int, rarity: String) -> void:
	var p := {"pid": _next_id, "team": team, "x": x, "y": y, "target": -1, "data": row, "name": row.get("Name", ""),
		"rolling": true, "dir": -1 if team == 0 else 1, "left": Rules.num(row, "ProjectileRange", 10000),
		"speed": maxi(1, Rules.speed_per_tick(row.get("Speed", 200))),
		"half_w": Rules.num(row, "ProjectileRadius", 1950), "half_h": Rules.num(row, "ProjectileRadiusY", 600),
		"damage": Rules.scaled(row.get("Damage", 0), rarity, level),
		"tower_pct": 100 + Rules.num(row, "CrownTowerDamagePercent", 0, false),
		"pushback": Rules.num(row, "Pushback"), "hit_ids": [], "level": level, "rarity": rarity,
		"tx": x, "ty": y + (-1 if team == 0 else 1) * Rules.num(row, "ProjectileRange", 10000)}
	_next_id += 1
	projectiles.append(p)
	if not silent:
		projectile_spawned.emit(p)


func _update_rolling(p: Dictionary) -> void:
	var step: int = mini(p.speed, p.left)
	p.y += p.dir * step
	p.left -= step
	for t in entities:
		if t.team == p.team or t.hp <= 0 or t.air or t.id in p.hit_ids:
			continue
		if absi(t.x - p.x) <= p.half_w + t.radius and absi(t.y - p.y) <= p.half_h + t.radius:
			p.hit_ids.append(t.id)
			_hit(t, p.damage * p.tower_pct / 100 if t.kind == Kind.TOWER else p.damage, p.team)
			if t.kind == Kind.TROOP and not Rules.flag(t.data, "IgnorePushback"):
				t.y = clampi(t.y + p.dir * p.pushback, 0, Rules.ARENA_H)
	if p.left <= 0 or p.y <= 0 or p.y >= Rules.ARENA_H:
		projectiles.erase(p)
		if not silent:
			projectile_hit.emit(p)


func _update_area(a: Dictionary) -> void:
	var pulse: bool = (a.hit_ticks == 0 and a.timer == 0) or (a.hit_ticks > 0 and a.timer % a.hit_ticks == 0)
	if a.biggest:
		# Foudre : à chaque impulsion, l'ennemi le plus résistant pas encore touché.
		if pulse and a.timer > 0:
			_strike_biggest(a)
	elif pulse:
		if a.damage > 0:
			_damage_area(a.team, a.x, a.y, a.radius, a.damage, a.tower_pct, a.air, a.ground)
		if a.buff != "":
			for e in entities.duplicate():
				if _area_affects(a, e):
					_apply_buff(e, a.buff, a.buff_ticks, a.team, a.level, a.rarity, a)
	if a.spawn != "" and a.spawn_ticks > 0 and a.timer >= a.spawn_delay \
			and (a.timer - a.spawn_delay) % a.spawn_ticks == 0:
		var r: int = a.radius * 8 / 10
		var ox := _rand(2 * r + 1) - r
		var oy := _rand(2 * r + 1) - r
		_spawn_troop(a.spawn, a.team, clampi(a.x + ox, 0, Rules.ARENA_W), clampi(a.y + oy, 0, Rules.ARENA_H),
				a.level, a.rarity, true)
	a.timer += 1
	if a.timer >= a.life:
		areas.erase(a)


func _area_affects(a: Dictionary, e: Dictionary) -> bool:
	if e.hp <= 0 or e.deploy > 0:
		return false
	if a.only_enemies and e.team == a.team or a.only_own and e.team != a.team:
		return false
	if a.ignore_buildings and e.kind != Kind.TROOP:
		return false
	if (e.air and not a.air) or (not e.air and not a.ground):
		return false
	return _dist_xy(e.x, e.y, a.x, a.y) <= a.radius + e.radius


func _strike_biggest(a: Dictionary) -> void:
	var best := {}
	for e in entities:
		if e.team != a.team and e.hp > 0 and not e.id in a.hit_ids and _dist_xy(e.x, e.y, a.x, a.y) <= a.radius + e.radius:
			if best.is_empty() or e.hp > best.hp or (e.hp == best.hp and e.id < best.id):
				best = e
	if best.is_empty():
		return
	a.hit_ids.append(best.id)
	var proj: Dictionary = a.projectile
	var damage := Rules.scaled(proj.get("Damage", 0), a.rarity, a.level)
	var pct := 100 + Rules.num(proj, "CrownTowerDamagePercent", 0, false)
	_hit(best, damage * pct / 100 if best.kind == Kind.TOWER else damage, a.team)
	var buff: String = proj.get("TargetBuff", "")
	if buff != "":
		_apply_buff(best, buff, Rules.ms_to_ticks(Rules.num(proj, "BuffTime")), a.team, a.level, a.rarity)
	if not silent:
		projectile_hit.emit({"pid": -1, "team": a.team, "x": best.x, "y": best.y, "data": proj, "name": proj.get("Name", "")})


# --- Buffs (character_buffs.csv) -----------------------------------------------------------------

## Pose ou prolonge un buff : vitesse, rythme d'attaque, dégâts ou soins périodiques, attraction, clone.
func _apply_buff(e: Dictionary, buff_name: String, ticks: int, team: int, level: int, rarity: String, area := {}) -> void:
	var row := GameDB.buff(buff_name)
	if row.is_empty() or e.hp <= 0:
		return
	if Rules.flag(row, "Clone"):
		if e.kind == Kind.TROOP and not e.get("is_clone", false) and not e.get("cloned", false):
			e.cloned = true
			_clone(e)
		return
	if e.kind == Kind.TOWER and (Rules.num(row, "SpeedMultiplier", 0, false) < 0 or Rules.flag(row, "NoEffectToCrownTowers")) \
			and Rules.num(row, "DamagePerSecond") == 0:
		# Les tours couronnées sont gelées mais pas ralenties (Gel et Zap les arrêtent).
		if Rules.num(row, "SpeedMultiplier", 0, false) != -100:
			return
	var b: Dictionary = e.buffs.get(buff_name, {})
	if b.is_empty():
		b = {"row": row, "timer": 0, "team": team, "level": level, "rarity": rarity, "ticks": 0}
		e.buffs[buff_name] = b
	b.ticks = maxi(b.ticks, ticks)
	if not area.is_empty():
		b.area = area


func _update_buffs(e: Dictionary) -> void:
	for buff_name in e.buffs.keys():
		var b: Dictionary = e.buffs[buff_name]
		var row: Dictionary = b.row
		var every := maxi(1, Rules.ms_to_ticks(Rules.num(row, "HitFrequency", 1000)))
		b.timer += 1
		if b.timer % every == 0:
			var dps := Rules.num(row, "DamagePerSecond")
			if dps > 0:
				var dmg := Rules.scaled(dps, b.rarity, b.level) * every * Rules.TICK_MS / 1000
				if e.kind == Kind.TOWER:
					dmg = dmg * (100 + Rules.num(row, "CrownTowerDamagePercent", 0, false)) / 100
				_hit(e, dmg, b.team)
			var heal := Rules.num(row, "HealPerSecond")
			if heal > 0:
				e.hp = mini(e.max_hp, e.hp + Rules.scaled(heal, b.rarity, b.level) * every * Rules.TICK_MS / 1000)
		# Tornade : attire vers le centre de la zone.
		var attract := Rules.num(row, "AttractPercentage")
		if attract > 0 and b.has("area") and e.kind == Kind.TROOP:
			var a: Dictionary = b.area
			var dx: int = a.x - e.x
			var dy: int = a.y - e.y
			var d := _isqrt(dx * dx + dy * dy)
			var pull := Rules.speed_per_tick(60) * attract / 100
			if d > pull:
				e.x += dx * pull / d
				e.y += dy * pull / d
		b.ticks -= 1
		if b.ticks <= 0:
			e.buffs.erase(buff_name)


## Multiplicateur en % d'une colonne de buff (135 = ×1,35 ; −100 = arrêt ; −35 = ×0,65), cumulés.
func _buff_pct(e: Dictionary, column: String) -> int:
	var pct := 100
	for b in e.buffs.values():
		var v := Rules.num(b.row, column, 0, false)
		if v != 0:
			pct = pct * (v if v > 0 else 100 + v) / 100
	return maxi(0, pct)


## Clone : copie à 1 point de vie, posée à côté de l'original.
func _clone(e: Dictionary) -> void:
	var row: Dictionary = e.data
	var c := _base_entity(Kind.TROOP, row, e.team, clampi(e.x + 700, 0, Rules.ARENA_W), e.y, e.level, e.rarity)
	c.hp = 1
	c.max_hp = 1
	c.shield = 0
	c.is_clone = true
	entities.append(c)
	if not silent:
		entity_spawned.emit(c)


## Générateur pseudo-aléatoire entier (identique sur les deux clients).
func _rand(n: int) -> int:
	_rng = (_rng * 1103515245 + 12345 + tick) & 0x7FFFFFFF
	return _rng % maxi(1, n)


func _damage_area(team: int, x: int, y: int, radius: int, damage: int, tower_pct: int, air: bool, ground: bool,
		buff := "", buff_ticks := 0, pushback := 0) -> void:
	for t in entities.duplicate():
		if t.team == team or t.hp <= 0:
			continue
		if (t.air and not air) or (not t.air and not ground):
			continue
		var d := _dist_xy(t.x, t.y, x, y)
		if d <= radius + t.radius:
			_hit(t, damage * tower_pct / 100 if t.kind == Kind.TOWER else damage, team)
			if buff != "":
				_apply_buff(t, buff, buff_ticks, team, 0, "Common")
			if pushback > 0 and t.kind == Kind.TROOP and not Rules.flag(t.data, "IgnorePushback") and d > 0:
				t.x = clampi(t.x + (t.x - x) * pushback / d / 2, 0, Rules.ARENA_W)
				t.y = clampi(t.y + (t.y - y) * pushback / d / 2, 0, Rules.ARENA_H)


func _hit(t: Dictionary, damage: int, from_team: int) -> void:
	if damage <= 0 or t.hp <= 0:
		return
	if t.get("shield", 0) > 0:
		# Le bouclier encaisse le coup entier (le surplus est perdu, comme dans le jeu).
		t.shield = maxi(0, t.shield - damage)
		return
	t.hp -= damage
	if t.kind == Kind.TOWER and t.king and not t.active:
		t.active = true
	if t.hp <= 0:
		t.hp = 0
		if t.kind == Kind.TOWER:
			crowns[from_team] += 3 if t.king else 1
			if not t.king:
				var king := _tower(t.team, true)
				if king:
					king.active = true
			if not silent:
				crowns_changed.emit()


func _remove_dead() -> void:
	for e in entities.duplicate():
		if e.hp > 0:
			continue
		entities.erase(e)
		var row: Dictionary = e.data
		var death_spawn: String = row.get("DeathSpawnCharacter", "")
		if death_spawn != "":
			for i in Rules.num(row, "DeathSpawnCount", 1):
				_spawn_troop(death_spawn, e.team, e.x + (i % 2) * 300, e.y + (i / 2) * 300, e.level, e.rarity, false)
		if Rules.num(row, "DeathDamage") > 0:
			_damage_area(e.team, e.x, e.y, Rules.num(row, "DeathDamageRadius", 1000),
					Rules.scaled(row.get("DeathDamage"), e.rarity, e.level), 100, true, true)
		if not silent:
			entity_removed.emit(e)


func _check_end() -> void:
	var king0 := _tower(0, true)
	var king1 := _tower(1, true)
	if king0.is_empty() or king1.is_empty():
		_finish(1 if king0.is_empty() else 0)
		return
	if tick == match_ticks:
		if crowns[0] != crowns[1]:
			_finish(0 if crowns[0] > crowns[1] else 1)
		else:
			overtime = true
	elif overtime:
		if crowns[0] != crowns[1]:
			_finish(0 if crowns[0] > crowns[1] else 1)
		elif tick >= match_ticks + overtime_ticks:
			_finish(-1)


func _finish(w: int) -> void:
	ended = true
	winner = w
	battle_ended.emit(w)


# --- Outils -------------------------------------------------------------------------------------

func _tower(team: int, king: bool) -> Dictionary:
	for e in entities:
		if e.kind == Kind.TOWER and e.team == team and e.king == king and e.hp > 0:
			return e
	return {}


func _find(id: int) -> Dictionary:
	if id < 0:
		return {}
	for e in entities:
		if e.id == id:
			return e
	return {}


func _dist(a: Dictionary, b: Dictionary) -> int:
	return _dist_xy(a.x, a.y, b.x, b.y)


func _dist_xy(ax: int, ay: int, bx: int, by: int) -> int:
	var dx: int = ax - bx
	var dy: int = ay - by
	return _isqrt(dx * dx + dy * dy)


## Racine carrée entière (identique sur toutes les plateformes, contrairement aux flottants).
static func _isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x := int(sqrt(float(n)))
	while x * x > n:
		x -= 1
	while (x + 1) * (x + 1) <= n:
		x += 1
	return x


## Empreinte de l'état (tick, unités, élixir) : identique chez tous les joueurs s'ils sont synchronisés.
func checksum() -> int:
	var h := tick
	for e in entities:
		h = (h * 31 + e.id * 7 + e.hp * 3 + e.x * 5 + e.y) & 0x7FFFFFFF
	for p in players:
		h = (h * 31 + p.mana_ms) & 0x7FFFFFFF
	return h



# --- Instantanés (retour en arrière du réseau) ----------------------------------------------------

## Copie de l'état, assez profonde pour que la suite de la simulation ne la modifie pas (les lignes
## de données restent partagées : elles ne changent jamais).
func save_state() -> Dictionary:
	var ents: Array[Dictionary] = []
	for e in entities:
		var c: Dictionary = e.duplicate()
		var buffs := {}
		for k in e.buffs:
			buffs[k] = e.buffs[k].duplicate()
		c.buffs = buffs
		ents.append(c)
	var projs: Array[Dictionary] = []
	for p in projectiles:
		var c: Dictionary = p.duplicate()
		if c.has("hit_ids"):
			c.hit_ids = c.hit_ids.duplicate()
		projs.append(c)
	var ars: Array[Dictionary] = []
	for a in areas:
		var c: Dictionary = a.duplicate()
		c.hit_ids = c.hit_ids.duplicate()
		ars.append(c)
	var pls: Array[Dictionary] = []
	for p in players:
		var c: Dictionary = p.duplicate()
		c.played = c.played.duplicate()
		pls.append(c)
	return {"tick": tick, "entities": ents, "projectiles": projs, "areas": ars, "players": pls,
		"crowns": crowns.duplicate(), "ended": ended, "winner": winner, "overtime": overtime,
		"next_id": _next_id, "pending": _pending.duplicate(), "rng": _rng}


## Revient à un instantané (qui reste intact : il peut resservir).
func load_state(state: Dictionary) -> void:
	var copy := _copy_state(state)
	tick = copy.tick
	entities = copy.entities
	projectiles = copy.projectiles
	areas = copy.areas
	players = copy.players
	crowns = copy.crowns
	ended = copy.ended
	winner = copy.winner
	overtime = copy.overtime
	_next_id = copy.next_id
	_pending = copy.pending
	_rng = copy.rng
	# Les buffs de zone (Tornade) pointent vers leur zone : on les rattache aux nouvelles copies.
	var by_aid := {}
	for a in areas:
		by_aid[a.aid] = a
	for e in entities:
		for b in e.buffs.values():
			if b.has("area"):
				b.area = by_aid.get(b.area.aid, b.area)


func _copy_state(state: Dictionary) -> Dictionary:
	var saved := {"entities": entities, "projectiles": projectiles, "areas": areas, "players": players}
	entities = state.entities
	projectiles = state.projectiles
	areas = state.areas
	players = state.players
	var copy := save_state()
	entities = saved.entities
	projectiles = saved.projectiles
	areas = saved.areas
	players = saved.players
	copy.tick = state.tick
	copy.crowns = state.crowns.duplicate()
	copy.ended = state.ended
	copy.winner = state.winner
	copy.overtime = state.overtime
	copy.next_id = state.next_id
	copy.pending = state.pending.duplicate()
	copy.rng = state.rng
	return copy


## Retire les commandes en attente (recalcul : elles sont reprogrammées depuis le journal).
func clear_pending() -> void:
	_pending.clear()