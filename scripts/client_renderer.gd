extends Node2D
class_name ClientRenderer

## Simple renderer for interpolated entities
## Demonstrates the client-side rendering with lightweight client prediction

@export var game_client: GameClient

# Simple sprite pool
var entity_sprites: Dictionary = {}  # entity_id -> Sprite2D

# Camera
@onready var camera = Camera2D.new()

# CLIENT PREDICTION (Hybrid approach - lightweight, no full reconciliation)
const PLAYER_SPEED = 100.0  # units per second (matches server_world.gd)
const PREDICTION_BLEND_FACTOR = 0.3  # 30% correction per frame toward server
var predicted_player_position: Vector2 = Vector2.ZERO
var prediction_enabled: bool = false  # Enabled once we receive first snapshot

func _ready():
	set_process(true)
	add_child(camera)
	camera.enabled = true
	camera.zoom = Vector2(2, 2)  # Zoom in a bit

	# Draw walls for debugging (client-side visualization only, no collision)
	_draw_debug_walls()
	_draw_debug_obstacle_paths()

var debug_counter: int = 0

func _process(delta: float):
	if not game_client or not game_client.connected:
		return

	var entities = game_client.get_entities()

	# CLIENT PREDICTION: Initialize prediction on first snapshot
	if not prediction_enabled and game_client.my_entity_id != -1 and entities.has(game_client.my_entity_id):
		prediction_enabled = true
		predicted_player_position = entities[game_client.my_entity_id].current_position
		print("[RENDERER] Client prediction ENABLED for player entity ", game_client.my_entity_id)

	# CLIENT PREDICTION: Update predicted player position immediately based on input
	if prediction_enabled and game_client.my_entity_id != -1:
		# Predict movement immediately (no delay!)
		var input_direction = game_client.input_direction
		predicted_player_position += input_direction * PLAYER_SPEED * delta

		# Blend toward server position (soft reconciliation)
		if entities.has(game_client.my_entity_id):
			var entity = entities[game_client.my_entity_id]
			var server_position = entity.current_position
			
			# Extrapolate server position to present time to avoid drag/lag sensation
			# We compare our predicted pos (T=0) vs Server pos (T=-150ms) projected to T=0
			var latency = NetworkConfig.TOTAL_CLIENT_DELAY
			var target_position = server_position + (entity.current_velocity * latency)
			
			var error = target_position - predicted_player_position
			
			# Lower blend factor to trust client more, only correcting drift slowly
			# 0.05 @ 60FPS = ~95% correction over 1 second
			predicted_player_position += error * 0.05

	# Update/create sprites for entities
	for entity_id in entities:
		var entity: ClientInterpolator.InterpolatedEntity = entities[entity_id]

		if not entity_sprites.has(entity_id):
			_create_entity_sprite(entity_id)
			if entity_id == game_client.my_entity_id:
				print("[RENDERER] Created sprite for PLAYER entity ", entity_id)

		var sprite: Sprite2D = entity_sprites[entity_id]

		# CLIENT PREDICTION: Use predicted position for local player
		if entity_id == game_client.my_entity_id and prediction_enabled:
			sprite.position = predicted_player_position

			# Predict rotation based on input (immediate response)
			var input_dir = game_client.input_direction
			if input_dir.length() > 0.01:
				sprite.rotation = input_dir.angle()
		else:
			# Other entities use interpolated position
			sprite.position = entity.current_position

		# Update sprite appearance based on state
		# Pass is_local_player=true to prevent overriding our predicted rotation
		_update_sprite_appearance(sprite, entity, entity_id == game_client.my_entity_id)

	# Remove sprites for entities that no longer exist
	for entity_id in entity_sprites.keys():
		if not entities.has(entity_id):
			if entity_id == game_client.my_entity_id:
				print("[RENDERER] WARNING: Removing sprite for PLAYER entity ", entity_id, "!")
			entity_sprites[entity_id].queue_free()
			entity_sprites.erase(entity_id)

	# CRITICAL FIX: Follow player using predicted position if available
	if game_client.my_entity_id != -1:
		if prediction_enabled:
			# Follow predicted position (immediate response!)
			camera.position = predicted_player_position
		elif entities.has(game_client.my_entity_id):
			# Fallback to interpolated position
			camera.position = entities[game_client.my_entity_id].current_position
		else:
			debug_counter += 1
			if debug_counter % 60 == 0:  # Log once per second at 60 FPS
				print("[RENDERER] WARNING: Player entity ", game_client.my_entity_id,
					  " not in interpolated entities! Available: ", entities.keys())

