extends Node
## Point d'entrée : accueil (HomeScreen) ↔ combat (BattleScreen, entraînement ou en ligne).
## --server : serveur de jeu (GameServer) ; --net-bot=hôte : client de test sans affichage.
## Test : --training lance directement un entraînement ; --mode=2v2, --deck=…, --enemy=… (8 cartes).


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		add_child(GameServer.new())
		return
	for arg in args:
		if arg.begins_with("--net-bot"):
			add_child(load("res://src/dev/net_bot.gd").new())
			return
	if "--training" in args:
		_battle({"training": true, "team_mode": "--mode=2v2" in args})
	else:
		_home()


func _home() -> void:
	var home := MainMenu.new()
	home.battle_requested.connect(func(options: Dictionary) -> void:
		home.queue_free()
		_battle(options))
	add_child(home)


func _battle(options: Dictionary) -> void:
	var battle := BattleScreen.new()
	battle.team_mode = options.get("team_mode", false)
	battle.online = options.get("online", {})
	battle.deck = Player.deck()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--deck="):
			battle.deck = Array(arg.get_slice("=", 1).split(","))
		elif arg.begins_with("--enemy="):
			battle.opponent_deck = Array(arg.get_slice("=", 1).split(","))
	battle.finished.connect(func(_r: Dictionary) -> void:
		battle.queue_free()
		_home.call_deferred())
	add_child(battle)
