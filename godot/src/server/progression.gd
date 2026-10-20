class_name Progression
extends RefCounted
## Progression d'un compte, règles de la 1.9 (serveur seulement) : collection et niveaux de cartes,
## niveau du roi, or et gemmes, trophées et arènes, coffres de victoire (cycle chest_order, 4
## emplacements, déverrouillage un à la fois), coffre gratuit, contenu des coffres
## (treasure_chests : cartes selon l'arène, raretés, or).
##
## Réglages « entre amis » (settings.json du serveur) : cards_percent / gold_percent multiplient
## le contenu des coffres et l'or, unlock_percent raccourcit les déverrouillages.

const SLOTS := 4
const FREE_CHESTS_MAX := 2
const TROPHIES_WIN := 30
const TROPHIES_LOSS := 30
const STARTER_DECK := ["Knight", "Archer", "Giant", "Musketeer", "MiniPekka", "Fireball", "Arrows", "Bomber"]
## access_code : si non vide, il faut ce code pour créer un compte (serveur entre amis).
const DEFAULT_SETTINGS := {"cards_percent": 200, "gold_percent": 200, "unlock_percent": 25, "start_gold": 500,
	"start_gems": 200, "access_code": "", "shop_percent": 50, "request_seconds": 3600,
	"gold_packs": [[1000, 60], [10000, 500], [100000, 4500]], "server_name": "Clash Royale : Modern Classic",
	"access_mode": "invite", "player_invites": 2, "invite_days": 14}
const SHOP_CHESTS := ["Magic", "Giant", "Super"]

var settings := DEFAULT_SETTINGS.duplicate()
var rng := RandomNumberGenerator.new()
## Offres spéciales de l'admin : {id, title, items: [{kind: gold|gems|card|chest, id, n}], price,
## currency (gold|gems), starts, ends (0 = sans fin), limit (achats par joueur, 0 = illimité)}.
var offers: Array = []
## Événements de l'admin (ServerAdmin) : bonus gold_percent / cards_percent pendant leur durée.
var events: Array = []
var news: Array = []


func _init(server_settings := {}) -> void:
	settings.merge(server_settings, true)
	rng.randomize()


## Nouveau compte : cartes du camp d'entraînement au niveau 1, deck de départ.
func new_account(id: int, name: String) -> Dictionary:
	var acc := {"id": id, "name": name, "trophies": 0, "best": 0, "gold": int(settings.start_gold),
		"gems": int(settings.start_gems), "level": 1, "exp": 0, "cards": {}, "deck": STARTER_DECK.duplicate(),
		"chests": [], "cycle": 0, "free_chests": 1, "free_next": 0, "wins": 0, "losses": 0}
	fix(acc)
	return acc


## Complète un compte (nouveaux champs, cartes des arènes atteintes, deck valide).
func fix(acc: Dictionary) -> void:
	var fresh := {"clan": "", "request_next": 0, "best": 0, "gold": 0, "gems": 0, "level": 1, "exp": 0, "cards": {}, "deck": STARTER_DECK.duplicate(),
		"chests": [], "cycle": 0, "free_chests": 1, "free_next": 0, "wins": 0, "losses": 0}
	for k in fresh:
		if not acc.has(k):
			acc[k] = fresh[k]
	for k in ["id", "trophies", "best", "gold", "gems", "level", "exp", "cycle", "free_chests", "free_next", "wins",
			"losses", "request_next"]:
		acc[k] = int(acc.get(k, 0))
	for c in GameDB.cards:
		if int(c.arena) == 0 and not acc.cards.has(c.id):
			acc.cards[c.id] = {"lvl": 0, "n": 0}
	for id in acc.cards:
		acc.cards[id] = {"lvl": int(acc.cards[id].lvl), "n": int(acc.cards[id].n)}
	if not valid_deck(acc, acc.deck):
		acc.deck = STARTER_DECK.duplicate()


func valid_deck(acc: Dictionary, deck: Array) -> bool:
	if deck.size() != 8:
		return false
	var seen := {}
	for c in deck:
		if not c is String or not acc.cards.has(c) or seen.has(c):
			return false
		seen[c] = true
	return true


