extends Control

## Test launcher for the snapshot interpolation system
## Choose to run as Server or Client

# Preload the classes
const GameServerScript = preload("res://scripts/game_server.gd")
const GameClientScript = preload("res://scripts/game_client.gd")
const ClientRendererScript = preload("res://scripts/client_renderer.gd")

@onready var info_label = Label.new()
@onready var server_button = Button.new()
@onready var client_button = Button.new()
@onready var status_label = Label.new()

var server_instance: Node = null
var client_instance: Node = null
var renderer: Node2D = null

func _ready():
	# Setup UI
	var vbox = VBoxContainer.new()
	vbox.position = Vector2(20, 20)
	add_child(vbox)

	info_label.text = "Snapshot Interpolation Test\nChoose mode:"
	vbox.add_child(info_label)

	server_button.text = "Start Server"
	server_button.pressed.connect(_on_server_button_pressed)
	vbox.add_child(server_button)

	client_button.text = "Start Client"
	client_button.pressed.connect(_on_client_button_pressed)
	vbox.add_child(client_button)

	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(status_label)

	# Instructions
	var instructions = Label.new()
	instructions.text = "\nInstructions:\n" + \
		"1. Start server in one instance\n" + \
		"2. Start client in another instance\n" + \
		"3. Use arrow keys to move\n\n" + \
		"Architecture features:\n" + \
		"- Server-authoritative simulation at " + str(NetworkConfig.TICK_RATE) + " Hz\n" + \
		"- Snapshots sent at " + str(NetworkConfig.SNAPSHOT_RATE) + " Hz\n" + \
		"- Hermite spline interpolation on client\n" + \
		"- Delta compression with quantization\n" + \
		"- Spatial partitioning for 10k+ players\n" + \
		"- " + str(int(NetworkConfig.TOTAL_CLIENT_DELAY * 1000)) + "ms interpolation delay"
	vbox.add_child(instructions)

func _on_server_button_pressed():
	if server_instance:
		return

	# Disable buttons
	server_button.disabled = true
	client_button.disabled = true

	# Start server
	server_instance = GameServerScript.new()
	add_child(server_instance)

	status_label.text = "Server running on port " + str(7777)
	status_label.add_theme_color_override("font_color", Color.GREEN)

	print("=== SERVER MODE ===")

func _on_client_button_pressed():
	if client_instance:
		return

	# Disable buttons
	server_button.disabled = true
	client_button.disabled = true

	# Start client
	client_instance = GameClientScript.new()
	add_child(client_instance)
	client_instance._connect_to_server()

	# Add renderer
	renderer = ClientRendererScript.new()
	renderer.game_client = client_instance
	add_child(renderer)

	status_label.text = "Client connecting to 127.0.0.1:7777"
	status_label.add_theme_color_override("font_color", Color.YELLOW)

	# Hide buttons after a moment (but keep status label visible)
	await get_tree().create_timer(2.0).timeout
	info_label.visible = false
	server_button.visible = false
	client_button.visible = false

	print("=== CLIENT MODE ===")

func _process(_delta: float):
	# Update client status with comprehensive network metrics
	if client_instance and client_instance.connected:
		var stats = client_instance.get_network_stats()
		var entities = client_instance.get_entities()

		status_label.text = "CLIENT METRICS\n" + \
			"━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" + \
			"FPS: %d | Render delay: %.0f ms\n" % [stats.fps, stats.render_delay_ms] + \
			"Bandwidth: %.2f KB/s (%.0f B/s)\n" % [stats.kilobytes_per_second, stats.bytes_per_second] + \
			"Snapshots: %d/s | Avg size: %.0f bytes\n" % [stats.snapshots_per_second, stats.avg_packet_size] + \
			"Packet loss: %.1f%% (%d/%d)\n" % [stats.packet_loss_percent, stats.packets_lost, stats.total_packets] + \
			"Buffer size: %d snapshots\n" % stats.buffer_size + \
			"Entities: %d visible | Player ID: %d" % [stats.entities_count, client_instance.my_entity_id]

		# Color code based on metrics health
		if stats.fps < 30 or stats.packet_loss_percent > 10.0 or stats.render_delay_ms > 500.0:
			status_label.add_theme_color_override("font_color", Color.RED)
		elif stats.fps < 50 or stats.packet_loss_percent > 5.0 or stats.render_delay_ms > 300.0:
			status_label.add_theme_color_override("font_color", Color.ORANGE)
		else:
			status_label.add_theme_color_override("font_color", Color.GREEN)

	# Update server status with bandwidth metrics
	elif server_instance:
		var stats = server_instance.get_bandwidth_stats()

		status_label.text = "SERVER METRICS\n" + \
			"━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" + \
			"Bandwidth: %.2f KB/s (%.0f B/s)\n" % [stats.kilobytes_per_second, stats.bytes_per_second] + \
			"Snapshots: %d/s | Avg size: %.0f bytes\n" % [stats.snapshots_per_second, stats.avg_snapshot_size] + \
			"Connected clients: %d\n" % stats.connected_peers + \
			"Tick rate: %d Hz | Snapshot rate: %d Hz\n" % [NetworkConfig.TICK_RATE, NetworkConfig.SNAPSHOT_RATE] + \
			"Total entities: %d | Current tick: %d" % [stats.total_entities, server_instance.world.current_tick]

		status_label.add_theme_color_override("font_color", Color.CYAN)
