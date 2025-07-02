@tool
@icon("res://addons/SpacetimeDB/Icons/node_icon.svg")
extends Node
class_name RowReceiver

@export var table_to_receive: _ModuleTable : set = on_set;
var selected_table_name: String : set = set_selected_table_name

var _derived_table_names: Array[String] = []

signal insert(row: _ModuleTable)
signal update(prev: _ModuleTable, row: _ModuleTable)
signal delete(row: _ModuleTable)
signal transactions_completed

var _current_db_instance = null 

func _get_db():
	if _current_db_instance == null or not is_instance_valid(_current_db_instance):
		_current_db_instance = SpacetimeDB.get_local_database()
	return _current_db_instance
	
func on_set(schema: _ModuleTable):
	
	_derived_table_names.clear()

	if schema == null:
		name = "Receiver [EMPTY]"
		table_to_receive = schema
		if selected_table_name != "":
			set_selected_table_name("")
	else:
		var script_resource: Script = schema.get_script()
		
		if script_resource is Script:
			var global_name: String = script_resource.get_global_name().replace("_gd", "")
			if global_name == "_ModuleTable": 
				push_error("_ModuleTable is the base class for tables, not a reciever table. Selection is not changed.")
				return
			table_to_receive = schema
			name = "Receiver [%s]" % global_name

			var constant_map = script_resource.get_script_constant_map()
			if constant_map.has("table_names"):
				var names_value = constant_map["table_names"]
				if names_value is Array:
					for item in names_value:
						if item is String:
							_derived_table_names.push_back(item)
		else:
			name = "Receiver [Unknown Schema Type]"
		
	var current_selection_still_valid = _derived_table_names.has(selected_table_name)
	if not current_selection_still_valid:
		if not _derived_table_names.is_empty():
			set_selected_table_name(_derived_table_names[0])
		else:
			if selected_table_name != "":
				set_selected_table_name("")
	
	if Engine.is_editor_hint():
		property_list_changed.emit()


func set_selected_table_name(value: String):
	if selected_table_name == value:
		return
	selected_table_name = value


func _get_property_list() -> Array:
	var properties: Array = []
	if not _derived_table_names.is_empty():
		var hint_string_for_enum = ",".join(_derived_table_names)
		properties.append({
			"name": "selected_table_name",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": hint_string_for_enum
		})
	return properties


func _ready() -> void:
	if Engine.is_editor_hint():
		return;
	
	var db = _get_db()
	if db == null:
		await SpacetimeDB.database_initialized
		db = _get_db()
		
	_subscribe_to_table(selected_table_name)

	if not table_to_receive:
		push_error("No data schema. Node path: ", get_path())
		return;
	
	if get_parent() and not get_parent().is_node_ready():
		await get_parent().ready
	
	var data = db.get_all_rows(selected_table_name)
	for row_data in data:
		_on_insert(row_data)
		
func _subscribe_to_table(table_name_sn: StringName):
	if Engine.is_editor_hint() or table_name_sn == &"":
		return
	var db = _get_db()
	if not is_instance_valid(db): return

	db.subscribe_to_inserts(table_name_sn, Callable(self, "_on_insert"))
	db.subscribe_to_updates(table_name_sn, Callable(self, "_on_update"))
	db.subscribe_to_deletes(table_name_sn, Callable(self, "_on_delete"))
	db.subscribe_to_transactions_completed(table_name_sn, Callable(self, "_on_transactions_completed"))

func _unsubscribe_from_table(table_name_sn: StringName):
	if Engine.is_editor_hint() or table_name_sn == &"":
		return
	var db = _get_db()
	if not is_instance_valid(db): return 

	db.unsubscribe_from_inserts(table_name_sn, Callable(self, "_on_insert"))
	db.unsubscribe_from_updates(table_name_sn, Callable(self, "_on_update"))
	db.unsubscribe_from_deletes(table_name_sn, Callable(self, "_on_delete"))
	db.unsubscribe_from_transactions_completed(table_name_sn, Callable(self, "_on_transactions_completed"))
	
func _on_insert(row: _ModuleTable):
	insert.emit(row)

func _on_update(row: _ModuleTable, previous: _ModuleTable):
	update.emit(row, previous)

func _on_delete(row: _ModuleTable):
	delete.emit(row)

func _on_transactions_completed():
	transactions_completed.emit()

func get_table_data() -> Array[_ModuleTable]:
	var local_db = SpacetimeDB.get_local_database()
	if local_db:
		return local_db.get_all_rows(selected_table_name)
	return []
