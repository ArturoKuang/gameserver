extends Node2D  # Changed from Node to Node2D for physics support
class_name ServerWorld

## Server-authoritative world manager with spatial partitioning
## Handles up to 10,000 players using interest management

var entities: Dictionary = {}  # entity_id -> Entity
var chunks: Dictionary = {}  # Vector2i (chunk_pos) -> Array[entity_id]
var next_entity_id: int = 1

var tick_accumulator: float = 0.0
var current_tick: int = 0

const PLAYER_LINEAR_DAMP: float = 8.0  # Keeps rigidbody players responsive without sliding

# Per-client snapshot sequences (CRITICAL: each client needs independent sequence numbers)
var snapshot_sequences: Dictionary = {}  # peer_id -> int

# For delta compression (Ack-based)
var snapshot_history: Dictionary = {}  # peer_id -> Dictionary[sequence -> EntitySnapshot]
var peer_acks: Dictionary = {}  # peer_id -> int (last acknowledged sequence)
var peer_last_input_tick: Dictionary = {} # peer_id -> int (last processed input tick)
const HISTORY_SIZE = 60  # Keep ~3 seconds of snapshots (at 20Hz)

# Lag Compensation History
var world_history: Dictionary = {} # tick -> Dictionary[entity_id, Dictionary]
const LAG_COMP_HISTORY_TICKS = 40 # 2 seconds at 20Hz

# For entity interest management hysteresis
var active_peer_entities: Dictionary = {}  # peer_id -> Dictionary[entity_id -> bool]
const HYSTERESIS_BONUS = 10000.0  # Distance bonus squared (100 units)

# Physics containers
var physics_container: Node2D
var walls_container: Node2D
var moving_obstacles_container: Node2D

class Entity:
	var id: int
	var type: int = 0  # 0=Player/NPC, 2=Obstacle
	var physics_body: PhysicsBody2D  # NEW: Actual Godot physics body (can be CharacterBody2D, RigidBody2D, etc)
	var sprite_frame: int = 0
	var state_flags: int = 0
	var chunk: Vector2i
	var peer_id: int = -1  # If this is a player, their network peer ID

	# Cached properties for faster access
	var position: Vector2:
		get:
			return physics_body.position if physics_body else Vector2.ZERO
	var velocity: Vector2:
		get:
			if physics_body is CharacterBody2D:
				return physics_body.velocity
			elif physics_body is RigidBody2D:
				return physics_body.linear_velocity
			else:
				return Vector2.ZERO

	func _init(entity_id: int, body: PhysicsBody2D):
		id = entity_id
		physics_body = body
		chunk = NetworkConfig.world_to_chunk(body.position)

func _ready():
	set_physics_process(true)

	# Create physics containers
	physics_container = Node2D.new()
	physics_container.name = "PhysicsContainer"
	add_child(physics_container)

	walls_container = Node2D.new()
	walls_container.name = "Walls"
	physics_container.add_child(walls_container)

	moving_obstacles_container = Node2D.new()
	moving_obstacles_container.name = "MovingObstacles"
	physics_container.add_child(moving_obstacles_container)

	# Create static walls (box around the world)
	_create_walls()

func _physics_process(delta: float):
	tick_accumulator += delta

	# Run server ticks at fixed rate
	while tick_accumulator >= NetworkConfig.TICK_DELTA:
		tick_accumulator -= NetworkConfig.TICK_DELTA
		_tick()
		current_tick += 1

func _tick():
	# Update all entities
	for entity_id in entities:
		var entity: Entity = entities[entity_id]
		_update_entity(entity)

	# Update moving obstacles
	_update_moving_obstacles()
	
	# Store state for lag compensation
	_store_world_state()

	# Send snapshots every N ticks
	if current_tick % (NetworkConfig.TICK_RATE / NetworkConfig.SNAPSHOT_RATE) == 0:
		_send_snapshots()

