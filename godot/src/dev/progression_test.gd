extends Node
## Tests de la progression et des clans du serveur (sans réseau) : godot --headless
## res://src/dev/progression_test.tscn → « PROGTEST OK ».

var _fails := []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
		print("ÉCHEC : ", what)


func _ready() -> void:
	var p := Progression.new({"cards_percent": 100, "gold_percent": 100, "unlock_percent": 100})
	var now := 1_800_000_000
	var a := p.new_account(1, "Alice")
	var b := p.new_account(2, "Bob")
	_check(a.cards.size() == 12 and a.deck.size() == 8, "compte de départ")
	# Victoire : trophées, or, coffre.
	var r := p.battle_result(a, true, false, "1v1", now)
	_check(r.trophies == 30 and a.trophies == 30 and r.gold > 0 and r.chest != "", "récompenses de victoire")
	_check(p.start_unlock(a, 0, now) and not p.start_unlock(a, 0, now), "déverrouillage unique")
	_check(p.open_slot(a, 0, now).is_empty() == false or a.gems < 1, "ouverture payée en gemmes")
	var content := p.open_chest(a, "Magic")
	_check(content.cards.size() > 0 and content.gold > 0, "contenu d'un coffre magique")
	# Amélioration.
	a.cards.Knight.n = 10
	a.gold = 1000
	_check(p.upgrade(a, "Knight") and a.cards.Knight.lvl == 1 and a.cards.Knight.n == 8 and a.gold == 995, "amélioration")
	# Boutique.
	var offers := p.shop(a, now)
	_check(offers.size() == 3, "trois offres du jour")
	var gold := int(a.gold)
	_check(p.buy_card(a, 0, now) and int(a.gold) < gold, "achat d'une carte")
	# Clans : création, entrée, demande, don.
	var clans := Clans.new()
	var id := clans.create(a, "Les Royaux")
	_check(id != "" and clans.join(b, id), "création et entrée")
	_check(clans.request(a, "Archer", now, 3600) and not clans.request(a, "Archer", now + 10, 3600), "demande et délai")
	b.cards.Archer.n = 3
	var by_id := {1: a, 2: b}
	var req_id := 0
	for m in clans.clans[id].chat:
		if m.k == "req":
			req_id = m.id
	var before := int(a.cards.Archer.n)
	_check(clans.donate(b, req_id, by_id, p) == 1 and int(a.cards.Archer.n) == before + 1 and b.cards.Archer.n == 2, "don")
	_check(clans.donate(a, req_id, by_id, p) == 0, "pas de don à soi-même")
	clans.leave(b)
	clans.leave(a)
	_check(clans.clans.is_empty(), "clan vide supprimé")
	print("PROGTEST ", "OK" if _fails.is_empty() else "ÉCHEC %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)
