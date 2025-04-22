extends CharacterBody3D

@export var receiver:RowReceiver;

var last_local_input:Vector2;
var remote_input:Vector2;
var remote_speed:float;

func _ready() -> void:
	receiver.update.connect(user_data_received)
	set_process(get_meta("is_local"))
	
func user_data_received(user_data:UserData):
	if get_meta("id") != user_data.identity:return
	$Label3D.text = str(user_data.name)
	global_position = user_data.last_position
	remote_input = user_data.direction
	remote_speed = user_data.player_speed
	pass;
	
func _process(delta: float) -> void:
	var input_dir:Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if last_local_input == input_dir:
		return;
	last_local_input = input_dir
	var id = SpacetimeDB.call_reducer(
		"move_user", {
			"new_input": input_dir
			}
		)
	pass;
	
func _physics_process(delta: float) -> void:
	var direction := Vector3(remote_input.x, 0, remote_input.y)
	if direction:
		velocity.x = direction.x * remote_speed
		velocity.z = direction.z * remote_speed
	else:
		velocity.x = move_toward(velocity.x, 0, remote_speed)
		velocity.z = move_toward(velocity.z, 0, remote_speed)

	move_and_slide()