func _update_entity(entity: Entity):
	var body = entity.physics_body

	# Let Godot handle physics for CharacterBody2D
	if body is CharacterBody2D:
		# Move with collision detection
		body.move_and_slide()

		# Apply friction (Stardew Valley style - gradual stop)
		body.velocity *= 0.85

	# For RigidBody2D, physics is handled automatically by the engine
	elif body is RigidBody2D:
		# Keep player rigidbodies damped so they stop quickly after input
		if (body.collision_layer & 0b0001) != 0:
			body.linear_damp = PLAYER_LINEAR_DAMP

	# Update chunk if position changed
	var new_chunk = NetworkConfig.world_to_chunk(body.position)
	if new_chunk != entity.chunk:
		_move_entity_chunk(entity, new_chunk)

	# Update animation based on velocity
	var vel_length = entity.velocity.length()
	if vel_length > 0.1:
		entity.sprite_frame = (entity.sprite_frame + 1) % 4  # Simple walk cycle
	else:
		entity.sprite_frame = 0

func _move_entity_chunk(entity: Entity, new_chunk: Vector2i):
	var old_chunk = entity.chunk

	# Remove from old chunk
	if chunks.has(entity.chunk):
		chunks[entity.chunk].erase(entity.id)
		if chunks[entity.chunk].is_empty():
			chunks.erase(entity.chunk)

	# Add to new chunk
	if not chunks.has(new_chunk):
		chunks[new_chunk] = []
	chunks[new_chunk].append(entity.id)

	entity.chunk = new_chunk

	# Debug logging for player entities changing chunks
	if entity.peer_id != -1:
		GameLogger.log_chunk_change(entity.id, old_chunk, new_chunk, entity.position)

func spawn_entity(position: Vector2, peer_id: int = -1) -> int:
	var entity_id = next_entity_id
	next_entity_id += 1

	# Create RigidBody2D for player/NPC entities so they collide with each other
	var body = RigidBody2D.new()
	body.position = position
	body.name = "Entity_" + str(entity_id)
	body.gravity_scale = 0.0  # Top-down, no gravity
	body.lock_rotation = true  # Keep sprites upright
	body.linear_damp = PLAYER_LINEAR_DAMP

	# Add collision shape (box to match the sprite)
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	# Match the 16x16 visual sprite so the hitbox aligns with the box art
	shape.size = Vector2(16.0, 16.0)
	collision.shape = shape
	body.add_child(collision)

	# Physics layers:
	# Layer 1 (bit 0) = Entities (players, NPCs)
	# Layer 2 (bit 1) = Walls
	# Layer 3 (bit 2) = Moving obstacles
	body.collision_layer = 0b0001  # This entity is on layer 1
	body.collision_mask = 0b0111   # Collides with players, walls, and moving obstacles

	# Add to scene tree (required for physics to work)
	physics_container.add_child(body)

	var entity = Entity.new(entity_id, body)
	entity.type = 0 # Player/NPC
	entity.peer_id = peer_id
	entities[entity_id] = entity

	# Add to chunk
	if not chunks.has(entity.chunk):
		chunks[entity.chunk] = []
	chunks[entity.chunk].append(entity_id)

	GameLogger.info("SERVER", "Entity spawned", {
		"entity_id": entity_id,
		"pos": "(%d,%d)" % [int(position.x), int(position.y)],
		"peer_id": peer_id if peer_id != -1 else "NPC"
	})

	return entity_id

func remove_entity(entity_id: int):
	if not entities.has(entity_id):
		return

	var entity: Entity = entities[entity_id]

	# Clean up peer-specific data if this was a player entity
	if entity.peer_id != -1:
		cleanup_peer(entity.peer_id)

	# Remove physics body from scene tree
	if entity.physics_body:
		entity.physics_body.queue_free()

	# Remove from chunk
	if chunks.has(entity.chunk):
		chunks[entity.chunk].erase(entity_id)
		if chunks[entity.chunk].is_empty():
			chunks.erase(entity.chunk)

	entities.erase(entity_id)

## Cleanup peer-specific data when a client disconnects
func cleanup_peer(peer_id: int):
	snapshot_sequences.erase(peer_id)
	snapshot_history.erase(peer_id)
	peer_acks.erase(peer_id)
	active_peer_entities.erase(peer_id)

