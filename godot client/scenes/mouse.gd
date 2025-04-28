extends Sprite2D

@export var receiver:RowReceiver;
	
var last_position:Vector2;
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	receiver.update.connect(user_data_received)
	set_process(get_meta("local"))
	pass # Replace with function body.

func user_data_received(user_data:UserData):
	if get_meta("id") != user_data.identity:return
	last_position = Vector2(user_data.last_position.x, user_data.last_position.y)
	#global_position = last_position
	$RichTextLabel.text = "[wave]"+ user_data.name
	pass;

func _physics_process(delta: float) -> void:
	global_position = global_position.lerp(last_position, 10 * delta)
	pass;
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if last_position != get_global_mouse_position():
		last_position = get_global_mouse_position()
		var vec_to2d = Vector3(last_position.x, last_position.y, 0)
		SpacetimeDB.call_reducer("move_user", [Vector2(0,0), vec_to2d])
	pass
