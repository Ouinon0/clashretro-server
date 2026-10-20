extends Node
## Capture d'écran pour les tests sans écran : --capture=chemin.png [--capture-frames=N]
## enregistre l'image après N images (60 par défaut) puis quitte.
## --drag=x1,y1,x2,y2,image[,tenu] : glisser du doigt (coordonnées du canevas) à partir de l'image
## donnée ; avec « tenu », le doigt reste posé à l'arrivée (capture de l'aperçu de pose).
## --tap=x,y,image : toucher bref (coordonnées du canevas) à l'image donnée ; répétable.

var _path := ""
var _frames := 60
var _frame := 0
var _drags: Array = []              # [début, fin, image, tenu]
var _taps: Array = []               # [point, image]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--capture="):
			_path = arg.get_slice("=", 1)
		elif arg.begins_with("--capture-frames="):
			_frames = int(arg.get_slice("=", 1))
		elif arg.begins_with("--drag="):
			var v := arg.get_slice("=", 1).split(",")
			_drags.append([Vector2(float(v[0]), float(v[1])), Vector2(float(v[2]), float(v[3])), int(v[4]),
					v.size() > 5])
		elif arg.begins_with("--tap="):
			var t := arg.get_slice("=", 1).split(",")
			_taps.append([Vector2(float(t[0]), float(t[1])), int(t[2])])
	set_process(_path != "" or not _drags.is_empty() or not _taps.is_empty())


func _process(_delta: float) -> void:
	_frame += 1
	for d in _drags:
		_drag_step(d)
	for t in _taps:
		if _frame == t[1] or _frame == t[1] + 2:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = _frame == t[1]
			e.position = get_viewport().get_final_transform() * t[0]
			e.global_position = e.position
			Input.parse_input_event(e)
	if _path == "":
		return
	_frames -= 1
	if _frames > 0:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_path)
	print("capture : ", _path)
	get_tree().quit()


## Glisser en 12 images : appui, déplacements, relâchement (sauf « tenu »).
func _drag_step(d: Array) -> void:
	var t := _frame - int(d[2])
	if t < 0 or t > 12:
		return
	var vp := get_viewport()
	var at: Vector2 = d[0].lerp(d[1], t / 11.0)
	var to_screen := vp.get_final_transform()
	if t == 0:
		var press := InputEventScreenTouch.new()
		press.pressed = true
		press.position = to_screen * at
		Input.parse_input_event(press)
	elif t <= 11:
		var move := InputEventScreenDrag.new()
		move.position = to_screen * at
		Input.parse_input_event(move)
	elif not d[3]:
		var release := InputEventScreenTouch.new()
		release.pressed = false
		release.position = to_screen * at
		Input.parse_input_event(release)