## Arène atteinte (la dernière dont le seuil de trophées est dépassé).
func arena(acc: Dictionary) -> Dictionary:
	var best: Dictionary = GameDB.arenas()[0]
	for a in GameDB.arenas():
		if int(acc.trophies) >= int(a.trophies):
			best = a
	return best


func card_level(acc: Dictionary, card: String) -> int:
	return int(acc.cards.get(card, {"lvl": 0}).lvl)


# --- Cartes et niveau du roi ----------------------------------------------------------------------

func add_cards(acc: Dictionary, card: String, count: int) -> void:
	var c: Dictionary = acc.cards.get(card, {"lvl": 0, "n": -1})
	if c.n < 0:                         # nouvelle carte : la première sert à la débloquer
		c.n = count - 1
	else:
		c.n += count
	acc.cards[card] = c


## Cartes et or pour passer au niveau suivant ({} au niveau max).
func upgrade_cost(acc: Dictionary, card: String) -> Dictionary:
	var c: Dictionary = acc.cards.get(card, {})
	if c.is_empty():
		return {}
	var r := GameDB.rarity(GameDB.card(card).rarity)
	if c.lvl >= int(r.levels) - 1:
		return {}
	return {"cards": int(r.upgrade_cards[c.lvl]), "gold": int(r.upgrade_gold[c.lvl]), "exp": int(r.upgrade_exp[c.lvl])}


func upgrade(acc: Dictionary, card: String) -> bool:
	var cost := upgrade_cost(acc, card)
	if cost.is_empty() or acc.cards[card].n < cost.cards or acc.gold < cost.gold:
		return false
	acc.cards[card].n -= cost.cards
	acc.cards[card].lvl += 1
	acc.gold -= cost.gold
	add_exp(acc, cost.exp)
	return true


func add_exp(acc: Dictionary, exp: int) -> void:
	acc.exp += exp
	var levels: Array = GameDB.table("exp_levels")
	while acc.level <= levels.size() and acc.exp >= int(levels[acc.level - 1]) and acc.level < 13:
		acc.exp -= int(levels[acc.level - 1])
		acc.level += 1


# --- Combats -------------------------------------------------------------------------------------

## Récompenses d'un combat (1c1 : trophées ; victoire : or et coffre s'il reste un emplacement).
## Bonus des événements en cours (pourcentage cumulé) : « gold_percent » ou « cards_percent ».
func boost(kind: String, now: int) -> int:
	var total := 100
	for e in events:
		if int(e.get("starts", 0)) <= now and (int(e.get("ends", 0)) == 0 or now < int(e.ends)):
			total = total * int(e.get(kind, 100)) / 100
	return total


func battle_result(acc: Dictionary, won: bool, draw: bool, mode: String, now: int, event := {}) -> Dictionary:
	var out := {"trophies": 0, "gold": 0, "chest": ""}
	var a := arena(acc)
	var ladder: bool = event.is_empty() or bool(event.get("trophies", false))
	var chests: bool = event.is_empty() or bool(event.get("chests", false))
	if mode == "1v1" and not draw and ladder:
		if won:
			out.trophies = TROPHIES_WIN
		else:
			out.trophies = -mini(TROPHIES_LOSS, maxi(0, acc.trophies - int(a.get("demote", 0))))
		acc.trophies += out.trophies
		acc.best = maxi(acc.best, acc.trophies)
	if won:
		acc.wins += 1
		out.gold = int(a.gold) * int(settings.gold_percent) / 100 * boost("gold_percent", now) / 100
		acc.gold += out.gold
		if acc.chests.size() < SLOTS and chests:
			var order: Array = GameDB.table("chest_order")
			out.chest = order[acc.cycle % order.size()]
			acc.cycle += 1
			acc.chests.append({"type": out.chest, "state": "locked", "end": 0, "arena": int(a.number)})
	elif not draw:
		acc.losses += 1
	return out


# --- Coffres -------------------------------------------------------------------------------------

func unlock_seconds(type: String) -> int:
	var c: Dictionary = GameDB.table("chests").get(type, {})
	var s := int(c.get("TimeTakenDays", 0)) * 86400 + int(c.get("TimeTakenHours", 0)) * 3600 \
			+ int(c.get("TimeTakenMinutes", 0)) * 60 + int(c.get("TimeTakenSeconds", 0))
	return s * int(settings.unlock_percent) / 100


