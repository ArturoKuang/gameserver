extends Node
class_name TestAutomation

## Automated test behaviors for clients
## Enables headless testing of network interpolation and prediction

enum TestMode {
	DISABLED,
	RANDOM_WALK,       # Random direction changes
	STRESS_TEST,        # Rapid movements and direction changes
	CHUNK_CROSSING,     # Deliberately cross chunk boundaries
	CIRCLE_PATTERN,     # Move in circles
	FIGURE_EIGHT,       # Move in figure-8 pattern
	COLLISION_TEST      # Deliberately collide with walls
}

var current_mode: TestMode = TestMode.DISABLED
var test_enabled: bool = false

# Test parameters
var move_speed: float = 100.0
var test_timer: float = 0.0
var direction_change_interval: float = 2.0  # seconds

# Current test state
var current_direction: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var circle_angle: float = 0.0
var figure8_time: float = 0.0

# For collision testing
var collision_targets: Array[Vector2] = []

# Reference to player entity (set externally)
var player_position: Vector2 = Vector2.ZERO

func _ready():
	set_process(true)
	_load_test_config()

## Load test configuration from environment variables
func _load_test_config():
	var test_mode_str = OS.get_environment("TEST_BEHAVIOR")
	if test_mode_str.is_empty():
		return

	test_enabled = true

	match test_mode_str.to_lower():
		"random_walk":
			current_mode = TestMode.RANDOM_WALK
			direction_change_interval = 3.0
			Logger.info("TEST_AUTO", "Enabled: RANDOM_WALK", {"interval": direction_change_interval})

		"stress_test":
			current_mode = TestMode.STRESS_TEST
			direction_change_interval = 0.5  # Fast direction changes
			Logger.info("TEST_AUTO", "Enabled: STRESS_TEST", {"interval": direction_change_interval})

		"chunk_crossing":
			current_mode = TestMode.CHUNK_CROSSING
			Logger.info("TEST_AUTO", "Enabled: CHUNK_CROSSING", {"chunk_size": NetworkConfig.CHUNK_SIZE})

		"circle_pattern":
			current_mode = TestMode.CIRCLE_PATTERN
			Logger.info("TEST_AUTO", "Enabled: CIRCLE_PATTERN", {})

		"figure_eight":
			current_mode = TestMode.FIGURE_EIGHT
			Logger.info("TEST_AUTO", "Enabled: FIGURE_EIGHT", {})

		"collision_test":
			current_mode = TestMode.COLLISION_TEST
			_setup_collision_targets()
			Logger.info("TEST_AUTO", "Enabled: COLLISION_TEST", {"targets": collision_targets.size()})

		_:
			test_enabled = false
			Logger.warn("TEST_AUTO", "Unknown test mode", {"mode": test_mode_str})

func _process(delta: float):
	if not test_enabled:
		return

	test_timer += delta

	# Update current behavior
	match current_mode:
		TestMode.RANDOM_WALK:
			_update_random_walk(delta)

		TestMode.STRESS_TEST:
			_update_stress_test(delta)

		TestMode.CHUNK_CROSSING:
			_update_chunk_crossing(delta)

		TestMode.CIRCLE_PATTERN:
			_update_circle_pattern(delta)

		TestMode.FIGURE_EIGHT:
			_update_figure_eight(delta)

		TestMode.COLLISION_TEST:
			_update_collision_test(delta)

## Get current input direction for automated testing
func get_input_direction() -> Vector2:
	if not test_enabled:
		return Vector2.ZERO

	return current_direction

## Random walk: change direction randomly
func _update_random_walk(delta: float):
	if test_timer >= direction_change_interval:
		test_timer = 0.0

		# 80% chance to move, 20% chance to stop
		if randf() < 0.8:
			current_direction = Vector2(
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)
			).normalized()

			Logger.debug("TEST_AUTO", "Random walk direction change", {
				"dir": "(%+.2f,%+.2f)" % [current_direction.x, current_direction.y]
			})
		else:
			current_direction = Vector2.ZERO
			Logger.debug("TEST_AUTO", "Random walk stopped", {})

## Stress test: rapid direction changes
func _update_stress_test(delta: float):
	if test_timer >= direction_change_interval:
		test_timer = 0.0

		# Always move, change direction rapidly
		current_direction = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()

		# Occasionally do 180 degree turn (worst case for interpolation)
		if randf() < 0.3:
			current_direction = -current_direction
			Logger.debug("TEST_AUTO", "Stress test 180° turn", {})