## Process acknowledgement from client
func acknowledge_snapshot(peer_id: int, ack: int):
	if ack <= 0:
		return

	# Only update if newer (handle out-of-order packets)
	var current_ack = peer_acks.get(peer_id, 0)
	if ack > current_ack:
		peer_acks[peer_id] = ack
		# print("[SERVER] Peer ", peer_id, " acked snapshot #", ack)

func get_baseline_for_peer(peer_id: int) -> EntitySnapshot:
	var ack = peer_acks.get(peer_id, 0)
	if ack == 0:
		return null
	
	if snapshot_history.has(peer_id):
		var history = snapshot_history[peer_id]
		if history.has(ack):
			return history[ack]
			
	return null

func store_snapshot_for_peer(peer_id: int, snapshot: EntitySnapshot):
	if not snapshot_history.has(peer_id):
		snapshot_history[peer_id] = {}
	
	snapshot_history[peer_id][snapshot.sequence] = snapshot
	
	# Prune history (keep last N snapshots)
	var history = snapshot_history[peer_id]
	if history.size() > HISTORY_SIZE:
		var oldest_allowed = snapshot.sequence - HISTORY_SIZE
		var keys_to_remove = []
		for seq in history:
			if seq < oldest_allowed:
				keys_to_remove.append(seq)
		for seq in keys_to_remove:
			history.erase(seq)

func set_entity_velocity(entity_id: int, vel: Vector2):
	if entities.has(entity_id):
		var entity: Entity = entities[entity_id]
		if entity.physics_body is CharacterBody2D:
			entity.physics_body.velocity = vel
		elif entity.physics_body is RigidBody2D:
			entity.physics_body.linear_velocity = vel

## Get entities in interest area around a position
func get_entities_in_area(center: Vector2) -> Array[int]:
	var center_chunk = NetworkConfig.world_to_chunk(center)
	var result: Array[int] = []

	# Get entities from surrounding chunks
	for x in range(-NetworkConfig.INTEREST_RADIUS, NetworkConfig.INTEREST_RADIUS + 1):
		for y in range(-NetworkConfig.INTEREST_RADIUS, NetworkConfig.INTEREST_RADIUS + 1):
			var chunk_pos = center_chunk + Vector2i(x, y)
			if chunks.has(chunk_pos):
				result.append_array(chunks[chunk_pos])

	return result