## Met à jour les états (déverrouillage fini → prêt ; coffres gratuits régénérés).
func refresh(acc: Dictionary, now: int) -> void:
	for c in acc.chests:
		if c.state == "unlocking" and now >= int(c.end):
			c.state = "ready"
	var interval := GameDB.global_int("FREE_CHEST_INTERVAL_HOURS", 4) * 3600 * int(settings.unlock_percent) / 100
	while acc.free_chests < FREE_CHESTS_MAX and now >= acc.free_next:
		acc.free_chests += 1
		acc.free_next = (acc.free_next if acc.free_next > 0 else now) + interval
	if acc.free_chests >= FREE_CHESTS_MAX:
		acc.free_next = 0
	elif acc.free_next == 0:
		acc.free_next = now + interval


func start_unlock(acc: Dictionary, slot: int, now: int) -> bool:
	if slot < 0 or slot >= acc.chests.size():
		return false
	for c in acc.chests:
		if c.state == "unlocking":
			return false
	var chest: Dictionary = acc.chests[slot]
	if chest.state != "locked":
		return false
	chest.state = "unlocking"
	chest.end = now + unlock_seconds(chest.type)
	return true


## Gemmes pour finir maintenant (globals SPEED_UP_DIAMOND_COST_*, interpolé).
static func speed_up_cost(seconds: int) -> int:
	if seconds <= 0:
		return 0
	var points := [[60, GameDB.global_int("SPEED_UP_DIAMOND_COST_1_MIN", 1)],
		[3600, GameDB.global_int("SPEED_UP_DIAMOND_COST_1_HOUR", 20)],
		[86400, GameDB.global_int("SPEED_UP_DIAMOND_COST_24_HOURS", 360)],
		[604800, GameDB.global_int("SPEED_UP_DIAMOND_COST_1_WEEK", 1800)]]
	if seconds <= points[0][0]:
		return maxi(1, points[0][1])
	for i in range(1, points.size()):
		if seconds <= points[i][0]:
			var s0: int = points[i - 1][0]
			var c0: int = points[i - 1][1]
			return c0 + (seconds - s0) * (points[i][1] - c0) / (points[i][0] - s0)
	return points[-1][1]


## Ouvre un coffre d'emplacement (prêt, ou payé en gemmes) ; {} si impossible.
func open_slot(acc: Dictionary, slot: int, now: int) -> Dictionary:
	if slot < 0 or slot >= acc.chests.size():
		return {}
	refresh(acc, now)
	var chest: Dictionary = acc.chests[slot]
	if chest.state != "ready":
		var left := unlock_seconds(chest.type) if chest.state == "locked" else int(chest.end) - now
		var cost := speed_up_cost(left)
		if acc.gems < cost:
			return {}
		acc.gems -= cost
	acc.chests.remove_at(slot)
	return open_chest(acc, chest.type)


func open_free(acc: Dictionary, now: int) -> Dictionary:
	refresh(acc, now)
	if acc.free_chests <= 0:
		return {}
	acc.free_chests -= 1
	if acc.free_next == 0:
		refresh(acc, now)
	return open_chest(acc, "Free")


## Contenu d'un coffre (comme le jeu : cartes = RandomSpells × multiplicateur de l'arène, une part
## de chaque rareté selon ses chances, paquets DifferentSpells, or par carte), ajouté au compte.
func open_chest(acc: Dictionary, type: String) -> Dictionary:
	var base: Dictionary = GameDB.table("chests").get(type, {})
	if base.is_empty():
		return {}
	var a := arena(acc)
	var base_cards := maxi(1, int(base.get("RandomSpells", 1)) * int(a.chest_multiplier) / 100)
	var now := int(Time.get_unix_time_from_system())
	var total := maxi(1, base_cards * int(settings.cards_percent) / 100 * boost("cards_percent", now) / 100)
	var stacks := maxi(1, int(base.get("DifferentSpells", 1)))
	var legendaries := _roll(total, int(base.get("LegendaryChance", 0)))
	var epics := _roll(total, int(base.get("EpicChance", 0)))
	var rares := _roll(total, int(base.get("RareChance", 0)))
	var commons := maxi(0, total - legendaries - epics - rares)
	var free := maxi(2, stacks - legendaries - (1 if epics > 0 else 0))
	var out := {"type": type, "cards": [], "gold": 0}
	_add_stacks(acc, out, "Legendary", legendaries, legendaries, int(a.number))
	_add_stacks(acc, out, "Epic", epics, 1, int(a.number))
	_add_stacks(acc, out, "Rare", rares, maxi(1, free / 3), int(a.number))
	_add_stacks(acc, out, "Common", commons, maxi(1, free - free / 3), int(a.number))
	var lo := int(base.get("MinGoldPerCard", 0))
	var hi := maxi(lo, int(base.get("MaxGoldPerCard", 0)))
	out.gold = base_cards * rng.randi_range(lo, hi) * int(settings.gold_percent) / 100 * boost("gold_percent", now) / 100
	acc.gold += out.gold
	return out


