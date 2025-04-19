extends Resource
class_name User

@export var identity: PackedByteArray
@export var name: String
@export var online: bool

func _init():
	set_meta("table_name", "user")
	set_meta("primary_key", "identity")
	pass
