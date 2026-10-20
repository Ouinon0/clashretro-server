extends Node2D
## Planche de toutes les cartes (contrôle des illustrations et de leur découpe).


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.2, 0.2, 0.25))
	var screen := BattleScreen.new()
	var i := 0
	for card in GameDB.cards:
		var v: ScMovieClip = screen._card_view(card.id)
		v.scale = Vector2.ONE * 0.62
		v.position = Vector2(48 + (i % 9) * 78, 70 + (i / 9) * 110)
		add_child(v)
		var label := Label.new()
		label.text = str(i)
		label.position = v.position + Vector2(-30, -60)
		add_child(label)
		i += 1
	screen.free()
