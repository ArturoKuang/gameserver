extends Node
class_name ClientInterpolator

## Client-side snapshot interpolation buffer
## Implements Hermite spline interpolation from GafferOnGames

var snapshot_buffer: Array[EntitySnapshot] = []
var baseline_snapshot: EntitySnapshot = null

# Interpolated entities
var interpolated_entities: Dictionary = {}  # entity_id -> InterpolatedEntity

# Timing
var render_time: float = 0.0  # Time we're rendering at (server time - delay)
var latest_server_time: float = 0.0

class InterpolatedEntity:
	var entity_id: int
	var current_position: Vector2
	var current_velocity: Vector2
	var sprite_frame: int = 0
	var state_flags: int = 0

	func _init(id: int):
		entity_id = id
		current_position = Vector2.ZERO
		current_velocity = Vector2.ZERO

func _ready():
	set_process(true)

func _process(delta: float):
	# CRITICAL: Never extrapolate beyond latest snapshot (GafferOnGames)
	# If we're catching up to the latest snapshot, slow down render time advancement
	var time_until_latest = latest_server_time - render_time
	var min_buffer_time = NetworkConfig.TOTAL_CLIENT_DELAY

	# Adaptive time advancement - slow down when buffer is getting low
	var time_delta = delta
	if time_until_latest < min_buffer_time:
		# We're running low on snapshots - slow down to 90% speed
		time_delta *= 0.9
		if snapshot_buffer.size() % 60 == 0:  # Log occasionally
			print("[INTERPOLATOR] WARNING: Low buffer! Time until latest: ",
				  time_until_latest * 1000.0, "ms (min: ", min_buffer_time * 1000.0, "ms)")

	# Advance render time (but never past latest snapshot)
	render_time += time_delta

	# NEVER extrapolate - clamp to latest snapshot timestamp
	if not snapshot_buffer.is_empty():
		var max_render_time = snapshot_buffer.back().timestamp
		if render_time > max_render_time:
			render_time = max_render_time

	# Interpolate entities
	_interpolate()

## Receive a snapshot from server
func receive_snapshot(snapshot: EntitySnapshot):
	# Update latest server time
	if snapshot.timestamp > latest_server_time:
		latest_server_time = snapshot.timestamp

	# Keep render_time behind the newest snapshot by the configured delay
	var target_render_time = latest_server_time - NetworkConfig.TOTAL_CLIENT_DELAY
	if render_time > target_render_time:
		render_time = target_render_time

	# Initialize render time on first snapshot
	if snapshot_buffer.is_empty():
		render_time = snapshot.timestamp - NetworkConfig.TOTAL_CLIENT_DELAY
		print("[INTERPOLATOR] First snapshot received! Seq: ", snapshot.sequence,
			  " | Timestamp: ", snapshot.timestamp,
			  " | Setting render_time to: ", render_time,
			  " | Delay: ", NetworkConfig.TOTAL_CLIENT_DELAY)

	# Insert snapshot in order (by sequence number)
	var inserted = false
	for i in range(snapshot_buffer.size()):
		if snapshot_buffer[i].sequence > snapshot.sequence:
			# Discard old snapshot
			print("[INTERPOLATOR] Discarding old snapshot seq ", snapshot.sequence,
				  " (already have newer seq ", snapshot_buffer[i].sequence, ")")
			return
		elif snapshot_buffer[i].sequence == snapshot.sequence:
			# Duplicate, ignore
			print("[INTERPOLATOR] Ignoring duplicate snapshot seq ", snapshot.sequence)
			return

	# Add to buffer
	snapshot_buffer.append(snapshot)
	snapshot_buffer.sort_custom(func(a, b): return a.sequence < b.sequence)

	# Keep buffer size reasonable (keep last 1 second of snapshots)
	while snapshot_buffer.size() > NetworkConfig.SNAPSHOT_RATE * 2:
		var removed = snapshot_buffer.pop_front()
		if snapshot.sequence % 100 == 0:
			print("[INTERPOLATOR] Buffer full, removing old snapshot seq ", removed.sequence)

	# Debug logging
	if snapshot.sequence % 100 == 0:
		print("[INTERPOLATOR] Buffer state: ", snapshot_buffer.size(), " snapshots | ",
			  "Render time: ", render_time,
			  " | Latest server time: ", latest_server_time,
			  " | Delay: ", (latest_server_time - render_time) * 1000.0, " ms")

