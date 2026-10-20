extends Control
## Aperçu d'une annonce : --kind=level|arena --value=…


func _ready() -> void:
	var c := Celebration.new()
	c.kind = "arena"
	c.value = "Arena3"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kind="):
			c.kind = arg.get_slice("=", 1)
		elif arg.begins_with("--value="):
			c.value = arg.get_slice("=", 1)
	add_child(c)
