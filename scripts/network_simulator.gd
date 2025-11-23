extends Node

## Network condition simulator for testing
## Simulates packet loss, lag, and jitter

var enabled: bool = false

# Simulation parameters
var packet_loss_rate: float = 0.0  # 0.0 to 1.0 (0% to 100%)
var lag_ms: int = 0  # Base latency in milliseconds
var jitter_ms: int = 0  # Random jitter range in milliseconds
var bandwidth_limit_kbps: float = 0.0  # 0 = unlimited
var duplicate_rate: float = 0.0 # 0.0 to 1.0

# Bandwidth tracking
var bytes_sent_window: int = 0
var window_start_time: int = 0

# Packet delay queue (for lag simulation)
var delayed_packets: Array[DelayedPacket] = []

class DelayedPacket:
	var data: PackedByteArray
	var deliver_time: float  # When to deliver this packet (in msec)
	var callback: Callable
	var sequence: int

	func _init(p_data: PackedByteArray, p_deliver_time: float, p_callback: Callable, p_seq: int = 0):
		data = p_data
		deliver_time = p_deliver_time
		callback = p_callback
		sequence = p_seq

func _ready():
	set_process(true)
	_load_config()

## Load simulation config from environment variables
func _load_config():
	var packet_loss_str = OS.get_environment("TEST_PACKET_LOSS")
	var lag_str = OS.get_environment("TEST_LAG_MS")
	var jitter_str = OS.get_environment("TEST_JITTER_MS")
	var bw_str = OS.get_environment("TEST_BW_KBPS")
	var dup_str = OS.get_environment("TEST_DUPLICATE_RATE")

	if not packet_loss_str.is_empty():
		packet_loss_rate = float(packet_loss_str)
		enabled = true

	if not lag_str.is_empty():
		lag_ms = int(lag_str)
		enabled = true

	if not jitter_str.is_empty():
		jitter_ms = int(jitter_str)
		enabled = true
	elif lag_ms > 0:
		# Default jitter is 20% of lag if not specified
		jitter_ms = lag_ms / 5
		
	if not bw_str.is_empty():
		bandwidth_limit_kbps = float(bw_str)
		enabled = true
		
	if not dup_str.is_empty():
		duplicate_rate = float(dup_str)
		enabled = true

	if enabled:
		GameLogger.info("NET_SIM", "Network simulation enabled", {
			"loss": "%.1f%%" % (packet_loss_rate * 100),
			"lag": lag_ms,
			"jitter": jitter_ms,
			"bw_kbps": bandwidth_limit_kbps,
			"dup": "%.1f%%" % (duplicate_rate * 100)
		})

func _process(delta: float):
	if not enabled:
		return

	var current_time = Time.get_ticks_msec()
	
	# Reset bandwidth window every second
	if current_time - window_start_time >= 1000:
		bytes_sent_window = 0
		window_start_time = current_time

	# Process delayed packets
	var i = 0
	while i < delayed_packets.size():
		var packet = delayed_packets[i]

		if current_time >= packet.deliver_time:
			# Deliver packet
			GameLogger.log_network_simulation(
				"Packet delivered",
				packet.sequence,
				false,
				int(current_time - packet.deliver_time + lag_ms)
			)

			if packet.callback.is_valid():
				packet.callback.call(packet.data)

			delayed_packets.remove_at(i)
		else:
			i += 1

## Simulate receiving a packet (client-side)
## Returns true if packet should be processed, false if dropped
func should_process_packet(sequence: int = 0) -> bool:
	if not enabled:
		return true

	# Packet loss simulation
	if packet_loss_rate > 0.0 and randf() < packet_loss_rate:
		GameLogger.log_network_simulation(
			"Packet dropped (simulated loss)",
			sequence,
			true,
			0
		)
		return false

	return true

## Simulate sending a packet with lag
## Instead of immediately processing, delay it
func send_with_delay(data: PackedByteArray, callback: Callable, sequence: int = 0):
	if not enabled:
		# No delay, deliver immediately
		callback.call(data)
		return
		
	# Bandwidth throttling (drop if over limit)
	if bandwidth_limit_kbps > 0.0:
		bytes_sent_window += data.size()
		var limit_bytes = bandwidth_limit_kbps * 1024
		if bytes_sent_window > limit_bytes:
			GameLogger.log_network_simulation(
				"Packet dropped (bandwidth limit)",
				sequence,
				true,
				0
			)
			return

	# Calculate delivery time with jitter
	var current_time = Time.get_ticks_msec()
	var delay = lag_ms

	if jitter_ms > 0:
		delay += randi_range(-jitter_ms, jitter_ms)
		delay = max(0, delay)  # Never negative

	var deliver_time = current_time + delay

	# Add to queue
	var packet = DelayedPacket.new(data, deliver_time, callback, sequence)
	delayed_packets.append(packet)

	GameLogger.log_network_simulation(
		"Packet delayed",
		sequence,
		false,
		delay
	)
	
	# Duplication
	if duplicate_rate > 0.0 and randf() < duplicate_rate:
		var dup_delay = delay + randi_range(10, 50) # Duplicate arrives slightly later
		var dup_packet = DelayedPacket.new(data, current_time + dup_delay, callback, sequence)
		delayed_packets.append(dup_packet)
		GameLogger.log_network_simulation(
			"Packet duplicated",
			sequence,
			false,
			dup_delay
		)

## Configure simulation parameters at runtime
func set_packet_loss(rate: float):
	packet_loss_rate = clampf(rate, 0.0, 1.0)
	enabled = (packet_loss_rate > 0.0 or lag_ms > 0)
	GameLogger.info("NET_SIM", "Packet loss configured", {
		"rate": "%.1f%%" % (packet_loss_rate * 100),
		"enabled": enabled
	})

func set_lag(lag_milliseconds: int, jitter_milliseconds: int = 0):
	lag_ms = max(0, lag_milliseconds)
	jitter_ms = max(0, jitter_milliseconds)
	enabled = (packet_loss_rate > 0.0 or lag_ms > 0)
	GameLogger.info("NET_SIM", "Lag configured", {
		"lag_ms": lag_ms,
		"jitter_ms": jitter_ms,
		"enabled": enabled
	})

## Reset simulation
func reset():
	delayed_packets.clear()
	GameLogger.info("NET_SIM", "Network simulator reset", {})

## Get statistics
func get_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"packet_loss_rate": packet_loss_rate,
		"lag_ms": lag_ms,
		"jitter_ms": jitter_ms,
		"pending_packets": delayed_packets.size()
	}
