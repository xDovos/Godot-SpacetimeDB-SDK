extends Resource
class_name User

@export var identity: PackedByteArray
@export var name: String
@export var online: bool
@export var last_position: Vector3
@export var direction: Vector2
@export var last_update: int

func _init():
	set_meta("table_name", "user")
	set_meta("primary_key", "identity")
	set_meta("bsatn_type_last_update", "i64")
	pass
