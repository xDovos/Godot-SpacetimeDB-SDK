extends Node

@export var receiver:RowReceiver
var users = {}
var lobby_id:int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	receiver.insert.connect(on_self_update)
	receiver.delete.connect(on_leave_lobby)
	pass 

func on_leave_lobby(user:MainUser):
	print(user.online)
	print("Leave : ", user.identity.hex_encode())
	pass;
	
func on_self_update(user:MainUser):
	if user.identity == SpacetimeDB.get_local_identity().identity and lobby_id == 0:
		lobby_id = user.lobby_id
		print("My lobby : ", lobby_id)
		subscibe_whole_lobby(lobby_id, user.identity)
		users[user.identity] = user
	pass

func subscibe_whole_lobby(lobby_to_sub:int, user_identity:PackedByteArray):
	var id = user_identity
	id.reverse()
	var query = [
		"SELECT * FROM user WHERE online == true AND lobby_id == " + str(lobby_to_sub), 
		"SELECT * FROM user_data WHERE lobby_id == " + str(lobby_to_sub),
	]
	SpacetimeDB.subscribe('main', query)