## Create snapshot for a specific peer (with interest management)
func create_snapshot_for_peer(peer_id: int) -> EntitySnapshot:
	# Initialize sequence for new peer
	if not snapshot_sequences.has(peer_id):
		snapshot_sequences[peer_id] = 0

	# Increment THIS peer's sequence number only
	snapshot_sequences[peer_id] += 1
	var sequence = snapshot_sequences[peer_id]

	var timestamp = current_tick * NetworkConfig.TICK_DELTA
	var snapshot = EntitySnapshot.new(sequence, timestamp)

	# Find the player entity for this peer
	var player_entity: Entity = null
	for entity_id in entities:
		var entity: Entity = entities[entity_id]
		if entity.peer_id == peer_id:
			player_entity = entity
			break

	if not player_entity:
		print("[SERVER] WARNING: No player entity found for peer ", peer_id)
		return snapshot  # No player found, return empty snapshot

	# CRITICAL FIX: Set player entity ID in snapshot
	snapshot.player_entity_id = player_entity.id

	# Debug logging (every 100 snapshots)
	if sequence % 100 == 0:
		GameLogger.debug("SERVER", "Creating snapshot", {
			"seq": sequence,
			"tick": current_tick,
			"timestamp": "%.3f" % timestamp,
			"player_id": player_entity.id,
			"player_pos": "(%d,%d)" % [int(player_entity.position.x), int(player_entity.position.y)],
			"player_chunk": str(player_entity.chunk)
		})

	# Get entities in interest area
	var interest_entities = get_entities_in_area(player_entity.position)

	# CRITICAL FIX: ALWAYS include player entity first, regardless of interest area
	# Remove player if they're already in the list, then add them at position 0
	var player_was_in_interest = player_entity.id in interest_entities
	if player_was_in_interest:
		interest_entities.erase(player_entity.id)
	# Insert player as the very first entity - they must ALWAYS see themselves!
	interest_entities.insert(0, player_entity.id)

	# Debug: Log when player wasn't naturally in interest area
	if not player_was_in_interest and sequence % 10 == 0:
		print("[SERVER] DEBUG: Player ", player_entity.id, " NOT in natural interest area, manually added. Interest count: ", interest_entities.size())

	# Retrieve active entities for this peer (Hysteresis)
	if not active_peer_entities.has(peer_id):
		active_peer_entities[peer_id] = {}
	var active_set = active_peer_entities[peer_id]

	# Limit to MAX_ENTITIES_PER_SNAPSHOT (but never cut the player)
	if interest_entities.size() > NetworkConfig.MAX_ENTITIES_PER_SNAPSHOT:
		# print("[SERVER] DEBUG: Limiting snapshot, before: ", interest_entities.size())
		
		# Sort by distance with hysteresis (skip index 0 since that's the player)
		var other_entities = interest_entities.slice(1)
		other_entities.sort_custom(func(a, b):
			var dist_a = entities[a].position.distance_squared_to(player_entity.position)
			var dist_b = entities[b].position.distance_squared_to(player_entity.position)
			
			# Apply hysteresis bonus to keep existing entities
			if active_set.has(a): dist_a -= HYSTERESIS_BONUS
			if active_set.has(b): dist_b -= HYSTERESIS_BONUS
			
			return dist_a < dist_b
		)
		# Keep player + closest entities
		interest_entities = [player_entity.id] + other_entities.slice(0, NetworkConfig.MAX_ENTITIES_PER_SNAPSHOT - 1)
		# print("[SERVER] DEBUG: After limiting: ", interest_entities.size())

	# Update active set for next frame
	active_set.clear()
	for eid in interest_entities:
		active_set[eid] = true

	# Debug: Log interest_entities before adding to snapshot (every 10 snapshots)
	if sequence % 10 == 0:
		print("[SERVER] DEBUG: About to add ", interest_entities.size(),
			  " entities to snapshot #", sequence,
			  " | Player at [0]: ", (interest_entities.size() > 0 and interest_entities[0] == player_entity.id),
			  " | Interest list: ", interest_entities)

	# Add entities to snapshot
	for entity_id in interest_entities:
		# Safety check: ensure entity still exists
		if not entities.has(entity_id):
			print("[SERVER] WARNING: Entity ", entity_id, " in interest area but not in entities dict!")
			continue

		var entity: Entity = entities[entity_id]
		var state = snapshot.add_entity(entity_id, entity.position, entity.velocity)
		state.sprite_frame = entity.sprite_frame
		state.state_flags = entity.state_flags
		state.entity_type = entity.type # Pass the type to the snapshot

	# CRITICAL: Verify player was actually added to snapshot
	if not snapshot.has_entity(player_entity.id):
		print("[SERVER] CRITICAL ERROR: Player ", player_entity.id, " missing from snapshot #", snapshot.sequence,
			  "! Interest entities: ", interest_entities,
			  " | Snapshot entities: ", snapshot.entities.keys())
	else:
		# Log successful snapshot creation occasionally
		if sequence % 10 == 0:
			print("[SERVER] DEBUG: Snapshot #", snapshot.sequence,
				  " created with ", snapshot.entities.size(), " entities including player ", player_entity.id,
				  " | All entities: ", snapshot.entities.keys())

	return snapshot

func _send_snapshots():
	# In a real implementation, you'd iterate over connected peers
	# For now, this is a placeholder showing the architecture

	# Example: for each connected peer
	# var peers = get_connected_peers()
	# for peer_id in peers:
	#     var snapshot = create_snapshot_for_peer(peer_id)
	#     var baseline = last_snapshots.get(peer_id)
	#     var data = snapshot.serialize(baseline)
	#     send_to_peer(peer_id, data)
	#     last_snapshots[peer_id] = snapshot
	pass

