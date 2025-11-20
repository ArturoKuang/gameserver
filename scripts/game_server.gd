extends Node
class_name GameServer

## Example game server demonstrating the snapshot interpolation system
## This would be run as a dedicated server or listen server

@onready var world = ServerWorld.new()

# Network peers
var peer: ENetMultiplayerPeer
var connected_peers: Dictionary = {}  # peer_id -> player_entity_id

# Bandwidth tracking
var bytes_sent_this_second: int = 0
var bytes_sent_per_second: int = 0
var snapshots_sent_this_second: int = 0
var snapshots_sent_per_second: int = 0
var bandwidth_timer: float = 0.0

const PORT = 7777
const MAX_CLIENTS = 100  # Can scale to 10,000 with proper server infrastructure

func _ready():
	add_child(world)
	_start_server()

	# Spawn some NPC entities for testing
	for i in range(50):
		var pos = Vector2(
			randf_range(-500, 500),
			randf_range(-500, 500)
		)
		var npc_id = world.spawn_entity(pos)
		# Give NPCs some random movement
		world.set_entity_velocity(npc_id, Vector2(
			randf_range(-20, 20),
			randf_range(-20, 20)
		))

	# Spawn moving obstacles (RigidBody2D that move back and forth)
	print("[SERVER] Creating moving obstacles...")
	world.spawn_moving_obstacle(Vector2(-300, 0), Vector2(300, 0), 75.0)  # Horizontal
	world.spawn_moving_obstacle(Vector2(0, -300), Vector2(0, 300), 60.0)  # Vertical
	world.spawn_moving_obstacle(Vector2(-200, -200), Vector2(200, 200), 50.0)  # Diagonal
	world.spawn_moving_obstacle(Vector2(150, -100), Vector2(-150, 100), 80.0)  # Another diagonal
	print("[SERVER] Moving obstacles created")

func _start_server():
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CLIENTS)

	if error != OK:
		print("Failed to start server: ", error)
		return

	# Enable compression to reduce bandwidth by 60-90%
	peer.get_host().compress(ENetConnection.COMPRESS_FASTLZ)

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	print("Server started on port ", PORT)
	print("Tick rate: ", NetworkConfig.TICK_RATE, " Hz")
	print("Snapshot rate: ", NetworkConfig.SNAPSHOT_RATE, " Hz")
	print("ENet compression: FASTLZ enabled")

func _on_peer_connected(peer_id: int):
	print("Peer connected: ", peer_id)

	# Spawn player entity at random position
	var spawn_pos = Vector2(
		randf_range(-100, 100),
		randf_range(-100, 100)
	)
	var entity_id = world.spawn_entity(spawn_pos, peer_id)
	connected_peers[peer_id] = entity_id

	# Send initial snapshot
	_send_snapshot_to_peer(peer_id)

func _on_peer_disconnected(peer_id: int):
	print("Peer disconnected: ", peer_id)

	# Remove player entity
	if connected_peers.has(peer_id):
		world.remove_entity(connected_peers[peer_id])
		connected_peers.erase(peer_id)

## Override world's _send_snapshots to actually send over network
func _physics_process(delta: float):
	# Update bandwidth tracking
	bandwidth_timer += delta
	if bandwidth_timer >= 1.0:
		bytes_sent_per_second = bytes_sent_this_second
		snapshots_sent_per_second = snapshots_sent_this_second
		bytes_sent_this_second = 0
		snapshots_sent_this_second = 0
		bandwidth_timer = 0.0

	# Send snapshots to all connected peers
	if world.current_tick % (NetworkConfig.TICK_RATE / NetworkConfig.SNAPSHOT_RATE) == 0:
		for peer_id in connected_peers.keys():
			_send_snapshot_to_peer(peer_id)

func _send_snapshot_to_peer(peer_id: int):
	var snapshot = world.create_snapshot_for_peer(peer_id)

	# Get baseline for delta compression (ACK-BASED)
	var baseline = world.get_acked_snapshot(peer_id)

	# Serialize with compression
	var data = snapshot.serialize(baseline)

	# Track bandwidth
	bytes_sent_this_second += data.size()
	snapshots_sent_this_second += 1

	# Send to client (call the receive function on client)
	receive_snapshot_data.rpc_id(peer_id, data)

	# Store for future reference (so we can use it as baseline when acked)
	world.store_snapshot(peer_id, snapshot)

	# Debug info (only occasionally)
	if snapshot.sequence % 100 == 0:
		var uncompressed_size = snapshot.entities.size() * 50  # Rough estimate
		print("Snapshot #", snapshot.sequence, " to peer ", peer_id,
			  ": ", snapshot.entities.size(), " entities, ",
			  data.size(), " bytes (uncompressed: ~", uncompressed_size, " bytes)")

@rpc("authority", "call_remote", "unreliable")
func receive_snapshot_data(data: PackedByteArray):
	# This is defined on client - this is just a stub for RPC registration
	pass

## Receive player input from client
@rpc("any_peer", "call_remote", "unreliable")
func receive_player_input(input_dir: Vector2, last_seq: int = -1):
	var peer_id = multiplayer.get_remote_sender_id()
	world.handle_player_input(peer_id, input_dir, last_seq)

## Get bandwidth stats for UI
func get_bandwidth_stats() -> Dictionary:
	var avg_snapshot_size = 0.0
	if snapshots_sent_per_second > 0:
		avg_snapshot_size = float(bytes_sent_per_second) / float(snapshots_sent_per_second)

	return {
		"bytes_per_second": bytes_sent_per_second,
		"kilobytes_per_second": bytes_sent_per_second / 1024.0,
		"snapshots_per_second": snapshots_sent_per_second,
		"avg_snapshot_size": avg_snapshot_size,
		"connected_peers": connected_peers.size(),
		"total_entities": world.entities.size()
	}
