extends Resource
class_name User

@export var identity: PackedByteArray 
@export var name: String
@export var online: bool
@export var last_position_x: float
@export var last_position_y: float
@export var last_position_z: float
@export var direction_x: float
@export var direction_y: float
@export var direction_z: float
@export var last_update: int

func _init(): 
	set_meta("primary_key", "identity")
	set_meta("bsatn_type_last_update", "i64")
