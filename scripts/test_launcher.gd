extends Control

## Test launcher for the snapshot interpolation system
## Choose to run as Server or Client

class LineChart:
	extends Control

	var title: String
	var samples: Array[float] = []
	var max_samples: int = 120  # ~120 frames (~2s at 60fps)
	var line_color: Color = Color.CYAN
	var fill_color: Color = Color(0.2, 0.6, 0.8, 0.2)

	func _init(t: String = "", c: Color = Color.CYAN):
		title = t
		line_color = c
		fill_color = Color(c.r, c.g, c.b, 0.18)
		custom_minimum_size = Vector2(260, 140)

	func add_sample(value: float):
		samples.append(value)
		if samples.size() > max_samples:
			samples.pop_front()
		queue_redraw()

	func _draw():
		var rect = Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0, 0, 0, 0.45))
		draw_rect(Rect2(rect.position, rect.size), Color(0.25, 0.25, 0.25, 0.6), false, 2)

		# Title
		var font = get_theme_default_font()
		if font:
			draw_string(font, Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.95))

		if samples.is_empty():
			return

		var max_val: float = 0.0
		for v in samples:
			if v > max_val:
				max_val = v
		max_val = max(1.0, max_val)

		var graph_rect = Rect2(rect.position + Vector2(8, 24), rect.size - Vector2(16, 32))
		var count = samples.size()
		var step = 0.0 if count <= 1 else graph_rect.size.x / float(count - 1)

		var points: PackedVector2Array = PackedVector2Array()
		for i in range(count):
			var t = float(i) / float(max(count - 1, 1))
			var x = graph_rect.position.x + step * i
			var norm = clamp(samples[i] / max_val, 0.0, 1.0)
			var y = graph_rect.position.y + graph_rect.size.y * (1.0 - norm)
			points.append(Vector2(x, y))

		# Fill under curve
		if points.size() >= 2:
			var fill_points: PackedVector2Array = PackedVector2Array(points)
			fill_points.append(graph_rect.position + Vector2(graph_rect.size.x, graph_rect.size.y))
			fill_points.append(graph_rect.position + Vector2(0, graph_rect.size.y))
			var fills := PackedColorArray()
			fills.resize(fill_points.size())
			for i in range(fill_points.size()):
				fills[i] = fill_color
			draw_polygon(fill_points, fills)

		if points.size() >= 2:
			draw_polyline(points, line_color, 2.0, true)

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
var charts_container: HBoxContainer = null
var server_bw_chart: LineChart = null
var server_snap_chart: LineChart = null

func _ready():
	set_process(true)
	
	# Debug auto-start
	var args = OS.get_cmdline_args()
	var test_mode_env = OS.get_environment("TEST_MODE")
	print("[LAUNCHER] Args: ", args)
	print("[LAUNCHER] TEST_MODE: ", test_mode_env)

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

	# Charts (hidden until server is running)
	charts_container = HBoxContainer.new()
	charts_container.visible = false
	charts_container.add_theme_constant_override("separation", 12)
	vbox.add_child(charts_container)

	server_bw_chart = LineChart.new("Server bandwidth (KB/s)", Color(0.2, 0.8, 1.0))
	server_snap_chart = LineChart.new("Snapshots per second", Color(0.8, 0.9, 0.3))
	charts_container.add_child(server_bw_chart)
	charts_container.add_child(server_snap_chart)

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

	# Check command line args for auto-start
	
	if "--server" in args or test_mode_env == "server":
		_on_server_button_pressed()
	elif "--client" in args or test_mode_env == "client":
		_on_client_button_pressed()

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
	charts_container.visible = true

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
	charts_container.visible = false

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
		# Feed charts
		server_bw_chart.add_sample(stats.kilobytes_per_second)
		server_snap_chart.add_sample(stats.snapshots_per_second)
