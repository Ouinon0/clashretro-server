class_name GameServer
extends Node
## Serveur de jeu (Godot sans écran : godot --headless -- --server [--port=N] [--http-port=N]
## [--data=dossier] [--bots-after=S]). Admin web et pages publiques : ServerAdmin (port HTTP). Comptes simples, appariement 1c1 / 2c2 (complété par des IA après
## --bots-after secondes), combats arbitrés : même simulation que les clients, MAX_LATE ticks
## derrière l'heure réelle (Protocol).
##
## Tout tourne dans un fil dédié qui attend les paquets (ENet) au plus 2 ms : une pose est relayée
## à l'instant où elle arrive, et les simulations avancent à l'heure.

const SERVICE_TIMEOUT_MS := 2
const RECONNECT_MS := 30000         # combat gardé pour un joueur déconnecté
const BOT_DECKS := [
	["Knight", "Archer", "Giant", "Musketeer", "MiniPekka", "Fireball", "Arrows", "HogRider"],
	["Valkyrie", "Wizard", "Prince", "BabyDragon", "Witch", "Barbarians", "Zap", "Pekka"],
	["Goblins", "Minions", "Balloon", "Golem", "SkeletonArmy", "Cannon", "Zap", "Bowler"],
]

var port := Protocol.PORT
var http_port := Protocol.PORT + 1   # page d'accueil et admin web (TCP)
var data_dir := "user://server"
var bots_after_ms := 10000
var match_seconds := 180            # --matchlen=S (tests)

