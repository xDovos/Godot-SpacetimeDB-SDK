extends Resource
class_name Message

@export var message_id: int
@export var sender: PackedByteArray
@export var sent: int
@export var text: String

func _init():
	set_meta("table_name", "message")
	set_meta("primary_key", "message_id")
	set_meta("bsatn_type_message_id", "u64")
	set_meta("bsatn_type_sent", "i64")
	pass
