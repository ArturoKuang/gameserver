extends RefCounted
class_name EntitySnapshot

## Represents a snapshot of an entity's state at a specific moment
## Used for both transmission and interpolation

var sequence: int = 0  # Snapshot sequence number
var timestamp: float = 0.0  # Server time when snapshot was taken
var entities: Dictionary = {}  # entity_id -> EntityState
var player_entity_id: int = -1  # ID of the player entity in this snapshot

class EntityState:
	var entity_id: int
	var position: Vector2
	var velocity: Vector2
	var sprite_frame: int = 0  # Animation frame
	var state_flags: int = 0  # Bit flags for various states (facing direction, etc.)

	func _init(id: int, pos: Vector2, vel: Vector2 = Vector2.ZERO):
		entity_id = id
		position = pos
		velocity = vel

	func clone() -> EntityState:
		var state = EntityState.new(entity_id, position, velocity)
		state.sprite_frame = sprite_frame
		state.state_flags = state_flags
		return state

func _init(seq: int = 0, time: float = 0.0):
	sequence = seq
	timestamp = time

func add_entity(entity_id: int, pos: Vector2, vel: Vector2 = Vector2.ZERO) -> EntityState:
	var state = EntityState.new(entity_id, pos, vel)
	entities[entity_id] = state
	return state

func get_entity(entity_id: int) -> EntityState:
	return entities.get(entity_id)

func has_entity(entity_id: int) -> bool:
	return entities.has(entity_id)

## Serialize snapshot to bytes with compression
func serialize(baseline: EntitySnapshot = null) -> PackedByteArray:
	var buffer = PackedByteArray()
	var writer = BitWriter.new(buffer)

	# Write header
	writer.write_bits(sequence, 16)  # Sequence number

	# CRITICAL FIX: Write timestamp as milliseconds (32-bit int)
	var timestamp_ms = int(timestamp * 1000.0)
	writer.write_bits(timestamp_ms, 32)

	# CRITICAL FIX: Write baseline sequence for delta compression validation
	var baseline_seq = baseline.sequence if baseline else 0
	writer.write_bits(baseline_seq, 16)

	writer.write_bits(entities.size(), 16)  # Entity count
	writer.write_bits(player_entity_id if player_entity_id >= 0 else 0, 32)  # Player entity ID

	# Sort entity IDs for delta encoding
	var entity_ids = entities.keys()
	entity_ids.sort()

	# Debug: Log player entity in serialization
	if player_entity_id > 0 and sequence % 10 == 0:
		var player_in_keys = player_entity_id in entity_ids
		print("[SERIALIZE] Snapshot #", sequence, " | Player ID: ", player_entity_id,
			  " | Player in entity_ids: ", player_in_keys,
			  " | Entity count: ", entities.size(),
			  " | All IDs (sorted): ", entity_ids)

	var prev_id = 0
	for entity_id in entity_ids:
		var state: EntityState = entities[entity_id]

		# Delta encode entity ID (write difference from previous ID)
		var id_delta = entity_id - prev_id
		writer.write_variable_uint(id_delta)
		prev_id = entity_id

		# Check if we have a baseline for delta compression
		var baseline_state: EntityState = null
		if baseline and baseline.has_entity(entity_id):
			baseline_state = baseline.get_entity(entity_id)

		if baseline_state:
			# Delta compression: check if entity changed
			var changed = not states_equal(state, baseline_state)
			writer.write_bits(1 if changed else 0, 1)

			# Debug: Log if player entity is being skipped
			if entity_id == player_entity_id and not changed and sequence % 10 == 0:
				print("[SERIALIZE] WARNING: Player ", player_entity_id, " unchanged from baseline in snapshot #", sequence, " - copying from baseline")

			if not changed:
				continue  # Skip unchanged entity

		# Write quantized position
		var qpos = NetworkConfig.quantize_position(state.position)
		writer.write_bits(qpos.x, NetworkConfig.POSITION_BITS)
		writer.write_bits(qpos.y, NetworkConfig.POSITION_BITS)

		# Write quantized velocity
		var qvel = NetworkConfig.quantize_velocity(state.velocity)
		writer.write_bits(qvel.x, NetworkConfig.VELOCITY_BITS)
		writer.write_bits(qvel.y, NetworkConfig.VELOCITY_BITS)

		# Write other state (8 bits for frame, 8 bits for flags)
		writer.write_bits(state.sprite_frame, 8)
		writer.write_bits(state.state_flags, 8)

	writer.flush()
	return buffer

## Peek at the snapshot header to get sequence and baseline_sequence
## Useful for finding the correct baseline before full deserialization
static func peek_header(buffer: PackedByteArray) -> Dictionary:
	var reader = BitReader.new(buffer)
	var sequence = reader.read_bits(16)
	var timestamp_ms = reader.read_bits(32)
	var baseline_seq = reader.read_bits(16)

	return {
		"sequence": sequence,
		"timestamp": float(timestamp_ms) / 1000.0,
		"baseline_seq": baseline_seq
	}

