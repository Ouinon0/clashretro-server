extends Node
## Combat automatique pour voir le rendu : deux IA simples posent des cartes à modèle 3D.
## --mode=2v2 pour un 2c2, --arena=PvP_goblin pour le lieu, --team=1 pour voir depuis le haut,
## --seconds=N pour avancer le combat avant la capture.

const DECK := ["Knight", "Archer", "Giant", "Musketeer", "MiniPekka", "Valkyrie", "HogRider", "Wizard",
		"BabyDragon", "Prince", "Pekka", "Witch"]

var sim := BattleSim.new()
var view: BattleView
var _acc := 0.0
var _cycles := []
var _players := 2


func _ready() -> void:
	var team := 0
	var location := "PvP_barbarian"
	var warmup := 0.0
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg == "--mode=2v2":
			_players = 4
		elif arg.begins_with("--arena="):
			location = v
		elif arg.begins_with("--team="):
			team = int(v)
		elif arg.begins_with("--seconds="):
			warmup = float(v)
	var levels := []
	levels.resize(_players)
	levels.fill(9)
	sim.setup(levels)
	for p in _players:
		_cycles.append(DeckCycle.new(DECK.slice(p * 3 % 6, p * 3 % 6 + 8), 77 + p))
	for i in int(warmup * 20):
		_tick()
	view = BattleView.new(sim, team)
	view.location = location
	add_child(view)


func _process(delta: float) -> void:
	_acc += delta
	while _acc >= Rules.TICK_MS / 1000.0:
		_acc -= Rules.TICK_MS / 1000.0
		_tick()


func _tick() -> void:
	if sim.ended:
		return
	if sim.tick % 50 == 0:
		for p in _players:
			var cycle: DeckCycle = _cycles[p]
			for slot in 4:
				var card: String = cycle.hand[slot]
				if sim.can_afford(p, card):
					cycle.play(slot)
					var t := sim.team_of(p)
					var x := 3500 if (p + sim.tick / 50) % 2 == 0 else 14500
					sim.schedule(sim.tick + 1, p, card, 0, x + randi_range(-1500, 1500),
							(21000 if t == 0 else 11000) + randi_range(-2000, 2000))
					break
	sim.step()
