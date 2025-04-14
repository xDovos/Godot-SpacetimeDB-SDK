extends Node

@export var debug_url:String = "http://127.0.0.1:3000";
@export var release_url:String;
@export var debug:bool = true;

var auth_header:String;
var request = HTTPRequest.new()
var websocket = WebSocketPeer.new();
var token;
var connected = false

signal connection_established
signal spacetime_packet_parsed(packet)

func _ready():
	set_process(false)
	add_child(request)
	connect_to_spacetime()
	spacetime_packet_parsed.connect(debug_log)

func connect_to_spacetime():
	token = await get_auth_token()
	
	connect_websocket("quickstart-chat")
	
	await connection_established
	
	subscribe(["SELECT * FROM message","SELECT * FROM user"])
	pass;

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var result = await call_reducer("send_message", {"text" : "Hello from godot"}, true)
		#print("Result: ", result)

func debug_log(packet:SpacetimePacket):
	match packet.packet_type:
		SpacetimePacket.PacketType.UNKNOWN:
			print("Popa")
		SpacetimePacket.PacketType.TRANSACTION_UPDATE:
			print("ReducerName: ", packet.transaction_update.reducer_call.reducer_name, " Args: ", packet.transaction_update.reducer_call.args_string)
		SpacetimePacket.PacketType.INITIAL_SUBSCRIPTION:
			print("Poka")
	pass
	
func get_data(token):
	var error = request.request(get_current_url() + "/v1/database/quickstart-chat", [auth_header] ,HTTPClient.METHOD_GET);
	if error != OK:
		print("Error making GET request: ", error)
		return
	var result = await request.request_completed
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		print("GET request failed. Response code: ", result[1])
		return
	#print("Initial Data: ", result[3].get_string_from_utf8())
	pass
	
func rest_call_reducer(database:String, reducer_name:String, args):
	var content_type = "Content-Type: application/json"
	var error = request.request(get_current_url() + "/v1/database/"+database+"/call/" + reducer_name, [auth_header, content_type] ,HTTPClient.METHOD_POST, JSON.stringify(args));
	if error != OK:
		print("Error making POST request: ", error)
		return
	var result = await request.request_completed
	print(result[3].get_string_from_utf8())
	pass;
	
func call_reducer(reducer_name:String, args:Dictionary, notify_on_done:bool):
	var time_out_seconds = 10;
	var my_request_id = randi() & 0x7FFFFFFF
	var notify = 0;
	if not notify_on_done: notify = 1;
	
	print("Call reducer via Websocket")
	
	var subscription_message = {
		"CallReducer": {
			"reducer": 
				reducer_name,
			"args":JSON.stringify(args),
			"request_id": my_request_id,
			"flags": notify
			}
		}
		
	var json_string = JSON.stringify(subscription_message)
	
	var err = websocket.send_text(json_string)
	
	if err != OK:
		print("Error calling reducer request: ", err)
	
	var time_started = Time.get_ticks_msec()
	
	while true:
		var time_elapsed = (Time.get_ticks_msec() - time_started) / 1000.0
		var time_remaining = time_out_seconds - time_elapsed

		if time_remaining <= 0:
			printerr("Timeout waiting for response for reducer '%s' (ID: %d)" % [reducer_name, my_request_id])
			return null 

		var packet:SpacetimePacket = await self.spacetime_packet_parsed

		if packet.is_type(SpacetimePacket.PacketType.TRANSACTION_UPDATE):
			if packet.transaction_update.get_request_id() == my_request_id:
				print("Received response for reducer '%s' (ID: %d)" % [reducer_name, my_request_id])
				return packet 

func generate_websocket_key() -> String:
	var random_bytes = PackedByteArray()
	random_bytes.resize(16)
	for i in 16:
		random_bytes[i] = randi_range(0, 255)
	return Marshalls.raw_to_base64(random_bytes)

