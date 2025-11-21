extends Node
class_name GameClient

## Example game client with snapshot interpolation

const SERVER_IP = "127.0.0.1"
const PORT = 7777

@onready var interpolator = ClientInterpolator.new()

var peer: ENetMultiplayerPeer
var connected: bool = false
var server_baseline: EntitySnapshot = null
var my_entity_id: int = -1  # Track which entity is the player
var server_ip_override: String = SERVER_IP  # Allow overriding via CLI/testing

# Input
var input_direction: Vector2 = Vector2.ZERO
var last_input_send_time: float = 0.0
const INPUT_SEND_RATE = 20  # Send input 20 times per second

# Bandwidth and network metrics tracking
var bytes_received_this_second: int = 0
var bytes_received_per_second: int = 0
var snapshots_received_this_second: int = 0
var snapshots_received_per_second: int = 0
var last_snapshot_sequence: int = -1
var packets_lost: int = 0
var total_packets_received: int = 0
var bandwidth_timer: float = 0.0

# FPS tracking
var frames_this_second: int = 0
var fps: int = 0

# Automated test / lag simulation options
var autotest_enabled: bool = false
var autotest_label: String = ""
var autotest_move_pattern: String = ""
var autotest_move_radius: float = 180.0
var autotest_move_interval: float = 2.5
var autotest_fake_lag_ms: float = 0.0
var autotest_fake_jitter_ms: float = 0.0
var autotest_packet_loss: float = 0.0
var autotest_start_time_ms: int = 0
var autotest_log_timer: float = 0.0
var autotest_time: float = 0.0
var autotest_exit_after: float = 0.0

# Delayed snapshot queue for artificial lag
var delayed_snapshots: Array[Dictionary] = []  # {deliver_at: int, data: PackedByteArray}

func _ready():
	add_child(interpolator)
	# Don't auto-connect for now - wait for user input
	# Uncomment to auto-connect:
	# _connect_to_server()

func _connect_to_server():
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(server_ip_override, PORT)

	if error != OK:
		print("Failed to connect to server: ", error)
		return

	# Enable compression to reduce bandwidth by 60-90%
	peer.get_host().compress(ENetConnection.COMPRESS_FASTLZ)

	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	print("Connecting to server at ", server_ip_override, ":", PORT,
		  autotest_enabled ? " | autotest=" + autotest_label : "")

func _on_connected_to_server():
	print("Connected to server!", autotest_enabled ? " | autotest=" + autotest_label : "")
	connected = true
	autotest_start_time_ms = Time.get_ticks_msec()

func _on_connection_failed():
	print("Connection failed", autotest_enabled ? " | autotest=" + autotest_label : "")
	connected = false

func _on_server_disconnected():
	print("Disconnected from server", autotest_enabled ? " | autotest=" + autotest_label : "")
	connected = false

func _process(delta: float):
	# Track FPS
	frames_this_second += 1

	if not connected:
		# Still track FPS even when not connected
		bandwidth_timer += delta
		if bandwidth_timer >= 1.0:
			fps = frames_this_second
			frames_this_second = 0
			bandwidth_timer = 0.0
		return

	# Update bandwidth and FPS tracking
	bandwidth_timer += delta
	if bandwidth_timer >= 1.0:
		bytes_received_per_second = bytes_received_this_second
		snapshots_received_per_second = snapshots_received_this_second
		fps = frames_this_second
		bytes_received_this_second = 0
		snapshots_received_this_second = 0
		frames_this_second = 0
		bandwidth_timer = 0.0

	# Deliver delayed snapshots used to simulate latency/jitter
	_drain_delayed_snapshots()

	# Handle input
	_handle_input(delta)

	# Rate-limit input sending to avoid spamming the server
	last_input_send_time += delta
	if last_input_send_time >= (1.0 / INPUT_SEND_RATE):
		receive_player_input.rpc_id(1, input_direction)
		last_input_send_time = 0.0

	# Emit recurring autotest telemetry for easier log inspection
	if autotest_enabled and connected:
		autotest_log_timer += delta
		if autotest_log_timer >= 1.0:
			autotest_log_timer = 0.0
			var stats = get_network_stats()
			var player_state = interpolator.get_entity_state(my_entity_id)
			var player_pos = player_state.current_position if player_state else Vector2.ZERO
			var player_vel = player_state.current_velocity if player_state else Vector2.ZERO

			print("[AUTOTEST][", autotest_label, "] delay=", "%.0f" % stats.render_delay_ms,
				  "ms | buffer=", stats.buffer_size,
				  " | snapshots/s=", stats.snapshots_per_second,
				  " | packet_loss=", "%.2f" % stats.packet_loss_percent, "%",
				  " | player_pos=", player_pos,
				  " | player_vel=", player_vel,
				  " | input=", input_direction)

	# Respect optional exit timer for headless runs
	if autotest_enabled and autotest_exit_after > 0.0:
		var runtime = (Time.get_ticks_msec() - autotest_start_time_ms) / 1000.0
		if runtime >= autotest_exit_after:
			print("[AUTOTEST][", autotest_label, "] exit_after reached (", runtime, "s). Quitting client.")
			get_tree().quit()

