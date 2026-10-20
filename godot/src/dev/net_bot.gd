extends Node
## Client de test sans affichage : --net-bot=hôte[:port] [--mode=2v2] [--lag=ms]. Se connecte, s'inscrit
## dans la file, joue avec l'IA d'entraînement par le réseau (poses immédiates, retours en arrière),
## puis compare son empreinte à celle du serveur à la fin du combat.
## --lag ajoute un retard artificiel à la réception des poses des autres (mesure du recalcul).

var mode := "1v1"
var lag_ms := 0
var room := ""
var token_file := ""                # --token-file : jeton gardé d'une exécution à l'autre (reprise)
var clan_actions: Array = []        # --clan=create:Nom | join | say:texte | request:Carte (puis quitte)
var sim: BattleSim
var net: NetBattle
var ai: TrainingAI
var _delayed: Array = []            # [heure, message] (retard artificiel)
var _name := "Bot%d" % (randi() % 1000)


var _code := ""


func _ready() -> void:
	var host := "127.0.0.1"
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg.begins_with("--net-bot="):
			host = v
		elif arg == "--mode=2v2":
			mode = "2v2"
		elif arg.begins_with("--lag="):
			lag_ms = int(v)
		elif arg.begins_with("--token-file="):
			token_file = v
		elif arg.begins_with("--clan="):
			clan_actions.append(v)
		elif arg.begins_with("--room="):
			room = v
		elif arg.begins_with("--code="):
			_code = arg.get_slice("=", 1)
		elif arg.begins_with("--name="):
			_name = v
	var token := FileAccess.get_file_as_string(token_file) if token_file != "" and FileAccess.file_exists(token_file) else ""
	Net.connected.connect(func() -> void: Net.send({"t": "hello", "v": Protocol.VERSION, "name": _name, "token": token, "code": _code}))
	Net.disconnected.connect(func() -> void:
		print("NETBOT déconnecté")
		get_tree().quit(1))
	Net.message.connect(_on_message)
	Net.connect_to(host.get_slice(":", 0), int(host.get_slice(":", 1)) if ":" in host else Protocol.PORT)


func _on_message(msg: Dictionary) -> void:
	if msg.t == "cmd" and lag_ms > 0 and int(msg.p) != net.me:
		_delayed.append([Time.get_ticks_msec() + lag_ms, msg])
		return
	match msg.t:
		"welcome":
			if token_file != "":
				var f := FileAccess.open(token_file, FileAccess.WRITE)
				f.store_string(msg.token)
			if not clan_actions.is_empty():
				_clan_script()
				return
			# Reprise : le serveur renvoie lui-même le combat en cours après l'accueil.
			await get_tree().create_timer(0.3).timeout
			if net == null:
				Net.send({"t": "queue", "mode": mode, "room": room})
		"match":
			sim = BattleSim.new()
			sim.setup(msg.players.map(func(p: Dictionary) -> int: return p.level), msg.players.map(func(p: Dictionary) -> int: return p.team))
			net = NetBattle.new(sim, msg)
			ai = TrainingAI.new(sim, net.me, msg.deck, 8, 99 + net.me)
			ai.on_play = func(_p: int, card: String, x: int, y: int) -> void:
				net.deploy(card, int(msg.levels.get(card, 0)), x, y)
			print("NETBOT combat %d, joueur %d, rtt %d ms%s" % [msg.id, net.me, Net.rtt_ms,
					", reprise (%d poses)" % msg.log.size() if msg.has("log") else ""])
		"cmd":
			net.on_command(msg)
		"end":
			var at: int = msg.tick
			var mine := -1
			if net._snapshots.has(at):
				var probe := BattleSim.new()
				probe.load_state(net._snapshots[at])
				mine = probe.checksum()
			elif sim.tick == at:
				mine = sim.checksum()
			print("NETBOT fin : %s (empreinte %d / serveur %d), retours en arrière %d (%d ticks), rtt %d ms" % [
					"SYNCHRO OK" if mine == int(msg.sum) else "DÉSYNCHRO", mine, msg.sum, net.rollbacks,
					net.rollback_ticks, Net.rtt_ms])
			get_tree().quit(0 if mine == int(msg.sum) else 2)
		"desync":
			print("NETBOT désynchro signalée au tick ", msg.tick)


## Actions de clan scriptées (test), puis fin.
func _clan_script() -> void:
	for action: String in clan_actions:
		var arg := action.get_slice(":", 1)
		match action.get_slice(":", 0):
			"create":
				Net.send({"t": "clan_create", "name": arg})
			"join":
				Net.send({"t": "clans"})
				var list: Array = await Player.clans_listed
				if not list.is_empty():
					Net.send({"t": "clan_join", "id": list[0].id})
			"say":
				Net.send({"t": "clan_say", "text": arg})
			"request":
				Net.send({"t": "clan_request", "card": arg})
		await get_tree().create_timer(0.4).timeout
	print("NETBOT clan : ", Player.clan.get("name", "—"), ", ", Player.clan.get("chat", []).size(), " messages")
	get_tree().quit()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for d in _delayed.duplicate():
		if now >= d[0]:
			_delayed.erase(d)
			net.on_command(d[1])
	if net == null or not net.started():
		return
	# L'IA décide au rythme de la simulation (comme un joueur qui regarde l'écran).
	var before := sim.tick
	net.update()
	if not net.catching_up():
		for i in sim.tick - before:
			ai.on_tick()
