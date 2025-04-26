extends Resource
class_name Message

@export var int_value:int
@export var string_value:String
@export var int_vec:Array[int]
@export var string_vec:Array[String]

func _init():
	set_meta("bsatn_type_int_value", "u8")
	set_meta("bsatn_type_int_vec", "u8")
	pass
