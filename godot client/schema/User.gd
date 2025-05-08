extends Resource
class_name User

@export var identity: PackedByteArray
@export var online: bool
@export var lobby_id: int
@export var damage: Damage

func _init():
	set_meta("bsatn_type_identity", "identity")
	set_meta("bsatn_type_lobby_id", "u64")

	set_meta("table_name", "user")
	set_meta("primary_key", "identity")
	pass