func subscribe(queries:PackedStringArray):
	print("WebSocket connected. Sending subscription request...")
	var subscription_message = {
		"Subscribe": {
			"query_strings": 
				queries,
			"request_id": 1
			}
		}
	var json_string = JSON.stringify(subscription_message)
	
	print("Sending subscription: ", json_string)
	
	var err = websocket.send_text(json_string)
	
	if err != OK:
		print("Error sending subscription request: ", err)
	else:
		print("Subscription request sent successfully.")
	pass;
	
func connect_websocket(database:String):
	var current_url = get_current_url()
	current_url = current_url.replace("http", "ws");
	current_url = current_url.replace("https", "wss");
	var url = current_url + "/v1/database/"+ database + "/subscribe"
	
	auth_header = "Authorization: Bearer " + token;
	
	var proto = "v1.json.spacetimedb" #spdb json protocol
	
	websocket.handshake_headers = [auth_header]
	websocket.supported_protocols = [proto]

	#print("Attempting to connect to WebSocket: ", url)
	var err = websocket.connect_to_url(url)
	if err != OK:
		print("Error initiating WebSocket connection: ", err)
	else:
		print("WebSocket connection initiated. Enabling process.")
		set_process(true)
	pass

func get_current_url() -> String:
	if debug: return debug_url 
	else: return release_url;
	
func _process(delta: float) -> void:
	if websocket == null:
		return 

	websocket.poll()
	
	var state = websocket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not connected:
				connection_established.emit()
				connected = true

			while websocket.get_available_packet_count() > 0:
				var packet = websocket.get_packet()
				var packet_str = packet.get_string_from_utf8()
				#print("Received Packet: " ,packet_str)
				parse_packet(packet_str)


		WebSocketPeer.STATE_CONNECTING:
			#print("WebSocket connecting...") 
			pass

		WebSocketPeer.STATE_CLOSING:
			print("WebSocket closing...")
			pass

		WebSocketPeer.STATE_CLOSED:
			if connected: 
				print("WebSocket disconnected.")
			set_process(false) 
			connected = false
			pass

func parse_packet(packet_str: String):
	var parse_result = JSON.parse_string(packet_str)
	if parse_result == null:
		print("Error parsing JSON packet: ", packet_str)
		return
	#print(packet_str)
	if parse_result is Dictionary:
		var typed_packet: SpacetimePacket = SpacetimePacket.from_dictionary(parse_result)
		#print("Parsed Spacetime Packet: ", typed_packet) 
		
		spacetime_packet_parsed.emit(typed_packet)
	else:
		printerr("Parsed packet is not a Dictionary, cannot create SpacetimePacket: ", parse_result)

func get_auth_token() -> String :
	var token_path = ""
	if debug:token_path = "user://token.debug"
	else:token_path = "user://token"

	if FileAccess.file_exists(token_path):
		var file_read = FileAccess.open(token_path, FileAccess.READ)
		if file_read != null:
			#print("Token file exists. Reading token...")
			var existing_token = file_read.get_as_text()
			file_read.close()
			if not existing_token.is_empty():
				#print("Restored token from file.")
				return existing_token 
			else:
				print("Token file was empty. Requesting new token.")
		else:
			printerr("Error opening existing token file for reading. Requesting new token.")
	else:
		print("Token file does not exist. Requesting new token.")

	print("Requesting new token from server...")
	var error = request.request(debug_url + "/v1/identity", [] ,HTTPClient.METHOD_POST);
	if error != OK:
		printerr("Error making token request: ", error) 
		return "" 

	var result = await request.request_completed
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		printerr("Token request failed. Response code: ", result[1])
		printerr("Response body: ", result[3].get_string_from_utf8())
		return ""

	var body_text = result[3].get_string_from_utf8()
	var json = JSON.parse_string(body_text)
	if json == null:
		printerr("Failed to parse token JSON response: ", body_text)
		return ""

	if json.has("token") and not json.token.is_empty():
		var new_token = json.token
		print("New token received.")

		var file_write = FileAccess.open(token_path, FileAccess.WRITE)
		if file_write != null:
			print("Saving new token to file: ", token_path)
			file_write.store_string(new_token)
			file_write.close() 
		else:
			printerr("Error opening token file for writing!")

		return new_token
	else:
		printerr("Token not found or empty in JSON response: ", body_text)
		return ""
