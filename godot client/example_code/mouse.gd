extends Sprite2D

@export var receiver:RowReceiver;

var last_position:Vector2;

func _ready() -> void:
	receiver.update.connect(user_data_received)
	set_process(get_meta("local"))
	pass

func user_data_received(user_data:MainUserData):
	if get_meta("id") != user_data.identity:return
	last_position = Vector2(user_data.last_position.x, user_data.last_position.y)
	$RichTextLabel.text = "[wave]"+ user_data.name
	pass;

func _physics_process(delta: float) -> void:
	global_position = global_position.lerp(last_position, 10 * delta)
	pass;
	
func _process(delta: float) -> void:
	if last_position != get_global_mouse_position():
		last_position = get_global_mouse_position()
		var vec_to2d = Vector3(last_position.x, last_position.y, 0)
		SpacetimeModule.Main.Reducers.move_user(Vector2(0,0), vec_to2d)
	pass