func _roll(total: int, chance: int) -> int:
	if chance <= 0:
		return 0
	var expected := float(total) / chance
	var count := int(expected)
	if rng.randf() < expected - count:
		count += 1
	return count


func _add_stacks(acc: Dictionary, out: Dictionary, rarity: String, count: int, stacks: int, arena_number: int) -> void:
	var pool := []
	for c in GameDB.cards:
		if c.rarity == rarity and int(c.arena) <= arena_number:
			pool.append(c.id)
	if pool.is_empty() or count <= 0:
		return
	stacks = mini(stacks, count)
	for i in stacks:
		var amount := count / stacks + (1 if i < count % stacks else 0)
		var card: String = pool[rng.randi_range(0, pool.size() - 1)]
		var is_new: bool = not acc.cards.has(card)
		add_cards(acc, card, amount)
		out.cards.append({"id": card, "n": amount, "new": is_new})


# --- Boutique ------------------------------------------------------------------------------------

## Offres du jour (renouvelées à minuit UTC) : une commune, une rare, une épique parmi les cartes
## des arènes atteintes ; prix de la 1.9 (PRICE_*, +PRICE_INCREASE_* par exemplaire déjà acheté).
func shop(acc: Dictionary, now: int) -> Array:
	var day := now / 86400
	if int(acc.get("shop_day", -1)) != day or not acc.has("shop"):
		acc.shop_day = day
		acc.shop = []
		var a := arena(acc)
		for rarity in ["Common", "Rare", "Epic"]:
			var pool := GameDB.cards.filter(func(c: Dictionary) -> bool:
				return c.rarity == rarity and int(c.arena) <= int(a.number))
			if not pool.is_empty():
				acc.shop.append({"card": pool[rng.randi_range(0, pool.size() - 1)].id, "bought": 0})
	return acc.shop


func card_price(rarity: String, bought: int) -> int:
	var key := rarity.to_upper()
	var price := GameDB.global_int("PRICE_" + key, 2) + bought * GameDB.global_int("PRICE_INCREASE_" + key, 2)
	return maxi(1, price * int(settings.shop_percent) / 100)


func card_limit(rarity: String) -> int:
	return GameDB.global_int("BUY_LIMIT_" + rarity.to_upper(), 10)


func buy_card(acc: Dictionary, index: int, now: int) -> bool:
	var offers := shop(acc, now)
	if index < 0 or index >= offers.size():
		return false
	var offer: Dictionary = offers[index]
	var rarity: String = GameDB.card(offer.card).rarity
	var price := card_price(rarity, int(offer.bought))
	if int(offer.bought) >= card_limit(rarity) or acc.gold < price:
		return false
	acc.gold -= price
	offer.bought = int(offer.bought) + 1
	add_cards(acc, offer.card, 1)
	return true


## Prix en gemmes d'un coffre de la boutique dans l'arène du joueur (arrondi comme le jeu).
func chest_price(acc: Dictionary, type: String) -> int:
	var base: Dictionary = GameDB.table("chests").get(type, {})
	var price := int(base.get("ShopPriceWithoutSpeedUp", 0)) * int(arena(acc).get("shop_multiplier", 100)) / 100
	if price > 500:
		price = 100 * ((price + 50) / 100)
	elif price > 100:
		price = 10 * ((price + 5) / 10)
	elif price > 20:
		price = 5 * ((price + 3) / 5)
	return maxi(1, price * int(settings.shop_percent) / 100)


