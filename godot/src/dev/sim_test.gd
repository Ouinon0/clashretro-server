extends Node
## Banc de simulation sans écran : deux combats scriptés (1c1 puis 2c2), joués deux fois chacun ;
## les empreintes doivent être identiques. Lancement : godot --headless res://src/dev/sim_test.tscn

const DECK := ["Knight", "Archer", "Fireball", "Giant", "Musketeer", "MiniPekka", "Arrows", "HogRider"]


func _ready() -> void:
	var ok := true
	for players in [2, 4]:
		var a := _run(players)
		var b := _run(players)
		print("%dc%d : %s, vainqueur %d, couronnes %s, unités %d, empreinte %d / %d" % [
				players / 2, players / 2, "OK" if a.sum == b.sum else "DÉSYNCHRO", a.winner, a.crowns,
				a.spawned, a.sum, b.sum])
		ok = ok and a.sum == b.sum and a.spawned > 0
	# Retour en arrière : les poses du joueur 1 arrivent 4 ticks en retard, on revient à
	# l'instantané et on recalcule ; le résultat doit être celui de la simulation directe.
	for players in [2, 4]:
		var direct := _run(players)
		var late := _run(players, 4)
		print("rollback %dc%d : %s (%d / %d)" % [players / 2, players / 2, "OK" if direct.sum == late.sum else "DIFFÉRENT",
				direct.sum, late.sum])
		ok = ok and direct.sum == late.sum
	print("SIMTEST ", "OK" if ok else "ÉCHEC")
	get_tree().quit(0 if ok else 1)


## `lag` > 0 : les poses du joueur 1 ne sont connues que `lag` ticks plus tard (retour en arrière).
func _run(count: int, lag := 0) -> Dictionary:
	var sim := BattleSim.new()
	var snapshots := {}
	var log := []                       # [tick, joueur, carte, niveau, x, y] connus
	var late := []                      # poses du joueur 1 pas encore « reçues »
	sim.match_ticks = 90 * 20
	sim.overtime_ticks = 30 * 20
	var levels := []
	levels.resize(count)
	levels.fill(9)
	sim.setup(levels)
	var spawned := [0]
	sim.entity_spawned.connect(func(_e: Dictionary) -> void: spawned[0] += 1)
	var cycles := []
	for p in count:
		cycles.append(DeckCycle.new(DECK, 1000 + p))
	while not sim.ended and sim.tick < 200 * 20:
		# Toutes les 3 s, chaque joueur pose la première carte abordable de sa main, devant sa tour.
		if sim.tick % 60 == 0:
			for p in count:
				var cycle: DeckCycle = cycles[p]
				for slot in 4:
					var card: String = cycle.hand[slot]
					if sim.can_afford(p, card):
						cycle.play(slot)
						var team := sim.team_of(p)
						var x := 3500 if (p / 2 + sim.tick / 60) % 2 == 0 else 14500
						var y := 20000 if team == 0 else 12000
						if GameDB.card(card).type == "spell":
							y = 6500 if team == 0 else 25500
						if lag > 0 and p == 1:
							late.append([sim.tick + 1, p, card, 0, x, y])
						else:
							log.append([sim.tick + 1, p, card, 0, x, y])
							sim.schedule(sim.tick + 1, p, card, 0, x, y)
						break
		if lag > 0:
			for cmd in late.duplicate():
				if sim.tick >= cmd[0] + lag:
					late.erase(cmd)
					log.append(cmd)
					var now := sim.tick
					sim.load_state(snapshots[cmd[0]])
					sim.clear_pending()
					for c in log:
						if c[0] >= sim.tick:
							sim.schedule(c[0], c[1], c[2], c[3], c[4], c[5])
					sim.silent = true
					while sim.tick < now:
						snapshots[sim.tick] = sim.save_state()
						sim.step()
					sim.silent = false
			snapshots[sim.tick] = sim.save_state()
		sim.step()
	return {"sum": sim.checksum(), "winner": sim.winner, "crowns": sim.crowns, "spawned": spawned[0]}
