extends Node
class_name GameClient

## Example game client with snapshot interpolation

@onready var interpolator = ClientInterpolator.new()

var peer: ENetMultiplayerPeer
var connected: bool = false
var server_baseline: EntitySnapshot = null
var snapshots_by_sequence: Dictionary = {}  # seq -> EntitySnapshot for baseline lookup
var my_entity_id: int = -1  # Track which entity is the player
var awaiting_full_snapshot: bool = false

# Input
var input_direction: Vector2 = Vector2.ZERO
var last_input_send_time: float = 0.0
const INPUT_SEND_RATE = 20  # Send input 20 times per second
var local_player: CharacterBody2D = null
const LocalPlayerScript = preload("res://scripts/local_player.gd")

# Automated Testing
var auto_move_enabled: bool = false
var auto_move_timer: float = 0.0

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

# Clock Synchronization
var sync_timer: float = 0.0
var clock_offsets: Array = [] # Buffer for smoothing
const CLOCK_SYNC_SMOOTHING_COUNT = 10

const SERVER_IP = "127.0.0.1"
const PORT = 7777
const SNAPSHOT_HISTORY_LIMIT = NetworkConfig.SNAPSHOT_RATE * 4  # ~400ms of baseline history

func _ready():
	add_child(interpolator)

	# Check if running in test mode
	var test_mode = OS.get_environment("TEST_MODE")
	if test_mode == "client":
		GameLogger.info("CLIENT", "Starting in automated test mode", {})
		TestAutomation.register_client(self)
		_connect_to_server()
	
	# Check for auto-move argument
	if "--auto-move" in OS.get_cmdline_args():
		auto_move_enabled = true
		print("[CLIENT] Auto-move enabled for testing")

	# Don't auto-connect for now - wait for user input
	# Uncomment to auto-connect:
	# _connect_to_server()

func _connect_to_server():
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(SERVER_IP, PORT)

	if error != OK:
		print("Failed to connect to server: ", error)
		return

	# Enable compression to reduce bandwidth by 60-90%
	peer.get_host().compress(ENetConnection.COMPRESS_FASTLZ)

	multiplayer.multiplayer_peer = peer
	
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	print("Connecting to server at ", SERVER_IP, ":", PORT)

func _on_connected_to_server():
	print("Connected to server!")
	connected = true

func _on_connection_failed():
	print("Connection failed")
	connected = false

func _on_server_disconnected():
	print("Disconnected from server")
	connected = false

func _physics_process(delta: float):
	if not connected:
		return

	# Handle input (get direction)
	_handle_input_generation()

	# Run Client-Side Prediction (CSP)
	if local_player:
		var current_tick = int(interpolator.get_server_time() * NetworkConfig.TICK_RATE)
		local_player.process_tick(current_tick, input_direction)

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

	# Clock synchronization
	sync_timer += delta
	if sync_timer >= NetworkConfig.CLOCK_SYNC_INTERVAL:
		sync_clock()
		sync_timer = 0.0

	# Rate-limit input sending to avoid spamming the server
	last_input_send_time += delta
	if last_input_send_time >= (1.0 / INPUT_SEND_RATE):
		# Calculate current tick based on synchronized server time
		var current_tick = int(interpolator.get_server_time() * NetworkConfig.TICK_RATE)
		var current_render_time = interpolator.render_time
		
		# Send input along with the last received snapshot sequence (ack) for delta compression
		receive_player_input.rpc_id(1, input_direction, current_tick, current_render_time, last_snapshot_sequence)
		last_input_send_time = 0.0

func _handle_input_generation():
	# Check if test automation is active
	if TestAutomation.is_active():
		# Update test automation with current player position
		if local_player:
			TestAutomation.update_player_position(local_player.position)
		elif my_entity_id != -1:
			var player_pos = interpolator.get_entity_position(my_entity_id)
			TestAutomation.update_player_position(player_pos)

		# Get automated input
		input_direction = TestAutomation.get_input_direction()
	elif auto_move_enabled:
		auto_move_timer += get_physics_process_delta_time()
		# Circular motion
		input_direction = Vector2(cos(auto_move_timer * 2.0), sin(auto_move_timer * 2.0))
	else:
		# Manual input
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