var _host := ENetConnection.new()
var _thread := Thread.new()
var _running := true
var _sessions := {}                 # ENetPacketPeer → session
var _accounts := {}                 # jeton → compte (Progression)
var _progress: Progression
var _clans := Clans.new()
var _dirty := false                 # comptes à enregistrer
var _queues := {"1v1": [], "2v2": []}   # files : « 1v1 », « 2v2 », ou « 1v1#code » (combat amical)
var _matches: Array = []
var _next_match := 1
var _log := []                      # lignes de journal (écrites par le fil réseau, affichées par le principal)
var _log_mutex := Mutex.new()
var _log_history := []              # 300 dernières lignes (admin web)
var admin: ServerAdmin


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg.begins_with("--port="):
			port = int(v)
		elif arg.begins_with("--data="):
			data_dir = v
		elif arg.begins_with("--matchlen="):
			match_seconds = int(v)
		elif arg.begins_with("--bots-after="):
			bots_after_ms = int(float(v) * 1000)
		elif arg.begins_with("--http-port="):
			http_port = int(v)
	if OS.get_environment("CLASH_DATA") != "":
		data_dir = OS.get_environment("CLASH_DATA")
	DirAccess.make_dir_recursive_absolute(data_dir)
	_progress = Progression.new(_load_json("settings.json", {}))
	# Ancien réglage : un code d'accès non vide voulait dire « mode code ».
	if not _load_json("settings.json", {}).has("access_mode"):
		_progress.settings.access_mode = "code" if str(_progress.settings.access_code) != "" else "invite"
	_save_json("settings.json", _progress.settings)
	apply_settings()
	_load_accounts()
	_clans.load_data(_load_json("clans.json", {}))
	var err := _host.create_host_bound("*", port, 256, Protocol.CHANNELS)
	if err != OK:
		push_error("Port %d indisponible (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	_host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	print("Serveur prêt sur le port UDP %d" % port)
	admin = ServerAdmin.new(self)
	if http_port > 0:
		admin.listen(http_port)
	_thread.start(_loop)


func _process(_delta: float) -> void:
	_log_mutex.lock()
	for line in _log:
		print(line)
	_log.clear()
	_log_mutex.unlock()


func _exit_tree() -> void:
	_running = false
	if _thread.is_started():
		_thread.wait_to_finish()


func _say(line: String) -> void:
	var stamped := "[%s] %s" % [Time.get_datetime_string_from_system().replace("T", " "), line]
	_log_mutex.lock()
	_log.append(stamped)
	_log_mutex.unlock()
	_log_history.append(stamped)
	if _log_history.size() > 400:
		_log_history = _log_history.slice(-300)


# --- Boucle réseau -------------------------------------------------------------------------------

func _loop() -> void:
	while _running:
		var event := _host.service(SERVICE_TIMEOUT_MS)
		while event[0] != ENetConnection.EVENT_NONE:
			_handle(event)
			event = _host.service(0)
		admin.poll()
		var now := Time.get_ticks_msec()
		_update_queues(now)
		for m in _matches.duplicate():
			_update_match(m, now)
		if _dirty:
			_dirty = false
			_save_accounts()
			_save_json("clans.json", _clans.save_data())


func _handle(event: Array) -> void:
	var peer: ENetPacketPeer = event[1]
	match event[0]:
		ENetConnection.EVENT_CONNECT:
			peer.set_timeout(0, 5000, 10000)
			_sessions[peer] = {"peer": peer, "account": {}, "match": null, "index": -1}
		ENetConnection.EVENT_DISCONNECT:
			var s: Dictionary = _sessions.get(peer, {})
			_sessions.erase(peer)
			if not s.is_empty():
				for q in _queues.values():
					q.erase(s)
				# Seulement si c'est encore sa session (l'ancienne connexion d'un joueur revenu se
				# termine parfois après la reprise).
				if s.match != null and s.match.players[s.index].session == s:
					s.match.players[s.index].left_ms = Time.get_ticks_msec()
					s.match.players[s.index].session = null
		ENetConnection.EVENT_RECEIVE:
			var msg := Protocol.decode(peer.get_packet())
			var s: Dictionary = _sessions.get(peer, {})
			if not msg.is_empty() and not s.is_empty():
				_on_message(s, msg)


## `s` : session (dictionnaire) ou null (joueur IA, joueur déconnecté).
func _send(s: Variant, msg: Dictionary, channel := Protocol.CHANNEL_GAME) -> void:
	if not s is Dictionary or s.is_empty():
		return
	var flags := ENetPacketPeer.FLAG_RELIABLE if channel == Protocol.CHANNEL_GAME else ENetPacketPeer.FLAG_UNSEQUENCED
	s.peer.send(channel, Protocol.encode(msg), flags)


func _on_message(s: Dictionary, msg: Dictionary) -> void:
	match msg.get("t", ""):
		"ping":
			_send(s, {"t": "pong", "c": msg.get("c", 0), "s": Time.get_ticks_msec()}, Protocol.CHANNEL_CLOCK)
		"hello":
			_on_hello(s, msg)
		"queue":
			if s.account.is_empty() or s.match != null:
				return
			var mode := "2v2" if msg.get("mode", "") == "2v2" else "1v1"
			var asked := str(msg.get("mode", ""))
			if asked.begins_with("ev:"):
				var ev := event_by_id(asked.substr(3))
				if ev.is_empty() or ev.get("mode", "") == "":
					_send(s, {"t": "error", "code": "event"})
					return
				mode = asked
			for q in _queues.values():
				q.erase(s)
			s.deck = s.account.deck.duplicate()
			s.queued_ms = Time.get_ticks_msec()
			# Combat amical : ceux qui donnent le même code se retrouvent entre eux.
			var room := str(msg.get("room", "")).strip_edges().left(12)
			var key := mode + ("#" + room if room != "" and not mode.begins_with("ev:") else "")
			if not _queues.has(key):
				_queues[key] = []
			_queues[key].append(s)
			_send(s, {"t": "queued", "mode": mode, "room": room})
		"cancel":
			for q in _queues.values():
				q.erase(s)
			_send(s, {"t": "cancelled"})
		"cmd":
			if s.match != null:
				_on_command(s.match, s.index, msg)
		"sum":
			if s.match != null:
				_on_checksum(s.match, s.index, int(msg.get("tick", -1)), int(msg.get("v", 0)))
		"deck":
			if not s.account.is_empty() and _progress.valid_deck(s.account, msg.get("cards", [])):
				s.account.deck = msg.cards.duplicate()
				_changed(s)
		"upgrade":
			if not s.account.is_empty() and _progress.upgrade(s.account, str(msg.get("card", ""))):
				_changed(s)
		"chest_unlock":
			if not s.account.is_empty() and _progress.start_unlock(s.account, int(msg.get("slot", -1)), _unix()):
				_changed(s)
		"chest_open", "free_chest":
			if s.account.is_empty():
				return
			var content := _progress.open_free(s.account, _unix()) if msg.t == "free_chest" \
					else _progress.open_slot(s.account, int(msg.get("slot", -1)), _unix())
			if not content.is_empty():
				_send(s, {"t": "chest", "content": content})
				_changed(s)
		"emote":
			var now := Time.get_ticks_msec()
			if s.match != null and not s.match.ended and now - int(s.get("emote_ms", -5000)) >= 1800:
				s.emote_ms = now
				var index := clampi(int(msg.get("i", 0)), 0, 9)
				for p in s.match.players:
					_send(p.session, {"t": "emote", "p": s.index, "i": index})
		"buy_card":
			if not s.account.is_empty() and _progress.buy_card(s.account, int(msg.get("i", -1)), _unix()):
				_changed(s)
		"buy_chest":
			if s.account.is_empty():
				return
			var bought := _progress.buy_chest(s.account, str(msg.get("type", "")))
			if not bought.is_empty():
				_send(s, {"t": "chest", "content": bought})
				_changed(s)
		"buy_gold":
			if not s.account.is_empty() and _progress.buy_gold(s.account, int(msg.get("i", -1))):
				_changed(s)
		"buy_offer":
			if s.account.is_empty():
				return
			var content := _progress.buy_offer(s.account, str(msg.get("id", "")), _unix())
			if not content.is_empty():
				if not content.cards.is_empty():
					_send(s, {"t": "chest", "content": content})
				_changed(s)
		"invites":
			if not s.account.is_empty():
				_send_invites(s)
		"players":
			if not s.account.is_empty():
				_send(s, {"t": "players", "list": _leaderboard(int(s.account.id))})
		"invite_create":
			if s.account.is_empty():
				return
			var quota := int(_progress.settings.get("player_invites", 2))
			var mine := admin.invites.filter(func(i: Dictionary) -> bool: return int(i.by) == int(s.account.id))
			if mine.size() < quota:
				admin.create_invite(int(s.account.id))
			_send_invites(s)
		"clans":
			_send(s, {"t": "clans", "list": _clans.listing()})
		"clan_create", "clan_join", "clan_leave", "clan_say", "clan_request", "clan_donate":
			_on_clan(s, msg)
		"leave":
			if s.match != null and not s.match.ended:
				_finish(s.match, 1 - s.match.sim.team_of(s.index), "abandon")


# --- Comptes -------------------------------------------------------------------------------------

func _on_hello(s: Dictionary, msg: Dictionary) -> void:
	if int(msg.get("v", 0)) != Protocol.VERSION:
		_send(s, {"t": "error", "code": "version"})
		return
	var token := str(msg.get("token", ""))
	var account: Dictionary = _accounts.get(token, {})
	if account.is_empty():
		var given := str(msg.get("code", "")).strip_edges()
		var invited_by := -1
		match str(_progress.settings.get("access_mode", "invite")):
			"code":
				if given != str(_progress.settings.get("access_code", "")):
					_send(s, {"t": "error", "code": "access"})
					return
			"invite":
				if not admin.invite_valid(given):
					_send(s, {"t": "error", "code": "invite"})
					return
		token = _new_token()
		var next_id := 1
		for a in _accounts.values():
			next_id = maxi(next_id, int(a.id) + 1)
		account = _progress.new_account(next_id, str(msg.get("name", "Joueur")).left(16))
		if str(_progress.settings.get("access_mode", "invite")) == "invite":
			invited_by = admin.consume_invite(given, next_id)
		account.invited_by = invited_by
		account.created = _unix()
		_accounts[token] = account
		_dirty = true
		_say("Nouveau compte n°%d" % next_id)
	if account.get("banned", false):
		_send(s, {"t": "error", "code": "banned"})
		return
	elif msg.has("name") and str(msg.name).strip_edges() != "":
		account.name = str(msg.name).strip_edges().left(16)
	s.account = account
	s.token = token
	account.seen = _unix()
	_send(s, {"t": "welcome", "token": token, "id": account.id, "name": account.name, "trophies": account.trophies})
	_send(s, {"t": "profile", "profile": _progress.public_view(account, _unix())})
	if account.get("clan", "") != "":
		_send(s, {"t": "clan", "clan": _clans.view(account.clan, _accounts_by_id())})
	# Reprise d'un combat en cours (coupure réseau, appli relancée).
	for m in _matches:
		for i in m.players.size():
			var p: Dictionary = m.players[i]
			if p.get("token", "") == token and not m.ended:
				if p.session != null and p.session != s:
					p.session.match = null
					p.session.peer.peer_disconnect_later()
				p.session = s
				p.erase("left_ms")
				s.match = m
				s.index = i
				_send(s, _match_message(m, i, true))
				_say("%s revient dans le combat %d" % [account.name, m.id])
				return


func _on_clan(s: Dictionary, msg: Dictionary) -> void:
	var acc: Dictionary = s.account
	if acc.is_empty():
		return
	var clan_id: String = acc.get("clan", "")
	var ok := false
	match msg.t:
		"clan_create":
			clan_id = _clans.create(acc, str(msg.get("name", "")))
			ok = clan_id != ""
		"clan_join":
			clan_id = str(msg.get("id", ""))
			ok = _clans.join(acc, clan_id)
		"clan_leave":
			_clans.leave(acc)
			_changed(s)
			_send(s, {"t": "clan", "clan": {}})
			_push_clan(clan_id)
			return
		"clan_say":
			ok = _clans.say(acc, str(msg.get("text", "")))
		"clan_request":
			ok = _clans.request(acc, str(msg.get("card", "")), _unix(),
					int(_progress.settings.get("request_seconds", 3600)))
		"clan_donate":
			var receiver := _clans.donate(acc, int(msg.get("id", 0)), _accounts_by_id(), _progress)
			ok = receiver != 0
			if ok:
				for other in _sessions.values():
					if not other.account.is_empty() and int(other.account.id) == receiver:
						_changed(other)
	if ok:
		_changed(s)
		_push_clan(clan_id)


## Classement des joueurs du serveur (100 premiers) : pseudo, trophées, niveau, clan, en ligne.
func _leaderboard(me: int) -> Array:
	var online := {}
	for x in _sessions.values():
		if not x.account.is_empty():
			online[int(x.account.id)] = true
	var list := _accounts.values().filter(func(a: Dictionary) -> bool: return not a.get("banned", false))
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.trophies) > int(b.trophies))
	return list.slice(0, 100).map(func(a: Dictionary) -> Dictionary:
		return {"name": a.name, "trophies": a.trophies, "level": a.level, "online": online.has(int(a.id)),
			"clan": _clans.clans.get(a.get("clan", ""), {}).get("name", ""), "me": int(a.id) == me})


