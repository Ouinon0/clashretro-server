class_name DeckCycle
extends RefCounted
## Cycle des cartes (identifiants GameDB) : 4 en main, la suivante affichée, la carte jouée
## repart en fin de file.

var hand: Array = []
var queue: Array = []


## `shuffle` faux : l'ordre du deck est gardé (tutoriel : les cartes à poser sont en main).
func _init(deck: Array, seed_value: int, shuffle := true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cards := deck.duplicate()
	for i in range(cards.size() - 1, 0, -1 if shuffle else cards.size()):
		var j := rng.randi_range(0, i)
		var t = cards[i]
		cards[i] = cards[j]
		cards[j] = t
	hand = cards.slice(0, 4)
	queue = cards.slice(4)


func next_card() -> String:
	return queue[0] if not queue.is_empty() else ""


func play(slot: int) -> String:
	var card: String = hand[slot]
	hand[slot] = queue.pop_front()
	queue.append(card)
	return card
