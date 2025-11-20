# Snapshot Interpolation MMO Architecture

A server-authoritative networking architecture for Godot 4.3 capable of handling Stardew Valley-like MMO gameplay with up to 10,000 players. Implements snapshot interpolation and compression techniques from [GafferOnGames](https://gafferongames.com/).

## Features

- **Server-Authoritative Architecture**: All game logic runs on the server, clients only render
- **Snapshot Interpolation**: Hermite spline interpolation for smooth movement
- **Delta Compression**: Only transmit changes from acknowledged baselines
- **Quantization**: Position (18-bit) and velocity (11-bit) compression
- **Spatial Partitioning**: Chunk-based interest management for scalability
- **Simple & Prototype-Friendly**: Easy to understand and modify

## Architecture Overview

### Server Components

#### 1. ServerWorld (`scripts/server_world.gd`)
The authoritative game simulation that runs at **20 Hz** tick rate.

**Key Features:**
- Fixed timestep physics simulation
- Spatial partitioning using chunks (64x64 world units)
- Interest management (players only receive updates for nearby chunks)
- Entity management (spawn, update, remove)
- Handles up to 10,000+ entities efficiently

**Scalability:**
```
Chunk size: 64 units
Interest radius: 2 chunks (5x5 chunk area = 320x320 units visible)
Max entities per snapshot: 100 (prevents packet bloat)
```

#### 2. EntitySnapshot (`scripts/entity_snapshot.gd`)
Snapshot serialization with advanced compression.

**Compression Techniques:**
- **Quantization**: Positions use 18 bits (~2mm precision), velocities use 11 bits
- **Delta Encoding**: Entity IDs are delta-encoded (variable-length)
- **Delta Compression**: Only send changed entities vs baseline
- **Bit Packing**: Custom BitWriter/BitReader for efficient serialization

**Bandwidth Savings:**
```
Uncompressed entity: ~50 bytes
Compressed entity: ~8-12 bytes (with delta compression)
Unchanged entity: 1 bit
```

### Client Components

#### 3. ClientInterpolator (`scripts/client_interpolator.gd`)
Handles snapshot buffering and interpolation.

**Features:**
- **Hermite Spline Interpolation**: Smooth velocity transitions (not just linear)
- **Jitter Buffer**: 150ms delay (100ms interpolation + 50ms jitter)
- **Packet Loss Handling**: Can lose 2 consecutive packets without issues
- **Render Time Tracking**: Maintains consistent interpolation

**How It Works:**
```
Server Time:     [====|====|====|====]
                  t0   t1   t2   t3

Client Render:      [====|====]
                     t0'  t1'  (150ms behind)

Interpolation: Hermite(t0, t1, t)
```

### Network Protocol

#### 4. NetworkConfig (`scripts/network_config.gd`)
Central configuration for all network parameters.

**Key Settings:**
```gdscript
TICK_RATE = 20           # Server simulation Hz
SNAPSHOT_RATE = 10       # Snapshots/second
INTERPOLATION_DELAY = 100ms
CHUNK_SIZE = 64          # Spatial partitioning
INTEREST_RADIUS = 2      # Chunks around player
```

## How to Use

### Running the Test

1. **Start the Server:**
   - Run the project in Godot
   - Click "Start Server"
   - Server starts on port 7777

2. **Start Client(s):**
   - Run another instance of the project
   - Click "Start Client"
   - Use arrow keys to move

3. **Test Multiple Clients:**
   - Run as many client instances as you want
   - Each gets a random spawn position
   - See other players and NPCs interpolating smoothly

### Architecture Example

```
Server (20 Hz simulation, 10 Hz snapshots)
  ├─ ServerWorld
  │   ├─ Entities (players, NPCs, objects)
  │   ├─ Chunks (spatial partitioning)
  │   └─ Physics simulation
  │
  └─ For each connected client:
      ├─ Get entities in interest area
      ├─ Create snapshot with delta compression
      └─ Send unreliable UDP packet

Client (60 FPS rendering)
  ├─ Send input to server (unreliable)
  ├─ Receive snapshots
  ├─ ClientInterpolator
  │   ├─ Buffer snapshots
  │   ├─ Hermite interpolation
  │   └─ Output smooth positions
  └─ Render entities at interpolated positions
```

## Performance Characteristics

### Bandwidth (Per Client)

**Uncompressed:**
- 100 entities × 50 bytes × 10 snapshots/sec = **50 KB/s** (400 Kbps)

**With Compression:**
- ~20% entities change per snapshot (farming game)
- 20 changed × 10 bytes + 80 unchanged × 0.125 bytes = **210 bytes**
- 210 bytes × 10 snapshots/sec = **2.1 KB/s** (17 Kbps)

**Savings: ~95% reduction**

### Server Scalability

For 10,000 players:
```
With interest management (5x5 chunks):
- Each player sees ~100 entities average
- Total bandwidth: 10,000 × 17 Kbps = 170 Mbps
- Manageable with modern server hardware

Without interest management:
- Each player sees all 10,000 entities
- Would require ~4 Gbps - impractical!
```

## Key Implementation Details

### 1. Hermite Spline Interpolation

Instead of basic linear interpolation, we use Hermite splines that consider velocity:

```gdscript
# Hermite basis functions
h00 = 2t³ - 3t² + 1   # from_position weight
h10 = t³ - 2t² + t     # from_velocity weight
h01 = -2t³ + 3t²       # to_position weight
h11 = t³ - t²          # to_velocity weight

position = h00*p0 + h10*v0*dt + h01*p1 + h11*v1*dt
```

This ensures smooth acceleration/deceleration without jitter.

### 2. Variable-Length Entity ID Encoding

```gdscript
Delta < 16:    2 bits (prefix) + 4 bits = 6 bits
Delta < 128:   2 bits (prefix) + 7 bits = 9 bits
Delta >= 128:  2 bits (prefix) + 12 bits = 14 bits

Average: ~5.5 bits per entity ID (vs 32 bits uncompressed)
```

### 3. Spatial Partitioning

```gdscript
# O(1) lookup for entities in area
chunk_pos = world_pos / CHUNK_SIZE
for x in [-2..2]:
    for y in [-2..2]:
        entities += chunks[chunk_pos + (x,y)]
```

## Extending the System

### Adding New Entity Types

```gdscript
# In EntitySnapshot.EntityState
var entity_type: int = 0  # 0=player, 1=NPC, 2=item, etc.
var custom_data: int = 0  # Type-specific data

# Serialize
writer.write_bits(state.entity_type, 3)  # 8 types max
writer.write_bits(state.custom_data, 16)
```

### Adding Player Actions

```gdscript
# Client sends action
@rpc("any_peer", "call_remote", "reliable")
func send_action(action_type: int, target_id: int):
    pass

# Server processes
func handle_action(peer_id: int, action_type: int, target_id: int):
    # Validate and execute
    # Results reflected in next snapshot
```

### Optimizing for Production

1. **Use Real Networking Library**: Replace ENet with dedicated solution (e.g., Nakama, custom UDP)
2. **Add Prediction**: Client-side prediction for local player (reduce perceived latency)
3. **Implement Lag Compensation**: Server-side hit detection rewinding
4. **Add Reliability Layer**: Some events (chat, inventory) need reliable delivery
5. **Load Balancing**: Distribute chunks across multiple server processes

## Technical References

Based on:
- [Snapshot Interpolation](https://gafferongames.com/post/snapshot_interpolation/) - GafferOnGames
- [Snapshot Compression](https://gafferongames.com/post/snapshot_compression/) - GafferOnGames

## Files Overview

```
scripts/
├── network_config.gd         # Network constants and utilities
├── entity_snapshot.gd        # Snapshot serialization/compression
├── server_world.gd           # Server-side simulation
├── client_interpolator.gd    # Client-side interpolation
├── game_server.gd            # Server networking
├── game_client.gd            # Client networking
├── client_renderer.gd        # Visual rendering
└── test_launcher.gd          # Test launcher UI
```

## License

This is a prototype/example implementation. Feel free to use and modify for your projects.
# gameserver