func sync_clock():
	# Send current local time to server
	request_clock_sync.rpc_id(1, Time.get_ticks_msec())

@rpc("any_peer", "call_remote", "unreliable")
func request_clock_sync(client_time: int):
	# Server-side method
	pass

@rpc("authority", "call_remote", "unreliable")
func return_clock_sync(client_send_time: int, server_receive_time: int, server_send_time: int):
	var client_receive_time = Time.get_ticks_msec()
	
	# Calculate RTT
	# RTT = (t4 - t1) - (t3 - t2)
	var rtt = (client_receive_time - client_send_time) - (server_send_time - server_receive_time)
	
	# Calculate Server Time at the moment of receiving response
	# ServerTime = t3 + RTT/2
	var server_time = server_send_time + (rtt / 2.0)
	
	# Calculate offset: ServerTime - ClientTime
	var offset = server_time - client_receive_time
	
	_update_clock_offset_robustly(offset)

func _update_clock_offset_robustly(new_offset: float):
	clock_offsets.append(new_offset)
	if clock_offsets.size() > CLOCK_SYNC_SMOOTHING_COUNT:
		clock_offsets.pop_front()
	
	if clock_offsets.size() < 3:
		# Not enough samples for robust stats, just use average
		var avg = 0.0
		for o in clock_offsets: avg += o
		interpolator.update_clock_offset(avg / clock_offsets.size())
		return

	# Sort offsets to find median and for outlier removal
	var sorted_offsets = clock_offsets.duplicate()
	sorted_offsets.sort()
	
	# Median
	var median = sorted_offsets[sorted_offsets.size() / 2]
	
	# Calculate Standard Deviation
	var mean = 0.0
	for o in sorted_offsets: mean += o
	mean /= sorted_offsets.size()
	
	var variance = 0.0
	for o in sorted_offsets: variance += pow(o - mean, 2)
	var std_dev = sqrt(variance / sorted_offsets.size())
	
	# Filter outliers (e.g. > 1.5 std dev from median)
	# If std_dev is very small (tight cluster), we might filter everything if we're not careful,
	# so we ensure we keep samples if std_dev is small.
	var valid_offsets = []
	for o in sorted_offsets:
		if std_dev < 1.0 or abs(o - median) <= (1.5 * std_dev):
			valid_offsets.append(o)
			
	# Re-calculate average of valid offsets
	if valid_offsets.size() > 0:
		var final_offset = 0.0
		for o in valid_offsets: final_offset += o
		final_offset /= valid_offsets.size()
		interpolator.update_clock_offset(final_offset)
	else:
		# Fallback to median if all are outliers (unlikely)
		interpolator.update_clock_offset(median)

@rpc("any_peer", "call_remote", "unreliable")
func receive_player_input(input_dir: Vector2, tick: int, render_time: float, ack: int):
	# This is defined on server - this is just a stub for RPC registration
	pass

@rpc("any_peer", "call_remote", "reliable")
func request_full_snapshot():
	# Stub so the client can send an RPC to the server requesting a keyframe
	pass

