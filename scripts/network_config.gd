extends Node

## Network Configuration Constants (Autoload)
## Based on GafferOnGames snapshot interpolation/compression articles

# Network timing
const TICK_RATE = 30  # Server simulation ticks per second (33ms)
const SNAPSHOT_RATE = 30  # Snapshots sent per second (Send every tick for smoothness)
const TICK_DELTA = 1.0 / TICK_RATE  # ~0.033 seconds per tick

# Interpolation settings
# With 30Hz snapshots (33ms interval), we need at least 66ms buffer to survive 1 lost packet
const INTERPOLATION_DELAY = 0.100  # 100ms buffer (3 frames)
const JITTER_BUFFER = 0.050  # 50ms extra for jitter/lag spikes
const TOTAL_CLIENT_DELAY = INTERPOLATION_DELAY + JITTER_BUFFER  # 150ms total delay

# Gameplay constants
const SPEED = 150.0  # Player speed in units/second
const LINEAR_DAMP = 0.0  # No damping for immediate response

# Spatial partitioning (for 10k players)
const CHUNK_SIZE = 64  # World units per chunk (e.g., 64 tiles)
const INTEREST_RADIUS = 2  # How many chunks around player to send updates

# Compression settings
const POSITION_BITS = 18  # ~2mm precision for 512 unit range
const VELOCITY_BITS = 11  # Velocity quantization bits
const MAX_VELOCITY = 256.0  # Max velocity in units/second (must cover max player speed 100.0)

# World bounds (adjust for your game)
const WORLD_MIN = Vector2(-1024, -1024)
const WORLD_MAX = Vector2(1024, 1024)

# Network limits
const MAX_PACKET_SIZE = 1400  # Stay under MTU
const MAX_ENTITIES_PER_SNAPSHOT = 100  # Limit per packet
const CLOCK_SYNC_INTERVAL = 1.0  # Sync clock every 1 second

## Quantization helpers
static func quantize_position(pos: Vector2) -> Vector2i:
	# Map world position to quantized integer
	var normalized = (pos - WORLD_MIN) / (WORLD_MAX - WORLD_MIN)
	var max_val = (1 << POSITION_BITS) - 1
	return Vector2i(
		clampi(int(normalized.x * max_val), 0, max_val),
		clampi(int(normalized.y * max_val), 0, max_val)
	)


static func dequantize_position(quantized: Vector2i) -> Vector2:
	# Convert quantized integer back to world position
	var max_val = float((1 << POSITION_BITS) - 1)
	var normalized = Vector2(quantized.x / max_val, quantized.y / max_val)
	return WORLD_MIN + normalized * (WORLD_MAX - WORLD_MIN)


static func quantize_velocity(vel: Vector2) -> Vector2i:
	# Quantize velocity to -MAX_VELOCITY to +MAX_VELOCITY range
	var normalized = (vel / MAX_VELOCITY + Vector2.ONE) * 0.5  # Map to 0-1
	var max_val = (1 << VELOCITY_BITS) - 1
	return Vector2i(
		clampi(int(normalized.x * max_val), 0, max_val),
		clampi(int(normalized.y * max_val), 0, max_val)
	)


static func dequantize_velocity(quantized: Vector2i) -> Vector2:
	# Convert quantized velocity back
	var max_val = float((1 << VELOCITY_BITS) - 1)
	var normalized = Vector2(quantized.x / max_val, quantized.y / max_val)
	return (normalized * 2.0 - Vector2.ONE) * MAX_VELOCITY


static func world_to_chunk(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / CHUNK_SIZE)), int(floor(world_pos.y / CHUNK_SIZE)))


static func chunk_to_world(chunk_pos: Vector2i) -> Vector2:
	return Vector2(chunk_pos) * CHUNK_SIZE