func buy_chest(acc: Dictionary, type: String) -> Dictionary:
	if not type in SHOP_CHESTS:
		return {}
	var price := chest_price(acc, type)
	if acc.gems < price:
		return {}
	acc.gems -= price
	return open_chest(acc, type)


## Or contre des gemmes (gold_packs des réglages : [or, gemmes]).
func buy_gold(acc: Dictionary, index: int) -> bool:
	var packs: Array = settings.gold_packs
	if index < 0 or index >= packs.size() or acc.gems < int(packs[index][1]):
		return false
	acc.gems -= int(packs[index][1])
	acc.gold += int(packs[index][0])
	return true


func active_offers(now: int) -> Array:
	return offers.filter(func(o: Dictionary) -> bool:
		return int(o.get("starts", 0)) <= now and (int(o.get("ends", 0)) == 0 or now < int(o.ends)))


## Achat d'une offre spéciale : renvoie le contenu (format d'un coffre ouvert) ou {} si refusé.
func buy_offer(acc: Dictionary, id: String, now: int) -> Dictionary:
	for o in active_offers(now):
		if str(o.get("id", "")) != id:
			continue
		var bought: Dictionary = acc.get("offers_bought", {})
		var limit := int(o.get("limit", 0))
		if limit > 0 and int(bought.get(id, 0)) >= limit:
			return {}
		var price := int(o.get("price", 0))
		var currency: String = "gold" if o.get("currency", "gems") == "gold" else "gems"
		if int(acc[currency]) < price:
			return {}
		acc[currency] = int(acc[currency]) - price
		bought[id] = int(bought.get(id, 0)) + 1
		acc.offers_bought = bought
		var out := {"type": "Offer", "cards": [], "gold": 0, "gems": 0}
		for it: Dictionary in o.get("items", []):
			var n := maxi(1, int(it.get("n", 1)))
			match str(it.get("kind", "")):
				"gold":
					acc.gold += n
					out.gold += n
				"gems":
					acc.gems += n
					out.gems += n
				"card":
					var card := GameDB.card(str(it.get("id", "")))
					if not card.is_empty():
						add_cards(acc, card.id, n)
						out.cards.append({"id": card.id, "n": n})
				"chest":
					for i in mini(n, 10):
						var c := open_chest(acc, str(it.get("id", "Gold")))
						out.gold += int(c.get("gold", 0))
						out.cards.append_array(c.get("cards", []))
		return out
	return {}


## Vue du compte envoyée au client (sans jeton).
func public_view(acc: Dictionary, now: int) -> Dictionary:
	refresh(acc, now)
	var view := acc.duplicate(true)
	view.arena = arena(acc).id
	view.now = now
	for c in view.chests:
		c.seconds = unlock_seconds(c.type)
	view.shop = []
	for offer in shop(acc, now):
		var rarity: String = GameDB.card(offer.card).rarity
		view.shop.append({"card": offer.card, "bought": offer.bought, "price": card_price(rarity, int(offer.bought)),
			"limit": card_limit(rarity)})
	view.shop_reset = 86400 - now % 86400
	view.shop_chests = SHOP_CHESTS.map(func(t: String) -> Dictionary: return {"type": t, "price": chest_price(acc, t)})
	var packs: Array = settings.gold_packs
	view.shop_gold = []
	for i in packs.size():
		view.shop_gold.append({"i": i, "gold": int(packs[i][0]), "price": int(packs[i][1]), "tier": mini(i, 2)})
	var bought: Dictionary = acc.get("offers_bought", {})
	view.offers = active_offers(now).map(func(o: Dictionary) -> Dictionary:
		var v := o.duplicate(true)
		v.bought = int(bought.get(str(o.get("id", "")), 0))
		return v)
	view.erase("offers_bought")
	for k in ["banned", "invited_by", "seen", "created"]:
		view.erase(k)
	# Événements en cours et à venir (7 jours), actualités.
	view.events = events.filter(func(e: Dictionary) -> bool:
		return (int(e.get("ends", 0)) == 0 or now < int(e.ends)) and int(e.get("starts", 0)) < now + 7 * 86400)
	view.news = news.slice(-10)
	view.server_name = settings.get("server_name", "")
	return view