## Interpolate entities at current render time
func _interpolate():
	if snapshot_buffer.size() < 2:
		return  # Need at least 2 snapshots to interpolate

	# Find snapshots to interpolate between
	var from_snapshot: EntitySnapshot = null
	var to_snapshot: EntitySnapshot = null

	for i in range(snapshot_buffer.size() - 1):
		if snapshot_buffer[i].timestamp <= render_time and snapshot_buffer[i + 1].timestamp >= render_time:
			from_snapshot = snapshot_buffer[i]
			to_snapshot = snapshot_buffer[i + 1]
			break

	if not from_snapshot or not to_snapshot:
		# We're either at the edge of the buffer or behind it
		if snapshot_buffer.back().timestamp <= render_time:
			# We're at or past the latest snapshot - HOLD at last known state
			# NO EXTRAPOLATION per GafferOnGames recommendations
			from_snapshot = snapshot_buffer[-1]
			to_snapshot = snapshot_buffer[-1]
			# When both snapshots are the same, t=0 means we just hold position
			print("[INTERPOLATOR] Holding at latest snapshot seq ", snapshot_buffer[-1].sequence,
				  " | render_time: ", render_time, " | latest: ", snapshot_buffer.back().timestamp)
		else:
			# We're behind - jump to first snapshot
			print("[INTERPOLATOR] WARNING: Behind buffer! Jumping render_time from ",
				  render_time, " to ", snapshot_buffer[0].timestamp)
			render_time = snapshot_buffer[0].timestamp
			return

	# Interpolate
	var t = 0.0
	var time_diff = to_snapshot.timestamp - from_snapshot.timestamp
	if time_diff > 0.0001:  # Avoid division by zero when holding at same snapshot
		t = (render_time - from_snapshot.timestamp) / time_diff
		t = clampf(t, 0.0, 1.0)
	# else: t=0 means we hold at from_snapshot position (no interpolation)

	# Collect all entities from both snapshots
	var all_entity_ids = {}
	for entity_id in from_snapshot.entities.keys():
		all_entity_ids[entity_id] = true
	for entity_id in to_snapshot.entities.keys():
		all_entity_ids[entity_id] = true

	# Interpolate each entity
	for entity_id in all_entity_ids:
		var from_state: EntitySnapshot.EntityState = from_snapshot.get_entity(entity_id)
		var to_state: EntitySnapshot.EntityState = to_snapshot.get_entity(entity_id)

		if not interpolated_entities.has(entity_id):
			interpolated_entities[entity_id] = InterpolatedEntity.new(entity_id)

		var interp_entity: InterpolatedEntity = interpolated_entities[entity_id]

		if from_state and to_state:
			# Both snapshots have this entity - interpolate
			_hermite_interpolate(interp_entity, from_state, to_state, t)
		elif to_state:
			# Entity just appeared - snap to position
			interp_entity.current_position = to_state.position
			interp_entity.current_velocity = to_state.velocity
			interp_entity.sprite_frame = to_state.sprite_frame
			interp_entity.state_flags = to_state.state_flags
		elif from_state:
			# Entity disappeared - keep last known position
			print("[INTERPOLATOR] Entity ", entity_id, " disappeared (in from_snapshot seq ",
				  from_snapshot.sequence, " but not in to_snapshot seq ", to_snapshot.sequence, ")")
			pass  # Could mark for removal

	# Remove entities that no longer exist in recent snapshots
	var recent_entities = {}
	for entity_id in to_snapshot.entities.keys():
		recent_entities[entity_id] = true

	for entity_id in interpolated_entities.keys():
		if not recent_entities.has(entity_id):
			# Entity hasn't been seen recently, remove after delay
			# For now, keep it (in production, add timeout)
			pass

## Hermite spline interpolation (smooth velocity transitions)
func _hermite_interpolate(
	interp_entity: InterpolatedEntity,
	from_state: EntitySnapshot.EntityState,
	to_state: EntitySnapshot.EntityState,
	t: float
):
	# Hermite basis functions
	var t2 = t * t
	var t3 = t2 * t

	var h00 = 2*t3 - 3*t2 + 1  # Basis for from_position
	var h10 = t3 - 2*t2 + t     # Basis for from_velocity
	var h01 = -2*t3 + 3*t2      # Basis for to_position
	var h11 = t3 - t2            # Basis for to_velocity

	# Time delta between snapshots
	var dt = NetworkConfig.TICK_DELTA * (NetworkConfig.TICK_RATE / NetworkConfig.SNAPSHOT_RATE)

	# Hermite interpolation
	interp_entity.current_position = (
		h00 * from_state.position +
		h10 * from_state.velocity * dt +
		h01 * to_state.position +
		h11 * to_state.velocity * dt
	)

	# Linear interpolation for velocity
	interp_entity.current_velocity = from_state.velocity.lerp(to_state.velocity, t)

	# Discrete state (use from_state until halfway, then switch)
	if t < 0.5:
		interp_entity.sprite_frame = from_state.sprite_frame
		interp_entity.state_flags = from_state.state_flags
	else:
		interp_entity.sprite_frame = to_state.sprite_frame
		interp_entity.state_flags = to_state.state_flags

## Get interpolated position for an entity
func get_entity_position(entity_id: int) -> Vector2:
	if interpolated_entities.has(entity_id):
		return interpolated_entities[entity_id].current_position
	return Vector2.ZERO

## Get all interpolated entities
func get_all_entities() -> Dictionary:
	return interpolated_entities

## Reset the interpolator
func reset():
	snapshot_buffer.clear()
	interpolated_entities.clear()
	render_time = 0.0
	latest_server_time = 0.0