## Store current world state for lag compensation rewinds
func _store_world_state():
	var state = {}
	for id in entities:
		var e = entities[id]
		if e.physics_body:
			state[id] = e.physics_body.position
	
	world_history[current_tick] = state
	
	# Prune old history
	if world_history.size() > LAG_COMP_HISTORY_TICKS:
		var oldest_tick = current_tick - LAG_COMP_HISTORY_TICKS
		if world_history.has(oldest_tick):
			world_history.erase(oldest_tick)

## Perform a lag-compensated raycast
## Returns the entity ID hit, or -1 if none
func verify_hit(origin: Vector2, direction: Vector2, timestamp: float) -> int:
	# 1. Convert timestamp to tick
	var estimated_tick = timestamp / NetworkConfig.TICK_DELTA
	
	# Find two closest ticks in history
	var tick_floor = floori(estimated_tick)
	var tick_ceil = tick_floor + 1
	var t = estimated_tick - tick_floor
	
	if not world_history.has(tick_floor):
		if abs(estimated_tick - current_tick) < 2.0:
			return _raycast(origin, direction)
		# print("[SERVER] LagComp: History missing for tick ", tick_floor)
		return -1
		
	var state_floor = world_history[tick_floor]
	var state_ceil = world_history.get(tick_ceil, state_floor)
	
	# Manual Hit Check (Circle/AABB) against rewound positions
	var hit_id = -1
	var closest_dist = 999999.0
	
	for id in state_floor:
		if entities.has(id):
			# Get rewound position
			var pos_a = state_floor[id]
			var pos_b = state_ceil.get(id, pos_a)
			var interp_pos = pos_a.lerp(pos_b, t)
			
			# Check intersection (Radius 16)
			var radius = 16.0
			var L = interp_pos - origin
			var tca = L.dot(direction)
			if tca < 0: continue # Behind origin
			
			var d2 = L.length_squared() - tca * tca
			if d2 > radius * radius: continue # Miss
			
			var thc = sqrt(radius * radius - d2)
			var t0 = tca - thc
			
			if t0 < closest_dist:
				closest_dist = t0
				hit_id = id
				
	return hit_id

func _raycast(origin: Vector2, direction: Vector2) -> int:
	# Placeholder for standard raycast
	return -1

## Create static walls around the world
func _create_walls():
	print("[SERVER] Creating world walls...")

	# Wall thickness and world bounds
	var wall_thickness = 32.0
	var world_width = NetworkConfig.WORLD_MAX.x - NetworkConfig.WORLD_MIN.x
	var world_height = NetworkConfig.WORLD_MAX.y - NetworkConfig.WORLD_MIN.y

	# Top wall
	_create_wall(
		Vector2(0, NetworkConfig.WORLD_MIN.y - wall_thickness/2),
		Vector2(world_width, wall_thickness)
	)

	# Bottom wall
	_create_wall(
		Vector2(0, NetworkConfig.WORLD_MAX.y + wall_thickness/2),
		Vector2(world_width, wall_thickness)
	)

	# Left wall
	_create_wall(
		Vector2(NetworkConfig.WORLD_MIN.x - wall_thickness/2, 0),
		Vector2(wall_thickness, world_height)
	)

	# Right wall
	_create_wall(
		Vector2(NetworkConfig.WORLD_MAX.x + wall_thickness/2, 0),
		Vector2(wall_thickness, world_height)
	)

	# Add some interior walls for testing collision
	_create_wall(Vector2(200, 0), Vector2(32, 200))
	_create_wall(Vector2(-200, 100), Vector2(150, 32))

	print("[SERVER] Walls created successfully")

## Helper to create a single wall
func _create_wall(pos: Vector2, size: Vector2):
	var wall = StaticBody2D.new()
	wall.position = pos

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)

	# Layer 2 (bit 1) = Walls
	wall.collision_layer = 0b0010
	wall.collision_mask = 0b0001  # Walls interact with entities

	walls_container.add_child(wall)

