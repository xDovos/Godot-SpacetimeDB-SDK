@tool
extends EditorPlugin

const AUTOLOAD_NAME := "SpacetimeDB"
const AUTOLOAD_PATH := "res://addons/SpacetimeDB/Core/SpacetimeDBClient.gd"
const UI_PATH := "res://addons/SpacetimeDB/UI/ui.tscn"

var ui_panel: Control
var http_request = HTTPRequest.new();
var module_prefab:Control;

func _enter_tree():
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		# get_editor_interface().get_resource_filesystem().scan()
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		
	if not is_instance_valid(ui_panel):
		var scene = load(UI_PATH)
		if scene:
			ui_panel = scene.instantiate()
		else:
			printerr("Failed to load UI scene: ", UI_PATH)
			return

	if is_instance_valid(ui_panel):
		add_control_to_bottom_panel(ui_panel, AUTOLOAD_NAME)
	else:
		printerr("UI panel is not valid after instantiation attempt.")
	
	subscribe_controls()
		
func subscribe_controls():
	add_child(http_request)
	module_prefab = ui_panel.get_node("prefab").duplicate()
	
	ui_panel.get_node("CheckUri").button_down.connect(check_uri);
	ui_panel.get_node("Panel/Button").button_down.connect(add_module)
	ui_panel.get_node("Generate").button_down.connect(generate_code);
	pass;
	
func add_module():
	var new_module = module_prefab.duplicate()
	ui_panel.get_node("ScrollContainer/VBoxContainer").add_child(new_module)
	new_module.get_node("Button").button_down.connect(func() : new_module.queue_free())
	new_module.show()
	pass;

func generate_code():
	print_log("Start code gen")
	for i in ui_panel.get_node("ScrollContainer/VBoxContainer").get_children():
		var module_name = i.get_node("LineEdit").text
		var uri = ui_panel.get_node("Uri").text + "/v1/database/" + module_name + "/schema?version=9"
		http_request.request(uri)
		var result = await http_request.request_completed
		#print_log("Response code: " + str(result[1]))
		if result[1] == 200:
			var json = PackedByteArray(result[3]).get_string_from_utf8()
			#print_log(json)
			ui_panel.get_node("CodeGen")._on_request_completed(json)
			
	get_editor_interface().get_resource_filesystem().scan()
	print_log("Code gen end")
	pass;
	

func check_uri():
	var uri = ui_panel.get_node("Uri").text + "/v1/ping"
	http_request.request(uri)
	var result = await http_request.request_completed
	print_log("Response code: " + str(result[1]))
	pass;

func print_log(text:String):
	ui_panel.get_node("Log").text += text + "\n"
	pass;
	

func _exit_tree():
	if is_instance_valid(ui_panel):
		remove_control_from_bottom_panel(ui_panel)
		ui_panel.queue_free()
		ui_panel = null
		http_request.queue_free()
		http_request = null
		
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