func _send_invites(s: Dictionary) -> void:
	var quota := int(_progress.settings.get("player_invites", 2))
	var mine := admin.player_invites(int(s.account.id))
	_send(s, {"t": "invites", "list": mine, "quota": quota, "mode": _progress.settings.get("access_mode", "invite"),
		"http_port": http_port})


# --- Outils de l'admin ---------------------------------------------------------------------------

func online_count() -> int:
	return _sessions.values().filter(func(x: Dictionary) -> bool: return not x.account.is_empty()).size()


## Message à tous les joueurs connectés (annonce de l'admin).
func broadcast(msg: Dictionary) -> void:
	for x in _sessions.values():
		if not x.account.is_empty():
			_send(x, msg)


## Nouvelle vue du compte (et de son clan) pour toutes les sessions concernées.
func account_changed(acc: Dictionary) -> void:
	_dirty = true
	for x in _sessions.values():
		if not x.account.is_empty() and int(x.account.id) == int(acc.id):
			_send(x, {"t": "profile", "profile": _progress.public_view(x.account, _unix())})


## Événements, offres, réglages changés : nouvelles vues pour tout le monde.
func refresh_all() -> void:
	_dirty = true
	for x in _sessions.values():
		if not x.account.is_empty():
			_send(x, {"t": "profile", "profile": _progress.public_view(x.account, _unix())})
			if x.account.get("clan", "") != "":
				_send(x, {"t": "clan", "clan": _clans.view(x.account.clan, _accounts_by_id())})


