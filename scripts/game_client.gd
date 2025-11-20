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

const SERVER_IP = "127.0.0.1"
const PORT = 7777
const SNAPSHOT_HISTORY_LIMIT = NetworkConfig.SNAPSHOT_RATE * 4  # ~400ms of baseline history

func _ready():
	add_child(interpolator)
	
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
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
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

	# Handle input
	_handle_input()

	# Rate-limit input sending to avoid spamming the server
	last_input_send_time += delta
	if last_input_send_time >= (1.0 / INPUT_SEND_RATE):
		# Send input along with the last received snapshot sequence (ack) for delta compression
		receive_player_input.rpc_id(1, input_direction, last_snapshot_sequence)
		last_input_send_time = 0.0

func _handle_input():
	input_direction = Vector2.ZERO

	if auto_move_enabled:
		auto_move_timer += get_process_delta_time()
		# Circular motion
		input_direction = Vector2(cos(auto_move_timer * 2.0), sin(auto_move_timer * 2.0))
		# No normalization needed for sin/cos, it's already length 1
		return

	if Input.is_action_pressed("ui_right"):
		input_direction.x += 1
	if Input.is_action_pressed("ui_left"):
		input_direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		input_direction.y += 1
	if Input.is_action_pressed("ui_up"):
		input_direction.y -= 1

	input_direction = input_direction.normalized()

@rpc("any_peer", "call_remote", "unreliable")
func receive_player_input(input_dir: Vector2, ack: int):
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

	# Track packet loss (missed sequence numbers)
	if last_snapshot_sequence != -1:
		var expected_sequence = last_snapshot_sequence + 1
		if snapshot.sequence > expected_sequence:
			var lost = snapshot.sequence - expected_sequence
			packets_lost += lost
			print("[CLIENT] WARNING: Packet loss detected! Expected seq ", expected_sequence,
				  " but got ", snapshot.sequence, " (lost ", lost, " packets)")
	last_snapshot_sequence = snapshot.sequence

	# Update baselines
	server_baseline = snapshot
	snapshots_by_sequence[snapshot.sequence] = snapshot
	_trim_snapshot_history()
	awaiting_full_snapshot = false

	# CRITICAL FIX: Track player entity using explicit ID from server
	if my_entity_id == -1 and snapshot.player_entity_id != -1:
		my_entity_id = snapshot.player_entity_id
		print("[CLIENT] Player entity ID tracked: ", my_entity_id)

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
			
		# Verify other players are moving
		for eid in snapshot.entities:
			if eid != my_entity_id:
				var e = snapshot.entities[eid]
				# Heuristic: Player IDs are usually small integers from server logic, but here they are spawned. 
				# Let's just log one.
				print("[CLIENT] Remote Entity ", eid, " Pos: ", e.position, " Vel: ", e.velocity)
				break 

	# Pass to interpolator
	interpolator.receive_snapshot(snapshot)

	# Debug - check if player disappeared
	if my_entity_id != -1 and not snapshot.entities.has(my_entity_id):
		print("[CLIENT] ERROR: Player entity ", my_entity_id, " NOT in snapshot #", snapshot.sequence,
			  "! Entities in snapshot: ", snapshot.entities.keys())

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