func _handle_input_keyboard():
	input_direction = Vector2.ZERO

	if Input.is_action_pressed("ui_right"):
		input_direction.x += 1
	if Input.is_action_pressed("ui_left"):
		input_direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		input_direction.y += 1
	if Input.is_action_pressed("ui_up"):
		input_direction.y -= 1

	input_direction = input_direction.normalized()

func _handle_input(delta: float):
	if autotest_enabled and autotest_move_pattern != "":
		input_direction = _autotest_input(delta)
	else:
		_handle_input_keyboard()

@rpc("any_peer", "call_remote", "unreliable")
func receive_player_input(input_dir: Vector2):
	# This is defined on server - this is just a stub for RPC registration
	pass

## Receive snapshot from server
@rpc("authority", "call_remote", "unreliable")
func receive_snapshot_data(data: PackedByteArray):
	# Artificial network conditions for tests
	if autotest_enabled:
		if autotest_packet_loss > 0.0 and randf() < autotest_packet_loss:
			print("[AUTOTEST][", autotest_label, "] DROP packet (simulated loss)")
			return

		var delay_ms = autotest_fake_lag_ms
		if autotest_fake_jitter_ms > 0.0:
			delay_ms += randf_range(0.0, autotest_fake_jitter_ms)

		if delay_ms > 0.0:
			var deliver_at = Time.get_ticks_msec() + int(delay_ms)
			delayed_snapshots.append({"deliver_at": deliver_at, "data": data})
			return

	_process_snapshot_now(data)

func _drain_delayed_snapshots():
	if delayed_snapshots.is_empty():
		return

	var now = Time.get_ticks_msec()
	for i in range(delayed_snapshots.size() - 1, -1, -1):
		var entry = delayed_snapshots[i]
		if entry["deliver_at"] <= now:
			_process_snapshot_now(entry["data"])
			delayed_snapshots.remove_at(i)

func _process_snapshot_now(data: PackedByteArray):
	# Track bandwidth
	bytes_received_this_second += data.size()
	snapshots_received_this_second += 1
	total_packets_received += 1

	# Deserialize snapshot
	var snapshot = EntitySnapshot.deserialize(data, server_baseline)

	# Track packet loss (missed sequence numbers)
	if last_snapshot_sequence != -1:
		var expected_sequence = last_snapshot_sequence + 1
		if snapshot.sequence > expected_sequence:
			var lost = snapshot.sequence - expected_sequence
			packets_lost += lost
			print("[CLIENT] WARNING: Packet loss detected! Expected seq ", expected_sequence,
				  " but got ", snapshot.sequence, " (lost ", lost, " packets)")
	last_snapshot_sequence = snapshot.sequence

	# Update baseline
	server_baseline = snapshot

	# CRITICAL FIX: Track player entity using explicit ID from server
	if my_entity_id == -1 and snapshot.player_entity_id != -1:
		my_entity_id = snapshot.player_entity_id
		print("[CLIENT] Player entity ID tracked: ", my_entity_id)
		if autotest_enabled:
			interpolator.enable_debug_watch(my_entity_id, autotest_label)

	# Debug logging (every 100 snapshots)
	if snapshot.sequence % 100 == 0:
		var player_in_snapshot = snapshot.entities.has(my_entity_id)
		var current_time = Time.get_ticks_msec() / 1000.0
		print("[CLIENT] Received snapshot #", snapshot.sequence,
			  " | Snapshot timestamp: ", snapshot.timestamp,
			  " | Current client time: ", current_time,
			  " | Interpolator render_time: ", interpolator.render_time,
			  " | Interpolator latest_server_time: ", interpolator.latest_server_time,
			  " | Entities: ", snapshot.entities.size(),
			  " | Player in snapshot: ", player_in_snapshot,
			  " | Player ID: ", my_entity_id,
			  " | Data size: ", data.size(), " bytes")

	# Pass to interpolator
	interpolator.receive_snapshot(snapshot)

	# Debug - check if player disappeared
	if my_entity_id != -1 and not snapshot.entities.has(my_entity_id):
		print("[CLIENT] ERROR: Player entity ", my_entity_id, " NOT in snapshot #", snapshot.sequence,
			  "! Entities in snapshot: ", snapshot.entities.keys())

