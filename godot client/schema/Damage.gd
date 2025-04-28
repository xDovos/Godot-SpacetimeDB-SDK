extends Resource
class_name Damage

@export var amount: int
@export var source: PackedByteArray

func _init():
	set_meta("bsatn_type_amount", "u32")
	set_meta("bsatn_type_source", "identity")
	pass
