class_name SpacetimePacket
extends RefCounted

class SpacetimeIdentity:
	var identity_hex: String = ""
	static func from_dictionary(data: Dictionary) -> SpacetimeIdentity:
		var i := SpacetimeIdentity.new()
		i.identity_hex = data.get("__identity__", "") if data is Dictionary else ""
		if i.identity_hex.is_empty(): printerr("SpacetimeIdentity parse failed: ", data)
		return i
	func _to_string(): return "Identity[%s]" % identity_hex

class SpacetimeConnectionId:
	var id_string: String = "0"; var id_float: float = 0.0
	static func from_dictionary(data: Dictionary) -> SpacetimeConnectionId:
		var i := SpacetimeConnectionId.new()
		var raw_id = data.get("__connection_id__", null) if data is Dictionary else null
		if raw_id is float or raw_id is int:
			i.id_float = float(raw_id); i.id_string = str(raw_id)
		else: printerr("SpacetimeConnectionId parse failed: ", data)
		return i
	func _to_string(): return "ConnId[%s]" % id_string

class SpacetimeTimestamp:
	var micros_since_epoch: int = 0
	static func from_dictionary(data: Dictionary) -> SpacetimeTimestamp:
		var i := SpacetimeTimestamp.new()
		var raw_ts = data.get("__timestamp_micros_since_unix_epoch__", null) if data is Dictionary else null
		if raw_ts is float or raw_ts is int: i.micros_since_epoch = int(raw_ts)
		else: printerr("SpacetimeTimestamp parse failed: ", data)
		return i
	func get_datetime_dict() -> Dictionary: return Time.get_datetime_dict_from_unix_time(micros_since_epoch / 1000000)
	func _to_string():
		var dt = get_datetime_dict()
		return "Timestamp[%04d-%02d-%02d %02d:%02d:%02d.%06d]" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, micros_since_epoch % 1000000]

class SpacetimeDuration:
	var duration_micros: int = 0
	static func from_dictionary(data: Dictionary) -> SpacetimeDuration:
		var i := SpacetimeDuration.new()
		var raw_dur = data.get("__time_duration_micros__", null) if data is Dictionary else null
		if raw_dur is float or raw_dur is int: i.duration_micros = int(raw_dur)
		else: printerr("SpacetimeDuration parse failed: ", data)
		return i
	func _to_string(): return "Duration[%d us]" % duration_micros

class ReducerCallInfo:
	var reducer_name: String = ""; var reducer_id: int = -1
	var args_string: String = ""; var request_id: int = -1
	static func from_dictionary(data: Dictionary) -> ReducerCallInfo:
		var i := ReducerCallInfo.new()
		if not data is Dictionary: return i 
		i.reducer_name = data.get("reducer_name", "")
		i.reducer_id = int(data.get("reducer_id", -1.0))
		i.args_string = data.get("args", "")
		i.request_id = int(data.get("request_id", -1.0))
		return i
	func get_parsed_args() -> Variant: return JSON.parse_string(args_string)
	func _to_string(): return "Reducer[Name:'%s', ID:%d, ReqID:%d, Args:'%s']" % [reducer_name, reducer_id, request_id, args_string]

class RowUpdate:
	var inserts: Array[String] = [] 
	var deletes: Array[String] = [] 

	static func from_dictionary(data: Dictionary) -> RowUpdate:
		var i := RowUpdate.new()
		if not data is Dictionary: return i
		
		var raw_inserts = data.get("inserts", [])
		if raw_inserts is Array:
			for item in raw_inserts:
				if item is String:
					i.inserts.append(item)
				else:
					printerr("RowUpdate: Non-string item found in 'inserts': ", item)
		else:
			if raw_inserts != []:
				printerr("RowUpdate: 'inserts' is not an Array in ", data)
				
		var raw_deletes = data.get("deletes", [])
		if raw_deletes is Array:
			for item in raw_deletes:
				if item is String:
					i.deletes.append(item)
				else:
					printerr("RowUpdate: Non-string item found in 'deletes': ", item)
		else:
			if raw_deletes != []:
				printerr("RowUpdate: 'deletes' is not an Array in ", data)
		return i
		
	func _parse_json_strings(arr: Array[String]) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for json_string in arr:
			var parsed = JSON.parse_string(json_string)
			if parsed is Dictionary: result.append(parsed)
			else: printerr("RowUpdate: Failed to parse insert/delete string as JSON Dict: ", json_string)
		return result
	func get_parsed_inserts() -> Array[Dictionary]: return _parse_json_strings(inserts)
	func get_parsed_deletes() -> Array[Dictionary]: return _parse_json_strings(deletes) # Assuming deletes also contain JSON row data/keys
	func _to_string(): return "RowUpdate[Inserts:%d, Deletes:%d]" % [inserts.size(), deletes.size()]