## Receive snapshot from server
@rpc("authority", "call_remote", "unreliable")
func receive_snapshot_data(data: PackedByteArray):
	# Track bandwidth
	bytes_received_this_second += data.size()
	snapshots_received_this_second += 1
	total_packets_received += 1

	# Peek header to pick the correct baseline (or request a keyframe if missing)
	var header = EntitySnapshot.peek_header(data)
	var baseline_seq: int = header.get("baseline_seq", 0)
	var baseline_snapshot: EntitySnapshot = null

	if baseline_seq > 0:
		if snapshots_by_sequence.has(baseline_seq):
			baseline_snapshot = snapshots_by_sequence[baseline_seq]
		else:
			print("[CLIENT] WARNING: Missing baseline #", baseline_seq, " for incoming snapshot #", header.get("sequence"), " - requesting keyframe")
			_request_full_snapshot()
			return

	# Deserialize snapshot with correct baseline (or full snapshot when baseline_seq == 0)
	var snapshot = EntitySnapshot.deserialize(data, baseline_snapshot)
	if snapshot == null:
		_request_full_snapshot()
		return

	# Network condition simulation: check if packet should be dropped
	if not NetworkSimulator.should_process_packet(snapshot.sequence):
		# Simulate packet loss - drop this packet
		return

	# Track packet loss (missed sequence numbers)
	if last_snapshot_sequence != -1:
		var expected_sequence = last_snapshot_sequence + 1
		if snapshot.sequence > expected_sequence:
			var lost = snapshot.sequence - expected_sequence
			packets_lost += lost
			GameLogger.warn("CLIENT", "Packet loss detected", {
				"expected_seq": expected_sequence,
				"got_seq": snapshot.sequence,
				"lost": lost
			})
	last_snapshot_sequence = snapshot.sequence

	# Update baselines
	server_baseline = snapshot
	snapshots_by_sequence[snapshot.sequence] = snapshot
	_trim_snapshot_history()
	awaiting_full_snapshot = false

	# CRITICAL FIX: Track player entity using explicit ID from server
	if my_entity_id == -1 and snapshot.player_entity_id != -1:
		my_entity_id = snapshot.player_entity_id
		GameLogger.info("CLIENT", "Player entity ID tracked", {"player_id": my_entity_id})
		
		# CSP: Spawn LocalPlayer
		if local_player == null:
			# Wait for entity to be in snapshot to get position
			if snapshot.has_entity(my_entity_id):
				var start_pos = snapshot.get_entity(my_entity_id).position
				local_player = LocalPlayerScript.new()
				add_child(local_player)
				local_player.setup(self, start_pos)
				interpolator.local_player_id = my_entity_id
				print("[CLIENT] LocalPlayer spawned for CSP at ", start_pos)

	# Debug logging (every 100 snapshots)
	if snapshot.sequence % 100 == 0:
		var delay_ms = (interpolator.latest_server_time - interpolator.render_time) * 1000.0
		GameLogger.log_snapshot_received(
			snapshot.sequence,
			snapshot.entities.size(),
			my_entity_id,
			delay_ms
		)

	# Pass to interpolator
	interpolator.receive_snapshot(snapshot)
	
	# CSP Reconciliation
	if local_player and snapshot.has_entity(my_entity_id):
		var state = snapshot.get_entity(my_entity_id)
		local_player.reconcile(state.position, snapshot.last_processed_input_tick)

	# Debug - check if player disappeared
	if my_entity_id != -1 and not snapshot.entities.has(my_entity_id):
		GameLogger.log_player_disappearance(my_entity_id, snapshot.sequence, false)

## Get interpolated entities for rendering
func get_entities() -> Dictionary:
	return interpolator.get_all_entities()

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

func _trim_snapshot_history():
	if snapshots_by_sequence.size() <= SNAPSHOT_HISTORY_LIMIT:
		return
	var keys = snapshots_by_sequence.keys()
	keys.sort()
	while keys.size() > SNAPSHOT_HISTORY_LIMIT:
		var oldest = keys.pop_front()
		snapshots_by_sequence.erase(oldest)

func _request_full_snapshot():
	if awaiting_full_snapshot:
		return  # Avoid spamming
	awaiting_full_snapshot = true
	request_full_snapshot.rpc_id(1)  # Ask server (peer 1) for a keyframe / full snapshot
	print("[CLIENT] Requested full snapshot/keyframe from server")