func _create_entity_sprite(entity_id: int) -> Sprite2D:
	var sprite = Sprite2D.new()
	add_child(sprite)

	# Create a simple colored square
	var size = 16
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(randf(), randf(), randf()))  # Random color

	# Add border
	for i in range(size):
		image.set_pixel(i, 0, Color.BLACK)
		image.set_pixel(i, size-1, Color.BLACK)
		image.set_pixel(0, i, Color.BLACK)
		image.set_pixel(size-1, i, Color.BLACK)

	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture

	entity_sprites[entity_id] = sprite
	return sprite

func _update_sprite_appearance(sprite: Sprite2D, entity: ClientInterpolator.InterpolatedEntity, is_local_player: bool = false):
	# Rotate sprite based on movement direction (unless local player controlled by prediction)
	if not is_local_player and entity.current_velocity.length() > 0.1:
		sprite.rotation = entity.current_velocity.angle()

	# Could update sprite frame, modulation, etc. based on entity.state_flags

## Debug: Draw walls on client for visualization (matches server walls)
func _draw_debug_walls():
	var wall_thickness = 32.0
	var wall_color = Color(0, 0, 0, 0.85)  # Semi-transparent black

	# Helper to create a visual wall
	var create_visual_wall = func(pos: Vector2, size: Vector2):
		var wall_visual = ColorRect.new()
		wall_visual.position = pos - size / 2  # ColorRect uses top-left positioning
		wall_visual.size = size
		wall_visual.color = wall_color
		add_child(wall_visual)

	var world_width = NetworkConfig.WORLD_MAX.x - NetworkConfig.WORLD_MIN.x
	var world_height = NetworkConfig.WORLD_MAX.y - NetworkConfig.WORLD_MIN.y

	# Top wall
	create_visual_wall.call(
		Vector2(0, NetworkConfig.WORLD_MIN.y - wall_thickness/2),
		Vector2(world_width, wall_thickness)
	)

	# Bottom wall
	create_visual_wall.call(
		Vector2(0, NetworkConfig.WORLD_MAX.y + wall_thickness/2),
		Vector2(world_width, wall_thickness)
	)

	# Left wall
	create_visual_wall.call(
		Vector2(NetworkConfig.WORLD_MIN.x - wall_thickness/2, 0),
		Vector2(wall_thickness, world_height)
	)

	# Right wall
	create_visual_wall.call(
		Vector2(NetworkConfig.WORLD_MAX.x + wall_thickness/2, 0),
		Vector2(wall_thickness, world_height)
	)

	# Interior walls (matching server_world.gd)
	create_visual_wall.call(Vector2(200, 0), Vector2(32, 200))
	create_visual_wall.call(Vector2(-200, 100), Vector2(150, 32))

	print("[RENDERER] Debug walls drawn")

## Debug: Draw obstacle movement paths
func _draw_debug_obstacle_paths():
	var path_color = Color(1.0, 0.5, 0.0, 0.3)  # Semi-transparent orange

	# Helper to draw a line showing obstacle path
	var draw_path = func(start: Vector2, end: Vector2):
		var line = Line2D.new()
		line.add_point(start)
		line.add_point(end)
		line.width = 4.0
		line.default_color = path_color
		add_child(line)

	# Match the obstacle paths from game_server.gd
	draw_path.call(Vector2(-300, 0), Vector2(300, 0))  # Horizontal
	draw_path.call(Vector2(0, -300), Vector2(0, 300))  # Vertical
	draw_path.call(Vector2(-200, -200), Vector2(200, 200))  # Diagonal
	draw_path.call(Vector2(150, -100), Vector2(-150, 100))  # Another diagonal

	print("[RENDERER] Debug obstacle paths drawn")