class TableUpdate:
	var table_id: int = -1; var table_name: String = ""
	var num_rows: int = -1; var updates: Array[RowUpdate] = []
	static func from_dictionary(data: Dictionary) -> TableUpdate:
		var i := TableUpdate.new()
		if not data is Dictionary: return i
		i.table_id = int(data.get("table_id", -1.0))
		i.table_name = data.get("table_name", "")
		i.num_rows = int(data.get("num_rows", -1.0))
		var raw_updates = data.get("updates", [])
		if raw_updates is Array:
			for u_dict in raw_updates:
				if u_dict is Dictionary: i.updates.append(RowUpdate.from_dictionary(u_dict))
		return i
	func _to_string(): return "TableUpdate[Name:'%s', ID:%d, Rows:%d, Updates:%d]" % [table_name, table_id, num_rows, updates.size()]

class DatabaseUpdate:
	var tables: Array[TableUpdate] = []
	static func from_dictionary(data: Dictionary) -> DatabaseUpdate:
		var i := DatabaseUpdate.new()
		if not data is Dictionary: return i
		var raw_tables = data.get("tables", [])
		if raw_tables is Array:
			for t_dict in raw_tables:
				if t_dict is Dictionary: i.tables.append(TableUpdate.from_dictionary(t_dict))
		return i
	func get_updates_for_table(table_name: String) -> TableUpdate:
		for tu in tables:
			if tu.table_name == table_name: return tu
		return null
	func _to_string(): return "DatabaseUpdate[Tables:%d]" % tables.size()

class TransactionStatus:
	enum StatusType { UNKNOWN, COMMITTED, FAILED } # Enum defined inside the class
	var status_type: StatusType = StatusType.UNKNOWN
	var committed_update: DatabaseUpdate = null # Only if COMMITTED
	var failure_details: Variant = null # Only if FAILED (raw data)
	static func from_dictionary(data: Dictionary) -> TransactionStatus:
		var i := TransactionStatus.new()
		if not data is Dictionary: return i
		if data.has("Committed") and data["Committed"] is Dictionary:
			i.status_type = StatusType.COMMITTED
			i.committed_update = DatabaseUpdate.from_dictionary(data["Committed"])
		elif data.has("Failed"):
			i.status_type = StatusType.FAILED
			i.failure_details = data["Failed"] # Store raw failure data
			printerr("TransactionStatus: Received FAILED status: ", i.failure_details)
		else: i.status_type = StatusType.UNKNOWN
		return i
	func is_committed() -> bool: return status_type == StatusType.COMMITTED
	func is_failed() -> bool: return status_type == StatusType.FAILED
	func _to_string():
		match status_type:
			StatusType.COMMITTED: return "Status[COMMITTED, %s]" % str(committed_update)
			StatusType.FAILED: return "Status[FAILED: %s]" % str(failure_details)
			_: return "Status[UNKNOWN]"
			
class PayloadIdentityToken:
	var identity: SpacetimeIdentity = null; var token: String = ""
	var connection_id: SpacetimeConnectionId = null
	static func from_dictionary(data: Dictionary) -> PayloadIdentityToken:
		var i := PayloadIdentityToken.new()
		if not data is Dictionary: return i
		if data.has("identity"): i.identity = SpacetimeIdentity.from_dictionary(data.get("identity"))
		i.token = data.get("token", "")
		if data.has("connection_id"): i.connection_id = SpacetimeConnectionId.from_dictionary(data.get("connection_id"))
		return i
	func _to_string(): return "PayloadIdentityToken[ID:%s, ConnID:%s]" % [str(identity), str(connection_id)]

class PayloadInitialSubscription:
	var database_update: DatabaseUpdate = null; var request_id: int = -1
	var total_host_execution_duration: SpacetimeDuration = null
	static func from_dictionary(data: Dictionary) -> PayloadInitialSubscription:
		var i := PayloadInitialSubscription.new()
		if not data is Dictionary: return i
		if data.has("database_update"): i.database_update = DatabaseUpdate.from_dictionary(data.get("database_update"))
		i.request_id = int(data.get("request_id", -1.0))
		if data.has("total_host_execution_duration"): i.total_host_execution_duration = SpacetimeDuration.from_dictionary(data.get("total_host_execution_duration"))
		return i
	func _to_string(): return "PayloadInitialSubscription[ReqID:%d, DB:%s, Dur:%s]" % [request_id, str(database_update), str(total_host_execution_duration)]

