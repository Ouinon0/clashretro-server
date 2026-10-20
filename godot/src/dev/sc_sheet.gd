extends Node2D
## Planche d'exports .sc pour repérer les éléments d'interface : --sc=fichier --match=regex
## [--cols=4] [--frame=N] [--tree=profondeur] [--parts=export/chemin : ses enfants nommés, un par case] ; chaque export est réduit dans sa case, son nom
## dessous, et l'arbre de ses enfants nommés est écrit dans la sortie standard.

func _ready() -> void:
	var file := "ui"
	var pattern := "^menu_bottom"
	var cols := 4
	var frame := -1
	var depth := 2
	var parts := ""
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg.begins_with("--sc="):
			file = v
		elif arg.begins_with("--match="):
			pattern = v.replace(",", "|")         # « | » est mal transmis par les scripts de capture
		elif arg.begins_with("--cols="):
			cols = int(v)
		elif arg.begins_with("--frame="):
			frame = int(v)
		elif arg.begins_with("--tree="):
			depth = int(v)
		elif arg.begins_with("--parts="):
			parts = v
	RenderingServer.set_default_clear_color(Color(0.16, 0.17, 0.2))
	var lib := ScLibrary.get_library(file)
	var re := RegEx.create_from_string(pattern)
	var names: Array = lib.exports.keys().filter(func(n: String) -> bool: return re.search(n) != null)
	names.sort()
	if parts != "":
		var whole := lib.create_export(parts.get_slice("/", 0)) as ScMovieClip
		var holder := whole if not "/" in parts else whole.get_sc(parts.substr(parts.find("/") + 1)) as ScMovieClip
		names = Array(holder.child_names()).filter(func(n: String) -> bool: return n != "")
	var size := get_viewport_rect().size
	var cell := Vector2(size.x / cols, size.x / cols)
	for i in names.size():
		var clip: Node2D
		if parts != "":
			var whole := lib.create_export(parts.get_slice("/", 0)) as ScMovieClip
			clip = whole.get_sc((parts.substr(parts.find("/") + 1) + "/" if "/" in parts else "") + names[i])
			clip.get_parent().remove_child(clip)
			clip.transform = Transform2D.IDENTITY
		else:
			clip = lib.create_export(names[i])
		if clip is ScMovieClip and frame >= 0:
			clip.goto_and_stop(mini(frame, clip.frames.size() - 1))
		var box := ScMovieClip.bounds_of(clip)
		var k := minf((cell.x - 12) / maxf(box.size.x, 1.0), (cell.y - 34) / maxf(box.size.y, 1.0))
		var origin := Vector2(i % cols, i / cols) * cell
		clip.scale = Vector2.ONE * k
		clip.position = origin + Vector2(6, 4) - box.position * k
		add_child(clip)
		var label := Label.new()
		label.text = "%s  (%dx%d)" % [names[i], box.size.x, box.size.y]
		label.add_theme_font_size_override("font_size", 13)
		label.position = origin + Vector2(4, cell.y - 24)
		add_child(label)
		print("== ", names[i], " ", box)
		_print_tree(clip, 1, depth)


func _print_tree(node: Node, level: int, depth: int) -> void:
	if level > depth or not node is ScMovieClip:
		return
	var clip := node as ScMovieClip
	for n in clip.child_names():
		if n == "":
			continue
		var child := clip.get_sc(n)
		var kind := "txt" if child is ScTextField else ("clip %d" % child.frames.size() if child is ScMovieClip else "shape")
		print("  ".repeat(level), n, " [", kind, "]")
		_print_tree(child, level + 1, depth)
