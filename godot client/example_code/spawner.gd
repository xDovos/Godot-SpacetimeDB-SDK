extends Node3D

@export var receiver:RowReceiver
@export var player_scene:PackedScene
var players:Dictionary[PackedByteArray, Node3D]

func _ready() -> void:
	receiver.on_receive.connect(receive_user)
	
func receive_user(user_row:User):
	var player = players.get(user_row.identity)
	#Spawn online players
	if player == null and user_row.online == true:
		var new_player := player_scene.instantiate()
		new_player.set_meta("id", user_row.identity)
		if user_row.identity == SpacetimeDB.get_local_identity().identity:
			new_player.set_meta("is_local", true)
		else:
			new_player.set_meta("is_local", false)
		add_child(new_player)
		new_player.global_position.y = 1;
		players[user_row.identity] = new_player;
		
	#Despawn or ignore offline
	if player != null and user_row.online == false:
		player.queue_free()
		players[user_row.identity] = null
	pass