class PayloadTransactionUpdate:
	var status: TransactionStatus = null; var timestamp: SpacetimeTimestamp = null
	var caller_identity: SpacetimeIdentity = null
	var caller_connection_id: SpacetimeConnectionId = null
	var reducer_call: ReducerCallInfo = null # Can be null
	var energy_quanta_used: Dictionary = {}; var total_host_execution_duration: SpacetimeDuration = null
	static func from_dictionary(data: Dictionary) -> PayloadTransactionUpdate:
		var i := PayloadTransactionUpdate.new()
		if not data is Dictionary: return i
		if data.has("status"): i.status = TransactionStatus.from_dictionary(data.get("status"))
		if data.has("timestamp"): i.timestamp = SpacetimeTimestamp.from_dictionary(data.get("timestamp"))
		if data.has("caller_identity"): i.caller_identity = SpacetimeIdentity.from_dictionary(data.get("caller_identity"))
		if data.has("caller_connection_id"): i.caller_connection_id = SpacetimeConnectionId.from_dictionary(data.get("caller_connection_id"))
		if data.has("reducer_call") and data["reducer_call"] is Dictionary: # Reducer call is optional
			i.reducer_call = ReducerCallInfo.from_dictionary(data.get("reducer_call"))
		i.energy_quanta_used = data.get("energy_quanta_used", {})
		if data.has("total_host_execution_duration"): i.total_host_execution_duration = SpacetimeDuration.from_dictionary(data.get("total_host_execution_duration"))
		return i
		
	func get_request_id() -> int: return reducer_call.request_id if reducer_call else -1
	func _to_string(): return "PayloadTransactionUpdate[Status:%s, Reducer?:%s]" % [str(status), str(reducer_call)]
	
enum PacketType {
	UNKNOWN,
	IDENTITY_TOKEN,
	INITIAL_SUBSCRIPTION,
	TRANSACTION_UPDATE
}


var packet_type: PacketType = PacketType.UNKNOWN
var raw_data: Dictionary = {}
var identity_token: PayloadIdentityToken = null
var initial_subscription: PayloadInitialSubscription = null
var transaction_update: PayloadTransactionUpdate = null

static func from_dictionary(raw_dict: Dictionary) -> SpacetimePacket:
	var instance := SpacetimePacket.new() 
	instance.raw_data = raw_dict

	if not raw_dict is Dictionary or raw_dict.is_empty():
		printerr("SpacetimePacket: Input is not a valid Dictionary or is empty.")
		instance.packet_type = PacketType.UNKNOWN
		return instance

	
	if raw_dict.size() == 0:
		instance.packet_type = PacketType.UNKNOWN
		return instance
		
	var main_key: String = raw_dict.keys()[0]
	var payload_dict: Variant = raw_dict[main_key]

	if raw_dict.size() != 1:
		printerr("SpacetimePacket: Warning: Expected 1 top-level key, found %d. Using key '%s'." % [raw_dict.size(), main_key])

	if not payload_dict is Dictionary:
		printerr("SpacetimePacket: Payload for key '%s' is not a Dictionary." % main_key)
		instance.packet_type = PacketType.UNKNOWN
		if main_key == "TransactionUpdate":
			instance.packet_type = PacketType.TRANSACTION_UPDATE
			instance.transaction_update = PayloadTransactionUpdate.from_dictionary(raw_dict)
			printerr("SpacetimePacket: Attempted TransactionUpdate parse from top level.")
		return instance
		
	match main_key:
		"IdentityToken":
			instance.packet_type = PacketType.IDENTITY_TOKEN
			instance.identity_token = PayloadIdentityToken.from_dictionary(payload_dict)
		"InitialSubscription":
			instance.packet_type = PacketType.INITIAL_SUBSCRIPTION
			instance.initial_subscription = PayloadInitialSubscription.from_dictionary(payload_dict)
		"TransactionUpdate":
			instance.packet_type = PacketType.TRANSACTION_UPDATE
			instance.transaction_update = PayloadTransactionUpdate.from_dictionary(payload_dict)
		_:
			printerr("SpacetimePacket: Unknown packet type key: '%s'" % main_key)
			instance.packet_type = PacketType.UNKNOWN

	return instance
	
func is_type(type: PacketType) -> bool:
	return packet_type == type

func get_request_id() -> int:
	match packet_type:
		PacketType.INITIAL_SUBSCRIPTION:
			return initial_subscription.request_id if initial_subscription else -1
		PacketType.TRANSACTION_UPDATE:
			return transaction_update.get_request_id() if transaction_update else -1
		_:
			return -1 
			
func _to_string() -> String:
	match packet_type:
		PacketType.IDENTITY_TOKEN: return "SpacetimePacket[Type:IdentityToken, Payload:%s]" % str(identity_token)
		PacketType.INITIAL_SUBSCRIPTION: return "SpacetimePacket[Type:InitialSubscription, Payload:%s]" % str(initial_subscription)
		PacketType.TRANSACTION_UPDATE: return "SpacetimePacket[Type:TransactionUpdate, Payload:%s]" % str(transaction_update)
		_: return "SpacetimePacket[Type:UNKNOWN, Raw:%s]" % str(raw_data)
		
func get_committed_table_updates(table_name: String) -> TableUpdate:
	if is_type(PacketType.TRANSACTION_UPDATE) and \
		transaction_update and \
		transaction_update.status and \
		transaction_update.status.is_committed() and \
		transaction_update.status.committed_update:
			return transaction_update.status.committed_update.get_updates_for_table(table_name)
	return null
