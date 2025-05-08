extends Resource
class_name UserData

@export var identity: PackedByteArray
@export var online: bool
@export var name: String
@export var lobby_id: int
@export var color: Color
@export var test_vec: Array[String]
@export var test_bytes_array: Array[int]
@export var last_position: Vector3
@export var direction: Vector2
@export var player_speed: float
@export var last_update: int

func _init():
	set_meta("bsatn_type_identity", "identity")
	set_meta("bsatn_type_lobby_id", "u64")
	set_meta("bsatn_type_test_bytes_array", "u8")
	set_meta("bsatn_type_player_speed", "f32")
	set_meta("bsatn_type_last_update", "i64")

	set_meta("table_name", "user_data")
	set_meta("primary_key", "identity")
	pass
