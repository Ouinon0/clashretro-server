class_name NetBattle
extends RefCounted
## Combat en ligne côté client : poses immédiates, retour en arrière à l'arrivée des poses des
## autres (instantanés de la simulation), horloge calée sur le serveur (Protocol).

signal resynced                     # après un recalcul : l'affichage se réaligne

const SNAPSHOTS := 60               # 3 s d'instantanés
const MAX_STEPS := 8                # ticks rattrapés par image au plus (hors reprise)

var sim: BattleSim
var me := 0
var start_ms := 0.0
var rollbacks := 0                  # statistiques (test)
var rollback_ticks := 0
var _log: Array = []                # [tick, joueur, carte, niveau, x, y, seq] connus
var _snapshots := {}
var _first_snapshot := {}
var _seq := 0
var _sent_sum := 0


func _init(battle: BattleSim, match_msg: Dictionary) -> void:
	sim = battle
	sim.match_ticks = int(match_msg.get("len", sim.match_ticks))
	me = match_msg.you
	start_ms = match_msg.start
	_first_snapshot = sim.save_state()
	for c in match_msg.get("log", []):
		_log.append(c)
		sim.schedule(c[0], c[1], c[2], c[3], c[4], c[5])
		if c[1] == me:                   # combat repris : nos numéros de pose continuent
			_seq = maxi(_seq, c[6])


## Tick auquel la simulation doit être, d'après l'heure du serveur.
func target_tick() -> int:
	return maxi(0, int((Net.server_now() - start_ms) / Rules.TICK_MS))


## Rattrapage en cours (combat repris) : pas de pose possible.
func catching_up() -> bool:
	return target_tick() - sim.tick >= 40


func started() -> bool:
	return Net.server_now() >= start_ms


## Pose locale : jouée tout de suite (tick suivant), envoyée au serveur.
func deploy(card: String, level: int, x: int, y: int) -> void:
	_seq += 1
	# Jamais dans le passé de l'horloge du serveur (simulation en retard sur l'heure réelle).
	var tick := maxi(sim.tick, target_tick()) + Protocol.INPUT_DELAY
	_log.append([tick, me, card, level, x, y, _seq])
	sim.schedule(tick, me, card, level, x, y)
	Net.send({"t": "cmd", "tick": tick, "card": card, "x": x, "y": y, "seq": _seq})


## Message « cmd » du serveur : écho d'une de nos poses (éventuellement décalée) ou pose d'un autre.
func on_command(msg: Dictionary) -> void:
	var cmd := [int(msg.tick), int(msg.p), str(msg.card), int(msg.level), int(msg.x), int(msg.y), int(msg.seq)]
	if cmd[1] == me:
		for i in range(_log.size() - 1, -1, -1):
			var c: Array = _log[i]
			if c[1] == me and c[6] == cmd[6]:
				if c[0] != cmd[0]:
					var old: int = c[0]
					c[0] = cmd[0]
					c[3] = cmd[3]
					_rewind(mini(old, cmd[0]))
				elif c[3] != cmd[3]:
					c[3] = cmd[3]
					_rewind(cmd[0])
				return
	_log.append(cmd)
	if cmd[0] < sim.tick:
		_rewind(cmd[0])
	else:
		sim.schedule(cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5])


## Avance la simulation jusqu'à l'heure du serveur (rattrapage par blocs après une reprise).
func update() -> void:
	var target := target_tick()
	# Très en retard (combat repris après une coupure) : rattrapage par blocs, sans effets ni sons.
	var catching_up := target - sim.tick >= 40
	var budget := 400 if catching_up else MAX_STEPS
	sim.silent = catching_up
	Sounds.suppressed = catching_up
	while sim.tick < target and budget > 0 and not sim.ended:
		_snapshots[sim.tick] = sim.save_state()
		_snapshots.erase(sim.tick - SNAPSHOTS)
		sim.step()
		budget -= 1
	if catching_up:
		sim.silent = false
		Sounds.suppressed = false
		resynced.emit()
	# Empreinte d'un tick assez ancien pour ne plus bouger (au-delà du retard accepté).
	var safe := sim.tick - 2 * Protocol.MAX_LATE
	var sum_tick := safe - safe % Protocol.SUM_EVERY
	if sum_tick > _sent_sum and _snapshots.has(sum_tick):
		_sent_sum = sum_tick
		var probe := BattleSim.new()
		probe.load_state(_snapshots[sum_tick])
		Net.send({"t": "sum", "tick": sum_tick, "v": probe.checksum()})


## Retour à l'instantané du tick `t` (ou avant), poses reprogrammées, recalcul jusqu'à maintenant.
func _rewind(t: int) -> void:
	var now := sim.tick
	var from := t
	while from > 0 and not _snapshots.has(from):
		from -= 1
		if now - from > SNAPSHOTS:
			break
	var state: Dictionary = _snapshots.get(from, _first_snapshot)
	sim.load_state(state)
	sim.clear_pending()
	for c in _log:
		if c[0] >= sim.tick:
			sim.schedule(c[0], c[1], c[2], c[3], c[4], c[5])
	rollbacks += 1
	rollback_ticks += now - sim.tick
	sim.silent = true
	Sounds.suppressed = true
	while sim.tick < now:
		_snapshots[sim.tick] = sim.save_state()
		sim.step()
	sim.silent = false
	Sounds.suppressed = false
	resynced.emit()
