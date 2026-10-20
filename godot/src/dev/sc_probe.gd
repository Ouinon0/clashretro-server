extends Node2D
## Affiche un export .sc pour le calibrer : --sc=fichier --export=nom [--scale=0.5]
## [--grid=ox,oy,px,py] trace la grille des cases (origine = centre de l'arène, px/py par case).

func _ready() -> void:
	var file := "level_barbarian_arena"
	var export_name := "barbarian_arena_bgr"
	var s := 0.5
	var grid := PackedFloat64Array()
	var center := Vector2.ZERO          # point de l'export placé au centre de l'écran
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg.begins_with("--sc="):
			file = v
		elif arg.begins_with("--export="):
			export_name = v
		elif arg.begins_with("--scale="):
			s = float(v)
		elif arg.begins_with("--center="):
			center = Vector2(float(v.get_slice(",", 0)), float(v.get_slice(",", 1)))
		elif arg.begins_with("--grid="):
			grid = PackedFloat64Array(Array(v.split(",")).map(func(x: String) -> float: return float(x)))
	RenderingServer.set_default_clear_color(Color(0.1, 0.1, 0.1))
	var clip := ScLibrary.create(file, export_name)
	var root := Node2D.new()
	root.position = get_viewport_rect().size / 2 - center * s
	root.scale = Vector2(s, s)
	add_child(root)
	root.add_child(clip)
	if grid.size() == 4:
		var lines := Node2D.new()
		root.add_child(lines)
		lines.draw.connect(func() -> void:
			for i in range(0, 19):
				var x := grid[0] + (i - 9) * grid[2]
				lines.draw_line(Vector2(x, grid[1] - 16 * grid[3]), Vector2(x, grid[1] + 16 * grid[3]), Color.RED if i % 9 == 0 else Color(1, 1, 1, 0.5), 2.0)
			for j in range(0, 33):
				var y := grid[1] + (j - 16) * grid[3]
				lines.draw_line(Vector2(grid[0] - 9 * grid[2], y), Vector2(grid[0] + 9 * grid[2], y), Color.RED if j % 16 == 0 else Color(1, 1, 1, 0.5), 2.0))
		lines.queue_redraw()