## Get interpolated entities for rendering
func get_entities() -> Dictionary:
	return interpolator.get_all_entities()

## Get a single entity state (used by autotest logs)
func get_entity_state(entity_id: int) -> ClientInterpolator.InterpolatedEntity:
	return interpolator.get_entity_state(entity_id)

## Get comprehensive network stats for UI
func get_network_stats() -> Dictionary:
	var packet_loss_percent = 0.0
	if total_packets_received > 0:
		packet_loss_percent = (float(packets_lost) / float(total_packets_received + packets_lost)) * 100.0

	var avg_packet_size = 0.0
	if snapshots_received_per_second > 0:
		avg_packet_size = float(bytes_received_per_second) / float(snapshots_received_per_second)

	return {
		"bytes_per_second": bytes_received_per_second,
		"kilobytes_per_second": bytes_received_per_second / 1024.0,
		"snapshots_per_second": snapshots_received_per_second,
		"packet_loss_percent": packet_loss_percent,
		"packets_lost": packets_lost,
		"total_packets": total_packets_received + packets_lost,
		"avg_packet_size": avg_packet_size,
		"buffer_size": interpolator.snapshot_buffer.size(),
		"render_delay_ms": (interpolator.latest_server_time - interpolator.render_time) * 1000.0,
		"entities_count": interpolator.interpolated_entities.size(),
		"fps": fps
	}

## Configure automated test settings from CLI dictionary (see test_launcher.gd)
func configure_autotest(args: Dictionary):
	autotest_enabled = true
	autotest_label = args.get("autotest_id", args.get("label", "client"))
	autotest_move_pattern = args.get("auto-move", "")
	autotest_move_radius = float(args.get("auto-radius", str(autotest_move_radius)))
	autotest_move_interval = float(args.get("auto-interval", str(autotest_move_interval)))
	autotest_fake_lag_ms = float(args.get("fake-lag-ms", "0"))
	autotest_fake_jitter_ms = float(args.get("fake-jitter-ms", "0"))
	autotest_packet_loss = float(args.get("packet-loss", "0"))
	autotest_exit_after = float(args.get("exit_after", "0"))
	server_ip_override = args.get("connect_ip", SERVER_IP)

	# Forward debug tag to interpolator for log clarity
	if interpolator:
		interpolator.enable_debug_watch(my_entity_id, autotest_label)

	print("[AUTOTEST] Configured client label=", autotest_label,
		  " move=", autotest_move_pattern,
		  " lag=", autotest_fake_lag_ms, "ms+/-", autotest_fake_jitter_ms, "ms",
		  " drop=", autotest_packet_loss * 100.0, "%")

func _autotest_input(delta: float) -> Vector2:
	autotest_time += delta

	match autotest_move_pattern:
		"circle":
			var angle = autotest_time * 0.8  # radians/sec
			return Vector2(cos(angle), sin(angle))
		"line":
			# Ping-pong between left/right every interval
			var phase = int(floor(autotest_time / autotest_move_interval)) % 2
			return Vector2(1, 0) if phase == 0 else Vector2(-1, 0)
		"figure8":
			var angle_f = autotest_time
			return Vector2(cos(angle_f), sin(angle_f*2.0)).normalized()
		"dashes":
			# Burst movement to stress reconciliation
			var pulse = int(floor(autotest_time * 2.0)) % 4
			if pulse == 0:
				return Vector2.RIGHT
			if pulse == 1:
				return Vector2.DOWN
			if pulse == 2:
				return Vector2.LEFT
			return Vector2.UP
		_:
			# Default: gentle diagonal
			return Vector2(1, 1).normalized()