func kick(id: int, reason: String) -> void:
	for x in _sessions.values():
		if not x.account.is_empty() and int(x.account.id) == id:
			_send(x, {"t": "error", "code": "kicked", "text": reason})
			x.peer.peer_disconnect_later()


func delete_account(id: int) -> void:
	for token in _accounts.keys():
		if int(_accounts[token].id) == id:
			_clans.leave(_accounts[token])
			_accounts.erase(token)
	_dirty = true


## Réglages lus en direct (admin) : IA et durée des combats.
func apply_settings() -> void:
	var st: Dictionary = _progress.settings
	if st.has("bots_after"):
		bots_after_ms = int(st.bots_after) * 1000 if int(st.bots_after) >= 0 else -1
	else:
		st.bots_after = bots_after_ms / 1000 if bots_after_ms >= 0 else -1
	if st.has("match_seconds"):
		match_seconds = clampi(int(st.match_seconds), 30, 600)
	else:
		st.match_seconds = match_seconds


func event_by_id(id: String) -> Dictionary:
	for e in ServerAdmin._active(admin.events):
		if str(e.id) == id:
			return e
	return {}


## Nouvelle vue du clan à tous ses membres connectés.
func _push_clan(clan_id: String) -> void:
	if clan_id == "":
		return
	var view := _clans.view(clan_id, _accounts_by_id())
	for other in _sessions.values():
		if not other.account.is_empty() and other.account.get("clan", "") == clan_id:
			_send(other, {"t": "clan", "clan": view})


