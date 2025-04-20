extends Resource
class_name RowReceiver

@export var data_to_receive: Resource;
var data_instance: Resource;

signal update(row)
signal delete(row)

func _init() -> void:
	SpacetimeDB.row_inserted.connect(_on_insert)
	SpacetimeDB.row_updated.connect(_on_insert)
	SpacetimeDB.row_deleted.connect(_on_delete)
	#Hack to create instance after init
	await Engine.get_main_loop().process_frame
	if data_instance == null:data_instance = data_to_receive.new();
	
func _on_insert(table_name: String, row: Resource):
	if row.get_meta("table_name") != data_instance.get_meta("table_name"):
		return
	update.emit(row)

func _on_delete(table_name: String, row: Resource):
	if row.get_meta("table_name") != data_instance.get_meta("table_name"):
		return
	delete.emit(row)
	pass;
	