## Deserialize snapshot from bytes
static func deserialize(buffer: PackedByteArray, baseline: EntitySnapshot = null) -> EntitySnapshot:
	var reader = BitReader.new(buffer)

	# Read header
	var sequence = reader.read_bits(16)

	# CRITICAL FIX: Read timestamp
	var timestamp_ms = reader.read_bits(32)
	var timestamp_sec = float(timestamp_ms) / 1000.0

	# CRITICAL FIX: Read baseline sequence and validate
	var baseline_seq = reader.read_bits(16)
	var baseline_valid = false
	if baseline and baseline_seq > 0:
		baseline_valid = (baseline.sequence == baseline_seq)
		if not baseline_valid:
			print("[DESERIALIZE] WARNING: Baseline mismatch! Snapshot #", sequence,
				  " expects baseline #", baseline_seq, " but we have #", baseline.sequence,
				  " (likely out-of-order packet) - ignoring delta compression")
			baseline = null  # Disable delta compression for this packet

	var entity_count = reader.read_bits(16)
	var player_id = reader.read_bits(32)

	var snapshot = EntitySnapshot.new(sequence, timestamp_sec)
	snapshot.player_entity_id = player_id if player_id > 0 else -1

	# Debug: Log deserialization start
	if sequence % 10 == 0:
		print("[DESERIALIZE] Starting snapshot #", sequence,
			  " | Timestamp: ", timestamp_sec,
			  " | Entity count: ", entity_count,
			  " | Player ID: ", snapshot.player_entity_id,
			  " | Has baseline: ", baseline != null,
			  " | Baseline seq: ", baseline_seq)

	var prev_id = 0
	for i in range(entity_count):
		# Read delta-encoded entity ID
		var id_delta = reader.read_variable_uint()
		var entity_id = prev_id + id_delta
		prev_id = entity_id

		# Check if entity changed (if we have baseline)
		# CRITICAL FIX: Only read "changed" bit if entity exists in baseline
		# This must match the serialization logic at line 86-93
		var changed = true
		if baseline and baseline.has_entity(entity_id):
			changed = reader.read_bits(1) == 1
			if not changed:
				# Copy from baseline
				snapshot.entities[entity_id] = baseline.get_entity(entity_id).clone()
				continue

		# Read quantized position
		var qpos_x = reader.read_bits(NetworkConfig.POSITION_BITS)
		var qpos_y = reader.read_bits(NetworkConfig.POSITION_BITS)
		var position = NetworkConfig.dequantize_position(Vector2i(qpos_x, qpos_y))

		# Read quantized velocity
		var qvel_x = reader.read_bits(NetworkConfig.VELOCITY_BITS)
		var qvel_y = reader.read_bits(NetworkConfig.VELOCITY_BITS)
		var velocity = NetworkConfig.dequantize_velocity(Vector2i(qvel_x, qvel_y))

		# Read other state
		var sprite_frame = reader.read_bits(8)
		var state_flags = reader.read_bits(8)

		var state = snapshot.add_entity(entity_id, position, velocity)
		state.sprite_frame = sprite_frame
		state.state_flags = state_flags

	# Debug: Log deserialization result
	if sequence % 10 == 0:
		var player_in_snapshot = snapshot.has_entity(snapshot.player_entity_id)
		print("[DESERIALIZE] Completed snapshot #", sequence,
			  " | Final entity count: ", snapshot.entities.size(),
			  " | Player ", snapshot.player_entity_id, " in snapshot: ", player_in_snapshot,
			  " | All entity IDs: ", snapshot.entities.keys())

	return snapshot

func states_equal(a: EntityState, b: EntityState) -> bool:
	return (a.position.distance_to(b.position) < 0.01 and
			a.velocity.distance_to(b.velocity) < 0.01 and
			a.sprite_frame == b.sprite_frame and
			a.state_flags == b.state_flags)


## Bit-level reader/writer for compression
class BitWriter:
	var buffer: PackedByteArray
	var scratch: int = 0
	var scratch_bits: int = 0

	func _init(buf: PackedByteArray):
		buffer = buf

	func write_bits(value: int, num_bits: int):
		# Mask value to prevent high bits from leaking
		value &= ((1 << num_bits) - 1)

		scratch |= (value << scratch_bits)
		scratch_bits += num_bits

		while scratch_bits >= 8:
			buffer.append(scratch & 0xFF)
			scratch >>= 8
			scratch_bits -= 8

			# CRITICAL: Mask to clear sign-extended bits after arithmetic right shift
			# GDScript uses 64-bit signed integers, so >> may sign-extend
			if scratch_bits > 0:
				scratch &= ((1 << scratch_bits) - 1)

	func write_variable_uint(value: int):
		# Variable-length encoding: small values use fewer bits
		if value < 16:  # 4 bits
			write_bits(0, 2)  # Prefix: 00
			write_bits(value, 4)
		elif value < 128:  # 7 bits
			write_bits(1, 2)  # Prefix: 01
			write_bits(value, 7)
		else:  # 12 bits
			write_bits(2, 2)  # Prefix: 10
			write_bits(value, 12)

	func flush():
		if scratch_bits > 0:
			buffer.append(scratch & 0xFF)
			scratch = 0
			scratch_bits = 0


class BitReader:
	var buffer: PackedByteArray
	var pos: int = 0
	var scratch: int = 0
	var scratch_bits: int = 0

	func _init(buf: PackedByteArray):
		buffer = buf

	func read_bits(num_bits: int) -> int:
		while scratch_bits < num_bits:
			if pos >= buffer.size():
				return 0
			scratch |= (buffer[pos] << scratch_bits)
			scratch_bits += 8
			pos += 1

		var value = scratch & ((1 << num_bits) - 1)
		scratch >>= num_bits
		scratch_bits -= num_bits

		# CRITICAL: Mask to clear sign-extended bits after arithmetic right shift
		if scratch_bits > 0:
			scratch &= ((1 << scratch_bits) - 1)

		return value

	func read_variable_uint() -> int:
		var prefix = read_bits(2)
		if prefix == 0:
			return read_bits(4)
		elif prefix == 1:
			return read_bits(7)
		else:
			return read_bits(12)
