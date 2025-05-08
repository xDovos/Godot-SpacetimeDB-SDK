extends Resource
class_name Damage

@export var amount: int
@export var source: PackedByteArray
@export var int_vec: Array[int]

func _init():
	set_meta("bsatn_type_amount", "u32")
	set_meta("bsatn_type_source", "identity")
	set_meta("bsatn_type_int_vec", "u8")
	pass