func _accounts_by_id() -> Dictionary:
	var out := {}
	for a in _accounts.values():
		out[int(a.id)] = a
	return out


## Compte modifié : enregistrement groupé et nouvelle vue au client.
func _changed(s: Dictionary) -> void:
	_dirty = true
	_send(s, {"t": "profile", "profile": _progress.public_view(s.account, _unix())})


static func _unix() -> int:
	return int(Time.get_unix_time_from_system())


func _load_json(file: String, fallback: Variant) -> Variant:
	var f := FileAccess.open(data_dir.path_join(file), FileAccess.READ)
	if f:
		var v = JSON.parse_string(f.get_as_text())
		if v != null:
			return v
	return fallback


func _save_json(file: String, value: Variant) -> void:
	var path := data_dir.path_join(file)
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(value, "\t"))
		f.close()
		DirAccess.rename_absolute(path + ".tmp", path)


func _new_token() -> String:
	var bytes := Crypto.new().generate_random_bytes(18)
	return Marshalls.raw_to_base64(bytes).replace("/", "_").replace("+", "-")


func _load_accounts() -> void:
	var v = _load_json("accounts.json", {})
	if v is Dictionary:
		_accounts = v
		for a in _accounts.values():
			_progress.fix(a)


func _save_accounts() -> void:
	_save_json("accounts.json", _accounts)


# --- Appariement ---------------------------------------------------------------------------------

func _update_queues(now: int) -> void:
	for key in _queues.keys():
		var q: Array = _queues[key]
		var mode: String = key.get_slice("#", 0)
		var friendly: bool = "#" in key
		if mode.begins_with("ev:"):
			var ev := event_by_id(mode.substr(3))
			if ev.is_empty():
				for x in q:
					_send(x, {"t": "cancelled"})
				_queues.erase(key)
				continue
		var team_mode: bool = mode == "2v2" or (mode.begins_with("ev:") and event_by_id(mode.substr(3)).get("team", "") == "2v2")
		var need := 4 if team_mode else 2
		while q.size() >= need:
			_start_match(mode, q.slice(0, need), friendly)
			q.assign(q.slice(need))
		if not friendly and not q.is_empty() and bots_after_ms >= 0 and now - q[0].queued_ms >= bots_after_ms:
			_start_match(mode, q.duplicate())
			q.clear()
		if friendly and q.is_empty():
			_queues.erase(key)


