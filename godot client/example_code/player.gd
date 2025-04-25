extends CharacterBody3D

@export var receiver:RowReceiver;

var last_position:Vector3;
var last_local_input:Vector2;
var remote_input:Vector2;
var remote_speed:float;

func _ready() -> void:
	receiver.update.connect(user_data_received)
	
	#WARNING Dont do that! Every insert/update have deletes.
	#Just receive updates
	#receiver.delete.connect() 
	
	set_process(get_meta("is_local"))
	set_process_input(get_meta("is_local"))
	
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		#Reducer without args
		var id = SpacetimeDB.call_reducer("change_color_random", [])
	
func user_data_received(user_data:UserData):
	if get_meta("id") != user_data.identity:return
	$MeshInstance3D.get_surface_override_material(0).albedo_color = user_data.color
	$Label3D.text = str(user_data.name)
	last_position = user_data.last_position
	remote_input = user_data.direction
	remote_speed = user_data.player_speed
	pass;
	
func _process(delta: float) -> void:
	var input_dir:Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if last_local_input == input_dir:
		return;
	last_local_input = input_dir
	var id = SpacetimeDB.call_reducer("move_user", [input_dir, global_position])
	pass;
	
func _physics_process(delta: float) -> void:
	if remote_input == Vector2.ZERO:
		global_position = global_position.lerp(last_position, 10 * delta)
	var direction := Vector3(remote_input.x, 0, remote_input.y)
	if direction:
		velocity.x = direction.x * remote_speed
		velocity.z = direction.z * remote_speed
	move_and_slide()
