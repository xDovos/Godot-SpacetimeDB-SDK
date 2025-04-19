extends Resource
class_name RowReceiver

@export var data_to_receive: Resource;
var data_instance: Resource;

signal on_receive(row)

func _init() -> void:
	SpacetimeDB.row_inserted.connect(_on_receive)
	SpacetimeDB.row_updated.connect(_on_receive)
	#Hack to create instance after init
	await Engine.get_main_loop().process_frame
	if data_instance == null:data_instance = data_to_receive.new();
	
func _on_receive(table_name: String, row: Resource):
	if row.get_meta("table_name") != data_instance.get_meta("table_name"):
		return
	on_receive.emit(row)
