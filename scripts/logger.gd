extends Node
class_name GameLogger

## Enhanced logging system with timestamps and structured format
## Usage: GameLogger.info("Server", "Player spawned", {"player_id": 1, "position": Vector2(0,0)})

enum Level {
	DEBUG = 0,
	INFO = 1,
	WARN = 2,
	ERROR = 3
}

# Current log level (can be changed at runtime)
static var current_level: Level = Level.DEBUG

# For timestamp synchronization
static var start_time: float = 0.0

static func _static_init():
	start_time = Time.get_ticks_msec() / 1000.0

## Get relative timestamp since logger started
static func get_timestamp() -> String:
	var elapsed = (Time.get_ticks_msec() / 1000.0) - start_time
	return "%.3f" % elapsed

## Format a log message with timestamp and metadata
static func _format_message(level_str: String, category: String, message: String, metadata: Dictionary = {}) -> String:
	var parts = [
		"[" + get_timestamp() + "]",
		"[" + level_str + "]",
		"[" + category + "]",
		message
	]

	# Add metadata if present
	if not metadata.is_empty():
		var meta_str = " | "
		for key in metadata:
			meta_str += str(key) + "=" + str(metadata[key]) + " "
		parts.append(meta_str)

	return " ".join(parts)

## Debug level logging
static func debug(category: String, message: String, metadata: Dictionary = {}):
	if current_level <= Level.DEBUG:
		print(_format_message("DEBUG", category, message, metadata))
		_log_json("DEBUG", category, message, metadata)

## Info level logging
static func info(category: String, message: String, metadata: Dictionary = {}):
	if current_level <= Level.INFO:
		print(_format_message("INFO", category, message, metadata))
		_log_json("INFO", category, message, metadata)

## Warning level logging
static func warn(category: String, message: String, metadata: Dictionary = {}):
	if current_level <= Level.WARN:
		print(_format_message("WARN", category, message, metadata))
		_log_json("WARN", category, message, metadata)

## Error level logging
static func error(category: String, message: String, metadata: Dictionary = {}):
	if current_level <= Level.ERROR:
		print(_format_message("ERROR", category, message, metadata))
		_log_json("ERROR", category, message, metadata)

## Log in structured JSON format for automation tools
static func _log_json(level: String, category: String, message: String, metadata: Dictionary):
	var log_data = {
		"timestamp": get_timestamp(),
		"level": level,
		"category": category,
		"message": message,
		"metadata": metadata
	}
	print("[LOG_JSON]" + JSON.stringify(log_data))

## Set log level from string
static func set_level_from_string(level_str: String):
	match level_str.to_upper():
		"DEBUG":
			current_level = Level.DEBUG
		"INFO":
			current_level = Level.INFO
		"WARN":
			current_level = Level.WARN
		"ERROR":
			current_level = Level.ERROR

## Specialized loggers for networking

static func log_snapshot_sent(peer_id: int, sequence: int, entity_count: int, byte_size: int, compression_ratio: float):
	info("SERVER_SNAPSHOT", "Snapshot sent", {
		"peer_id": peer_id,
		"seq": sequence,
		"entities": entity_count,
		"bytes": byte_size,
		"compression": "%.1f%%" % (compression_ratio * 100)
	})

static func log_snapshot_received(sequence: int, entity_count: int, player_id: int, delay_ms: float):
	info("CLIENT_SNAPSHOT", "Snapshot received", {
		"seq": sequence,
		"entities": entity_count,
		"player_id": player_id,
		"delay_ms": "%.1f" % delay_ms
	})

static func log_entity_disappeared(entity_id: int, last_seen_seq: int, current_seq: int):
	warn("INTERPOLATOR", "Entity disappeared", {
		"entity_id": entity_id,
		"last_seq": last_seen_seq,
		"current_seq": current_seq
	})

static func log_player_input(peer_id: int, input_dir: Vector2, position: Vector2):
	debug("SERVER_INPUT", "Player input", {
		"peer_id": peer_id,
		"input": "(%+.2f,%+.2f)" % [input_dir.x, input_dir.y],
		"pos": "(%d,%d)" % [int(position.x), int(position.y)]
	})

static func log_chunk_change(entity_id: int, old_chunk: Vector2i, new_chunk: Vector2i, position: Vector2):
	info("SERVER_CHUNK", "Entity changed chunk", {
		"entity_id": entity_id,
		"from": str(old_chunk),
		"to": str(new_chunk),
		"pos": "(%d,%d)" % [int(position.x), int(position.y)]
	})

static func log_baseline_mismatch(expected_seq: int, actual_seq: int, snapshot_seq: int):
	warn("CLIENT_DELTA", "Baseline mismatch", {
		"expected": expected_seq,
		"actual": actual_seq,
		"snapshot": snapshot_seq
	})

static func log_interpolation_warning(warning_type: String, render_time: float, latest_time: float, buffer_size: int):
	warn("INTERPOLATOR", warning_type, {
		"render_time": "%.3f" % render_time,
		"latest": "%.3f" % latest_time,
		"buffer": buffer_size
	})

static func log_player_disappearance(entity_id: int, snapshot_seq: int, in_snapshot: bool):
	error("CLIENT_ERROR", "Player entity missing", {
		"entity_id": entity_id,
		"snapshot_seq": snapshot_seq,
		"in_snapshot": in_snapshot
	})

static func log_collision(entity_id: int, collided_with: String, position: Vector2):
	debug("PHYSICS", "Collision detected", {
		"entity_id": entity_id,
		"collided_with": collided_with,
		"pos": "(%d,%d)" % [int(position.x), int(position.y)]
	})

static func log_network_simulation(event_type: String, packet_seq: int, simulated_loss: bool, simulated_lag_ms: int):
	debug("NETWORK_SIM", event_type, {
		"seq": packet_seq,
		"dropped": simulated_loss,
		"lag_ms": simulated_lag_ms
	})
