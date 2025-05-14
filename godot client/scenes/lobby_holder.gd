extends Node

@export var receiver:RowReceiver;
var local_user:MainUser;
var users = {}
signal user_join(user:MainUser)
signal user_leave(user:MainUser)

func _ready() -> void:
	receiver.update.connect(on_user_received)
	receiver.delete.connect(on_user_leave)
	pass;
	
func on_user_received(user:MainUser):
	if local_user == null and user.identity == SpacetimeDB.get_local_identity().identity:
		print("Set local user: ", user.identity.hex_encode())
		local_user = user;
		subscibe_on_lobby(user.lobby_id)
	else:
		if users.has(user.identity):return;
		print("Join: ", user.identity.hex_encode())
		user_join.emit(user)
		users[user.identity] = user;
	pass;

func on_user_leave(user:MainUser):
	print("Leave: ", user.identity.hex_encode())
	user_leave.emit(user)
	pass;
	
func subscibe_on_lobby(lobby_to_sub:int):
	var query = [
		"SELECT * FROM user WHERE online == true AND lobby_id == " + str(lobby_to_sub), 
		"SELECT * FROM user_data WHERE lobby_id == " + str(lobby_to_sub),
	]
	SpacetimeDB.subscribe(query)
