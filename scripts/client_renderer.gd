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

	# Update/create sprites for interpolated entities
	for entity_id in entities:
		var entity: ClientInterpolator.InterpolatedEntity = entities[entity_id]

		if not entity_sprites.has(entity_id):
			_create_entity_sprite(entity_id, entity)

		var sprite: Sprite2D = entity_sprites[entity_id]
		sprite.position = entity.current_position

		# Update sprite appearance based on state
		_update_sprite_appearance(sprite, entity)

	# Handle Local Player (CSP)
	if game_client.local_player and game_client.my_entity_id != -1:
		var player_id = game_client.my_entity_id
		
		if not entity_sprites.has(player_id):
			_create_entity_sprite(player_id) # Default to player type
			print("[RENDERER] Created sprite for LOCAL PLAYER entity ", player_id)
			
		var sprite = entity_sprites[player_id]
		
		# Smooth Visual Interpolation for CSP
		# Calculate fraction of time between the last processed tick and the next one
		var server_time = game_client.interpolator.get_server_time()
		var tick_duration = NetworkConfig.TICK_DELTA
		var current_tick = floor(server_time * NetworkConfig.TICK_RATE)
		var next_tick_time = (current_tick + 1) * tick_duration
		
		# Time accumulated within the current tick
		# (server_time is smoothed, so this gives us a smooth 0.0->1.0 ramp)
		var fraction = (server_time - (current_tick * tick_duration)) / tick_duration
		fraction = clamp(fraction, 0.0, 1.0)
		
		# Interpolate between prev_position (start of tick) and position (end of tick)
		if game_client.local_player.prev_position != Vector2.ZERO:
			sprite.position = game_client.local_player.prev_position.lerp(game_client.local_player.position, fraction)
		else:
			sprite.position = game_client.local_player.position
		
		# Update camera to follow local player
		camera.position = sprite.position
		
		# Simple rotation for local player based on velocity
		if game_client.local_player.velocity.length() > 0.1:
			sprite.rotation = game_client.local_player.velocity.angle()

	# Remove sprites for entities that no longer exist
	for entity_id in entity_sprites.keys():
		# If it's the local player, don't remove it if we have a local_player object
		if entity_id == game_client.my_entity_id and game_client.local_player:
			continue
			
		if not entities.has(entity_id):
			entity_sprites[entity_id].queue_free()
			entity_sprites.erase(entity_id)

	# Fallback camera control (if no local player yet)
	if not game_client.local_player and game_client.my_entity_id != -1:
		if entities.has(game_client.my_entity_id):
			camera.position = entities[game_client.my_entity_id].current_position
		else:
			debug_counter += 1
			if debug_counter % 60 == 0:
				print("[RENDERER] Waiting for player entity ", game_client.my_entity_id)

	# Debug Visualization
	if NetworkConfig.DEBUG_VISUALIZATION:
		_draw_debug_ghosts()

func _create_entity_sprite(entity_id: int, entity: ClientInterpolator.InterpolatedEntity = null) -> Sprite2D:
	var sprite = Sprite2D.new()
	add_child(sprite)

	# Create a simple colored square
	var size = 16
	
	# Check type if entity is provided
	if entity and entity.entity_type == 2: # Obstacle
		size = 32
	
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

func _update_sprite_appearance(sprite: Sprite2D, entity: ClientInterpolator.InterpolatedEntity):
	# Rotate sprite based on movement direction
	if entity.current_velocity.length() > 0.1:
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

# Ghost sprites for debug visualization
var ghost_sprites: Dictionary = {} # id -> Sprite2D

func _draw_debug_ghosts():
	if not game_client or not game_client.connected:
		return
		
	var entities = game_client.get_entities()
	
	# 1. Visualize Remote Entities (Target Server Position)
	for entity_id in entities:
		# Don't draw ghost for local player here (handled separately)
		if entity_id == game_client.my_entity_id:
			continue
			
		var entity = entities[entity_id]
		_update_ghost_sprite(entity_id, entity.target_position, Color(1, 0, 0, 0.5)) # Red ghost = Server Target
		
	# 2. Visualize Local Player (Authoritative Server Position)
	if game_client.local_player:
		var player_id = game_client.my_entity_id
		# Green ghost = Server Authoritative Position for Local Player
		_update_ghost_sprite(player_id, game_client.local_player.last_server_position, Color(0, 1, 0, 0.5))

	# Cleanup old ghosts
	for id in ghost_sprites.keys():
		if id != game_client.my_entity_id and not entities.has(id):
			ghost_sprites[id].queue_free()
			ghost_sprites.erase(id)

func _update_ghost_sprite(id: int, pos: Vector2, color: Color):
	if pos == Vector2.ZERO: return
	
	if not ghost_sprites.has(id):
		var sprite = Sprite2D.new()
		
		# Create a simple ghost texture (hollow square)
		var size = 16
		var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		image.fill(Color(0,0,0,0)) # Transparent center
		
		# Add border
		for i in range(size):
			image.set_pixel(i, 0, Color.WHITE)
			image.set_pixel(i, size-1, Color.WHITE)
			image.set_pixel(0, i, Color.WHITE)
			image.set_pixel(size-1, i, Color.WHITE)
			
		var texture = ImageTexture.create_from_image(image)
		sprite.texture = texture
		sprite.modulate = color
		sprite.z_index = 10 # Draw on top
		add_child(sprite)
		ghost_sprites[id] = sprite
		
	ghost_sprites[id].position = pos