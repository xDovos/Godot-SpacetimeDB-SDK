extends Resource
class_name Lobby

@export var id: int
@export var player_count: int

func _init():
	set_meta("bsatn_type_id", "u64")
	set_meta("bsatn_type_player_count", "u32")

	set_meta("table_name", "lobby")
	set_meta("primary_key", "id")
	pass