func _start_match(queue_mode: String, humans: Array, friendly := false) -> void:
	var event := event_by_id(queue_mode.substr(3)) if queue_mode.begins_with("ev:") else {}
	var mode := queue_mode if event.is_empty() else str(event.get("team", "1v1"))
	var count := 4 if mode == "2v2" else 2
	var rules := _event_rules(event)
	var m := {"id": _next_match, "mode": mode, "friendly": friendly, "event": event, "rules": rules, "players": [], "log": [], "ended": false, "sums": {},
		"start_ms": Time.get_ticks_msec() + Protocol.START_DELAY_MS, "seed": randi(), "ais": [],
		"location": "", "sim": BattleSim.new()}
	_next_match += 1
	for i in count:
		var s: Dictionary = humans[i] if i < humans.size() else {}
		var p := {"team": i % 2, "level": 1, "session": s if not s.is_empty() else null, "levels": {}}
		if s.is_empty():
			# IA au niveau du premier joueur humain (roi et cartes).
			var ref: Dictionary = humans[0].account
			p.name = "IA"
			p.deck = BOT_DECKS[(i + m.id) % BOT_DECKS.size()]
			p.bot = true
			p.level = ref.level
			for c in p.deck:
				var r := GameDB.rarity(GameDB.card(c).rarity)
				p.levels[c] = clampi(ref.level - 1 - int(r.relative_level), 0, int(r.levels) - 1)
			_apply_level_rules(p, rules)
		else:
			p.name = s.account.name
			p.deck = s.deck
			p.token = s.token
			p.trophies = s.account.trophies
			p.level = s.account.level
			for c in p.deck:
				p.levels[c] = _progress.card_level(s.account, c)
			_apply_level_rules(p, rules)
			s.match = m
			s.index = i
		m.players.append(p)
	var arena: Dictionary = GameDB.arenas()[(m.id) % GameDB.arenas().size()]
	m.location = arena.team if mode == "2v2" else arena.pvp
	var sim: BattleSim = m.sim
	sim.match_ticks = int(rules.get("seconds", match_seconds)) * 20
	sim.setup(m.players.map(func(p: Dictionary) -> int: return p.level))
	sim.apply_rules(rules)
	sim.battle_ended.connect(func(w: int) -> void: _finish(m, w, "fin"))
	for i in count:
		if m.players[i].get("bot", false):
			var ai := TrainingAI.new(sim, i, m.players[i].deck, 0, m.seed + i)
			ai.on_play = func(player: int, card: String, x: int, y: int) -> void:
				_add_command(m, player, _now_tick(m) + Protocol.INPUT_DELAY, card, x, y, -1)
			m.ais.append(ai)
	_matches.append(m)
	for i in count:
		_send(m.players[i].session, _match_message(m, i, false))
	_say("Combat %d (%s) : %s" % [m.id, mode, ", ".join(m.players.map(func(p: Dictionary) -> String: return p.name))])


func _match_message(m: Dictionary, index: int, resume: bool) -> Dictionary:
	var players := []
	for p in m.players:
		players.append({"name": p.name, "team": p.team, "level": p.level, "trophies": p.get("trophies", 0)})
	var msg := {"t": "match", "id": m.id, "mode": m.mode, "you": index, "players": players,
		"deck": m.players[index].deck, "levels": m.players[index].levels, "start": m.start_ms, "len": m.sim.match_ticks, "location": m.location, "now": Time.get_ticks_msec(),
		"rules": m.rules, "event": m.event.get("title", "")}
	if resume:
		msg.log = m.log.duplicate()
	return msg


# --- Combats -------------------------------------------------------------------------------------

## Règles d'un combat d'événement : élixir (%), élixir de départ, durée (s), niveaux.
func _event_rules(event: Dictionary) -> Dictionary:
	match str(event.get("mode", "")):
		"double_elixir":
			return {"elixir_percent": 200}
		"triple_elixir":
			return {"elixir_percent": 300}
		"tournament":
			return {"levels": "tournament"}
		"sudden_death":
			return {"elixir_percent": 200, "seconds": 60}
	return {}


## Niveaux de tournoi (cartes : communes 9, rares 7, épiques 4, légendaires 1 ; roi 9 au plus).
func _apply_level_rules(p: Dictionary, rules: Dictionary) -> void:
	if rules.get("levels", "") != "tournament":
		return
	p.level = mini(int(p.level), 9)
	for c in p.levels:
		var r := GameDB.rarity(GameDB.card(c).rarity)
		p.levels[c] = mini(int(p.levels[c]), maxi(0, 8 - int(r.relative_level)))


