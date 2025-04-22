extends Resource
class_name UserData

@export var identity: PackedByteArray
@export var name: String
@export var lobby_id:int
@export var last_position: Vector3
@export var direction: Vector2
@export var player_speed: float
@export var last_update: int

func _init():
	set_meta("table_name", "user_data")
	set_meta("primary_key", "identity")
	set_meta("bsatn_type_last_update", "i64")
	set_meta("bsatn_type_lobby_id", "u64")
	pass