## Chunk crossing: deliberately move to cross chunk boundaries
func _update_chunk_crossing(delta: float):
	var current_chunk = NetworkConfig.world_to_chunk(player_position)

	# Calculate center of next chunk
	var target_chunk = current_chunk + Vector2i(
		randi_range(-1, 1),
		randi_range(-1, 1)
	)

	target_position = NetworkConfig.chunk_to_world(target_chunk) + Vector2(
		NetworkConfig.CHUNK_SIZE / 2.0,
		NetworkConfig.CHUNK_SIZE / 2.0
	)

	# Move towards target
	var direction_to_target = (target_position - player_position).normalized()

	# Snap to 8 directions (Stardew Valley style)
	current_direction = _snap_to_8_directions(direction_to_target)

	# Log when crossing chunks
	if test_timer > 1.0:  # Log every second
		test_timer = 0.0
		Logger.debug("TEST_AUTO", "Chunk crossing", {
			"current_chunk": str(current_chunk),
			"target_chunk": str(target_chunk),
			"distance": int(player_position.distance_to(target_position))
		})

## Circle pattern: move in circles
func _update_circle_pattern(delta: float):
	var radius = 150.0
	var speed = 0.5  # radians per second

	circle_angle += speed * delta

	# Calculate target position on circle
	target_position = Vector2(
		cos(circle_angle) * radius,
		sin(circle_angle) * radius
	)

	# Direction towards circle path
	var ideal_velocity = Vector2(-sin(circle_angle), cos(circle_angle)) * move_speed
	current_direction = ideal_velocity.normalized()

## Figure-8 pattern: move in figure-8 (tests complex interpolation)
func _update_figure_eight(delta: float):
	var scale = 200.0
	var speed = 0.3

	figure8_time += speed * delta

	# Lissajous curve (2:1 ratio for figure-8)
	target_position = Vector2(
		sin(figure8_time * 2) * scale,
		sin(figure8_time) * scale
	)

	# Calculate velocity direction
	var velocity = Vector2(
		cos(figure8_time * 2) * 2 * scale * speed,
		cos(figure8_time) * scale * speed
	)

	current_direction = velocity.normalized()

	if test_timer > 2.0:
		test_timer = 0.0
		Logger.debug("TEST_AUTO", "Figure-8 motion", {
			"phase": "%.2f" % figure8_time,
			"pos": "(%d,%d)" % [int(target_position.x), int(target_position.y)]
		})

## Collision test: move towards walls to test collision handling
func _update_collision_test(delta: float):
	if collision_targets.is_empty():
		_setup_collision_targets()

	# Pick a random wall to move towards
	if test_timer > direction_change_interval:
		test_timer = 0.0
		target_position = collision_targets[randi() % collision_targets.size()]

	# Move towards target wall
	current_direction = (target_position - player_position).normalized()

	# Log when close to wall
	var distance = player_position.distance_to(target_position)
	if distance < 50.0 and test_timer == 0.0:
		Logger.debug("TEST_AUTO", "Approaching collision target", {
			"distance": int(distance),
			"target": "(%d,%d)" % [int(target_position.x), int(target_position.y)]
		})

## Setup collision targets (world boundaries)
func _setup_collision_targets():
	collision_targets = [
		NetworkConfig.WORLD_MIN + Vector2(100, 100),       # Top-left corner
		Vector2(NetworkConfig.WORLD_MAX.x - 100, NetworkConfig.WORLD_MIN.y + 100),  # Top-right
		Vector2(NetworkConfig.WORLD_MIN.x + 100, NetworkConfig.WORLD_MAX.y - 100),  # Bottom-left
		NetworkConfig.WORLD_MAX - Vector2(100, 100),        # Bottom-right
		Vector2(0, NetworkConfig.WORLD_MIN.y + 100),        # Top center
		Vector2(0, NetworkConfig.WORLD_MAX.y - 100),        # Bottom center
		Vector2(NetworkConfig.WORLD_MIN.x + 100, 0),        # Left center
		Vector2(NetworkConfig.WORLD_MAX.x - 100, 0),        # Right center
	]

## Snap direction to 8 cardinal directions (Stardew Valley style)
func _snap_to_8_directions(dir: Vector2) -> Vector2:
	if dir.length() < 0.1:
		return Vector2.ZERO

	var angle = atan2(dir.y, dir.x)

	# 8 directions: 0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°
	var snap_angle = round(angle / (PI / 4.0)) * (PI / 4.0)

	return Vector2(cos(snap_angle), sin(snap_angle))

## Manual test control (for debugging)
func set_test_mode(mode: TestMode):
	current_mode = mode
	test_enabled = (mode != TestMode.DISABLED)
	test_timer = 0.0
	Logger.info("TEST_AUTO", "Test mode changed", {"mode": TestMode.keys()[mode]})

## Check if test automation is active
func is_active() -> bool:
	return test_enabled

## Update player position (called by client)
func update_player_position(pos: Vector2):
	player_position = pos