## Tick « réel » d'un combat (heure du serveur), en avance de MAX_LATE sur sa simulation.
func _now_tick(m: Dictionary) -> int:
	return int(Time.get_ticks_msec() - m.start_ms) / Rules.TICK_MS


func _update_match(m: Dictionary, now: int) -> void:
	if m.ended:
		if now - m.ended_ms > 5000:
			_matches.erase(m)
		return
	# Joueur parti depuis trop longtemps : son équipe perd.
	for i in m.players.size():
		var p: Dictionary = m.players[i]
		if p.has("left_ms") and now - p.left_ms > RECONNECT_MS:
			_finish(m, 1 - p.team, "déconnexion")
			return
	var sim: BattleSim = m.sim
	var target: int = (now - m.start_ms) / Rules.TICK_MS - Protocol.MAX_LATE
	while sim.tick < target and not m.ended:
		for ai in m.ais:
			ai.on_tick()
		sim.step()
		if sim.tick % Protocol.SUM_EVERY == 0:
			_store_sum(m, sim.tick, -1, sim.checksum())


func _on_command(m: Dictionary, index: int, msg: Dictionary) -> void:
	if m.ended:
		return
	var card := str(msg.get("card", ""))
	if not card in m.players[index].deck:
		return
	_add_command(m, index, int(msg.get("tick", 0)), card, int(msg.get("x", 0)), int(msg.get("y", 0)),
			int(msg.get("seq", -1)))


## Pose datée et relayée à tous. Trop en retard (la simulation du serveur a passé ce tick), elle est
## décalée au premier tick encore possible ; l'auteur l'apprend par l'écho (même seq, autre tick).
func _add_command(m: Dictionary, player: int, tick: int, card: String, x: int, y: int, seq: int) -> void:
	var sim: BattleSim = m.sim
	tick = clampi(tick, sim.tick, _now_tick(m) + Protocol.MAX_AHEAD)
	var p: Dictionary = m.players[player]
	var level: int = p.levels.get(card, 0)
	m.log.append([tick, player, card, level, x, y, seq])
	sim.schedule(tick, player, card, level, x, y)
	var msg := {"t": "cmd", "p": player, "tick": tick, "card": card, "level": level, "x": x, "y": y, "seq": seq}
	for other in m.players:
		_send(other.session, msg)


func _on_checksum(m: Dictionary, index: int, tick: int, value: int) -> void:
	_store_sum(m, tick, index, value)


func _store_sum(m: Dictionary, tick: int, index: int, value: int) -> void:
	var entry: Dictionary = m.sums.get(tick, {})
	entry[index] = value
	m.sums[tick] = entry
	if entry.has(-1):
		for k in entry:
			if k >= 0 and entry[k] != entry[-1]:
				_say("Combat %d : désynchro du joueur %d au tick %d" % [m.id, k, tick])
				_send(m.players[k].session, {"t": "desync", "tick": tick})
		m.sums.erase(tick - Protocol.SUM_EVERY * 10)


func _finish(m: Dictionary, winner: int, reason: String) -> void:
	if m.ended:
		return
	m.ended = true
	m.ended_ms = Time.get_ticks_msec()
	var sim: BattleSim = m.sim
	for p in m.players:
		var account: Dictionary = _accounts.get(p.get("token", ""), {})
		var rewards := {}
		if not account.is_empty() and not m.friendly:
			rewards = _progress.battle_result(account, p.team == winner, winner < 0, m.mode, _unix(), m.event)
			_dirty = true
		_send(p.session, {"t": "end", "winner": winner, "crowns": sim.crowns.duplicate(), "reason": reason,
			"tick": sim.tick, "sum": sim.checksum(), "trophies": account.get("trophies", -1), "rewards": rewards})
		if p.session != null:
			p.session.match = null
			_send(p.session, {"t": "profile", "profile": _progress.public_view(account, _unix())})
	_say("Combat %d terminé (%s) : équipe %d, couronnes %s, tick %d, empreinte %d" % [m.id, reason, winner,
			sim.crowns, sim.tick, sim.checksum()])