## Create a moving obstacle (RigidBody2D that moves back and forth)
func spawn_moving_obstacle(start_pos: Vector2, end_pos: Vector2, speed: float = 50.0) -> int:
	var entity_id = next_entity_id
	next_entity_id += 1

	var body = RigidBody2D.new()
	body.position = start_pos
	body.name = "MovingObstacle_" + str(entity_id)
	body.gravity_scale = 0.0  # Top-down game, no gravity
	body.linear_damp = 0.0  # No damping for constant movement
	body.lock_rotation = true  # Don't rotate

	# Add collision shape
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(32, 32)  # 32x32 obstacle
	collision.shape = shape
	body.add_child(collision)

	# Layer 3 (bit 2) = Moving obstacles
	body.collision_layer = 0b0100
	body.collision_mask = 0b0001  # Collides with entities

	moving_obstacles_container.add_child(body)

	# Store movement data in metadata
	body.set_meta("start_pos", start_pos)
	body.set_meta("end_pos", end_pos)
	body.set_meta("speed", speed)
	body.set_meta("moving_to_end", true)

	# Set initial velocity
	var direction = (end_pos - start_pos).normalized()
	body.linear_velocity = direction * speed

	# IMPORTANT: Create Entity wrapper so it appears in snapshots
	var entity = Entity.new(entity_id, body)
	entity.type = 2 # Obstacle
	entity.peer_id = -1  # Not a player
	entities[entity_id] = entity

	# Add to chunk system
	var chunk = NetworkConfig.world_to_chunk(start_pos)
	if not chunks.has(chunk):
		chunks[chunk] = []
	chunks[chunk].append(entity_id)
	entity.chunk = chunk

	print("[SERVER] Created moving obstacle ", entity_id, " from ", start_pos, " to ", end_pos)

	return entity_id

## Update moving obstacles (call this in _physics_process or _tick)
func _update_moving_obstacles():
	for obstacle in moving_obstacles_container.get_children():
		if obstacle is RigidBody2D:
			var start_pos: Vector2 = obstacle.get_meta("start_pos")
			var end_pos: Vector2 = obstacle.get_meta("end_pos")
			var speed: float = obstacle.get_meta("speed")
			var moving_to_end: bool = obstacle.get_meta("moving_to_end")

			# Check if we've reached the target
			var target = end_pos if moving_to_end else start_pos
			var distance = obstacle.position.distance_to(target)

			# If close enough, reverse direction
			if distance < 10.0:
				moving_to_end = !moving_to_end
				obstacle.set_meta("moving_to_end", moving_to_end)
				target = end_pos if moving_to_end else start_pos

			# Update velocity towards target
			var direction = (target - obstacle.position).normalized()
			obstacle.linear_velocity = direction * speed

## Input handling from client
func handle_player_input(peer_id: int, input_dir: Vector2, tick: int = 0, render_time: float = 0.0):
	# Store the tick so we can acknowledge it in the next snapshot
	if tick > peer_last_input_tick.get(peer_id, 0):
		peer_last_input_tick[peer_id] = tick
	# Find player entity
	for entity_id in entities:
		var entity: Entity = entities[entity_id]
		if entity.peer_id == peer_id:
			# Set velocity based on input (Stardew Valley has 8-directional movement)
			var speed = 100.0  # units per second
			if entity.physics_body is CharacterBody2D:
				entity.physics_body.velocity = input_dir.normalized() * speed
			elif entity.physics_body is RigidBody2D:
				var body: RigidBody2D = entity.physics_body
				if input_dir != Vector2.ZERO:
					body.linear_velocity = input_dir.normalized() * speed
				# Keep the body awake so collision responses stay active
				body.sleeping = false

			# Set facing direction in state_flags
			if input_dir.x > 0:
				entity.state_flags = 0  # Right
			elif input_dir.x < 0:
				entity.state_flags = 1  # Left
			elif input_dir.y > 0:
				entity.state_flags = 2  # Down
			elif input_dir.y < 0:
				entity.state_flags = 3  # Up
			break
