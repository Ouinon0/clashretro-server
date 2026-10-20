class_name TrainingAI
extends RefCounted
## Adversaire d'entraînement : joue ses cartes quand il a l'élixir, en réponse aux attaques ou
## en poussant un couloir. Ses choix sont tirés d'un générateur à graine fixe (rejouable).
## Joue pour un joueur de la simulation (équipe du haut ou du bas, 1c1 ou 2c2).

var sim: BattleSim
var player := 1
var level := 9                      # niveau affiché (échelle commune 1 à 13)
var cycle: DeckCycle
var rng := RandomNumberGenerator.new()
var _wait := 60
## Si donné, appelé à la place de sim.schedule (serveur : la pose est datée et relayée).
var on_play: Callable


func _init(battle: BattleSim, player_index: int, deck: Array, card_level: int, seed_value: int) -> void:
	sim = battle
	player = player_index
	level = card_level
	cycle = DeckCycle.new(deck, seed_value)
	rng.seed = seed_value


func on_tick() -> void:
	_wait -= 1
	if _wait > 0:
		return
	_wait = rng.randi_range(20, 70)
	var slot := rng.randi_range(0, 3)
	var card: String = cycle.hand[slot]
	if not sim.can_afford(player, card) or (sim.elixir(player) < 8 and rng.randf() < 0.35):
		return
	var team := sim.team_of(player)
	var spell: bool = GameDB.card(card).type == "spell"
	var threat := _closest_threat(team)
	if spell and threat.is_empty():
		return
	var x: int
	var y: int
	if spell:
		x = threat.x
		y = threat.y
	elif not threat.is_empty():
		x = clampi(threat.x + rng.randi_range(-1500, 1500), 1000, 17000)
		y = rng.randi_range(9000, 13000)
	else:
		x = Rules.BRIDGES_X[rng.randi_range(0, 1)] + rng.randi_range(-1000, 1000)
		y = rng.randi_range(10000, 14500)
	if team == 0 and not spell:
		y = Rules.ARENA_H - y           # même jeu depuis le bas de l'arène
	cycle.play(slot)
	if on_play.is_valid():
		on_play.call(player, card, x, y)
	else:
		# `level` : niveau affiché commun (1 à 13), ramené à la rareté de la carte.
		sim.schedule(sim.tick + 1, player, card, GameDB.relative_level(GameDB.card(card).rarity, level), x, y)


## Troupe adverse la plus avancée dans notre moitié.
func _closest_threat(team: int) -> Dictionary:
	var best := {}
	for e in sim.entities:
		if e.team == team or e.kind != BattleSim.Kind.TROOP:
			continue
		var depth: int = Rules.ARENA_H - e.y if team == 0 else e.y
		if depth < 18000 and (best.is_empty() or depth < (Rules.ARENA_H - best.y if team == 0 else best.y)):
			best = e
	return best
