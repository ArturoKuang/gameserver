extends CharacterBody2D
class_name LocalPlayer

## Client-Side Prediction Controller
## Handles local simulation, input storage, and server reconciliation.

# State History for Reconciliation
class PlayerState:
	var tick: int
	var position: Vector2
	var velocity: Vector2
	var timestamp: float

	func _init(t: int, pos: Vector2, vel: Vector2, time: float):
		tick = t
		position = pos
		velocity = vel
		timestamp = time

var input_history: Array[Dictionary] = [] # { tick, direction, timestamp }
var state_history: Array[PlayerState] = []
var last_processed_input_tick: int = 0

# GameClient reference for sending RPCs
var game_client: Node = null

func _ready():
	# Setup collision to match server
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(16.0, 16.0)
	collision.shape = shape
	add_child(collision)
	
	# Collision layers (should match server roughly)
	# Layer 1 (bit 0) = Players
	collision_layer = 0b0001 
	# Mask: Walls (Layer 2), Obstacles (Layer 3)
	collision_mask = 0b0110 

func setup(client_ref: Node, start_pos: Vector2):
	game_client = client_ref
	position = start_pos
	
func process_tick(current_tick: int, input_dir: Vector2):
	# 1. Apply Input
	_apply_movement(input_dir)
	
	# 2. Store Input
	var input_data = {
		"tick": current_tick,
		"direction": input_dir,
		"timestamp": Time.get_ticks_msec() / 1000.0
	}
	input_history.append(input_data)
	
	# 3. Store Predicted State
	var state = PlayerState.new(current_tick, position, velocity, Time.get_ticks_msec() / 1000.0)
	state_history.append(state)
	
	# 4. Prune old history
	_prune_history()

func _apply_movement(input_dir: Vector2):
	if input_dir != Vector2.ZERO:
		velocity = input_dir.normalized() * NetworkConfig.SPEED
	else:
		velocity = Vector2.ZERO # Instant stop (or lerp for sliding)
	
	move_and_slide()

func reconcile(server_pos: Vector2, last_server_tick: int):
	# 1. Find the predicted state for this tick
	var history_state = null
	var history_index = -1
	
	for i in range(state_history.size()):
		if state_history[i].tick == last_server_tick:
			history_state = state_history[i]
			history_index = i
			break
	
	if history_state == null:
		# We don't have history for this tick (maybe it's too old or we just started), snap to server
		position = server_pos
		return

	# 2. Compare
	var error = position.distance_to(server_pos) # Wait, comparing current pos to old server pos is wrong.
	# We must compare the HISTORY state at tick T to the SERVER state at tick T.
	
	var prediction_error = history_state.position.distance_to(server_pos)
	
	if prediction_error > 2.0: # Threshold (2 pixels)
		print("[CSP] Reconciliation triggered! Error: ", prediction_error, " | Server Tick: ", last_server_tick)
		
		# 3. Snap to authoritative state
		position = server_pos
		
		# 4. Replay inputs from last_server_tick + 1 to current
		# We need to find inputs AFTER the reconciled tick
		var inputs_to_replay = []
		for input in input_history:
			if input.tick > last_server_tick:
				inputs_to_replay.append(input)
		
		# Re-simulate
		for input in inputs_to_replay:
			_apply_movement(input.direction)
			
			# Update the history state for this tick with the new corrected result
			# (Optional, but good for debugging or subsequent reconciliations)
			for i in range(state_history.size()):
				if state_history[i].tick == input.tick:
					state_history[i].position = position
					state_history[i].velocity = velocity
					
	# 5. Remove processed inputs
	last_processed_input_tick = last_server_tick
	_prune_history()

func _prune_history():
	# Remove inputs older than last_processed_input_tick
	# But keep a bit of buffer just in case
	var safety_buffer = 0
	
	var keep_inputs: Array[Dictionary] = []
	for input in input_history:
		if input.tick > last_processed_input_tick - safety_buffer:
			keep_inputs.append(input)
	input_history = keep_inputs
	
	var keep_states: Array[PlayerState] = []
	for state in state_history:
		if state.tick > last_processed_input_tick - safety_buffer:
			keep_states.append(state)
	state_history = keep_states
