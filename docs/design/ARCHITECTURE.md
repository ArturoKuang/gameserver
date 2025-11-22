# Snapshot Interpolation - Architecture Overview

## System Design at a Glance

```
┌─────────────────────────────────────────────────────────────────────┐
│                            SERVER (Authoritative)                    │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │ server_world │ -> │entity_snapshot│ -> │ game_server  │          │
│  │   .gd        │    │    .gd       │    │    .gd       │          │
│  │              │    │              │    │              │          │
│  │ • Simulation │    │ • Quantize   │    │ • ENet       │          │
│  │ • Entities   │    │ • Compress   │    │ • Send UDP   │          │
│  │ • Chunks     │    │ • Serialize  │    │              │          │
│  └──────────────┘    └──────────────┘    └──────────────┘          │
│         ↓ 20 Hz              ↓ 10 Hz             ↓ UDP              │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
                          Network (150ms delay)
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│                            CLIENT (Observer)                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │ game_client  │ -> │entity_snapshot│ -> │client_interp │          │
│  │    .gd       │    │    .gd       │    │ olator.gd    │          │
│  │              │    │              │    │              │          │
│  │ • Receive    │    │ • Deserialize│    │ • Buffer     │          │
│  │ • Send input │    │ • Dequantize │    │ • Hermite    │          │
│  │              │    │ • Decompress │    │ • Interpolate│          │
│  └──────────────┘    └──────────────┘    └──────────────┘          │
│                                                   ↓                  │
│                                          ┌──────────────┐           │
│                                          │client_renderer│          │
│                                          │    .gd       │           │
│                                          │              │           │
│                                          │ • Render     │           │
│                                          │ • Sprites    │           │
│                                          └──────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow: From Server Simulation to Client Rendering

### Server Pipeline (Every 50ms / 20 Hz)

```
1. SERVER SIMULATION (server_world.gd)
   ├─ Tick accumulator ensures fixed timestep
   ├─ Process player input from all clients
   ├─ Update entity positions/velocities
   ├─ Update spatial partitioning (chunks)
   └─ Every 2 ticks (100ms):
      └─ Create snapshot for each connected client

2. INTEREST MANAGEMENT (server_world.gd:create_snapshot_for_peer)
   ├─ Get player's chunk position
   ├─ Find all chunks within INTEREST_RADIUS (2 chunks = 5×5 area)
   ├─ Collect entities from those chunks (O(1) lookup!)
   └─ Create EntitySnapshot with filtered entities

3. DELTA COMPRESSION (entity_snapshot.gd:serialize)
   ├─ Get baseline (based on client's last_received_tick in input)
   ├─ For each entity:
   │  ├─ If entity in baseline:
   │  │  ├─ Compare with baseline state
   │  │  ├─ Write "changed" bit (1 bit)
   │  │  └─ If unchanged: skip data (save 71 bits!)
   │  └─ If entity NOT in baseline:
   │     └─ Write full data directly (no flag)
   └─ Return compressed PackedByteArray

4. BIT PACKING (entity_snapshot.gd:BitWriter)
   ├─ Position: 18 bits per axis (vs 64 bits for float)
   ├─ Velocity: 11 bits per axis (vs 64 bits for float)
   ├─ Entity ID: Variable-length (6-14 bits vs 32 bits)
   └─ Result: ~72 bits per entity (vs ~256 bits uncompressed)

5. NETWORK SEND (game_server.gd)
   └─ ENet sends unreliable UDP packet to client
```

### Client Pipeline (Every frame / 60+ Hz)

```
1. NETWORK RECEIVE (game_client.gd)
   └─ Receive UDP packet from server

2. DESERIALIZATION (entity_snapshot.gd:deserialize)
   ├─ Read header (sequence, timestamp, baseline_seq)
   ├─ Validate baseline sequence number
   ├─ For each entity:
   │  ├─ Read entity ID (variable-length delta encoding)
   │  ├─ If entity in baseline:
   │  │  ├─ Read "changed" bit
   │  │  └─ If unchanged: copy from baseline
   │  └─ Else: read full data
   └─ Return EntitySnapshot

3. INTERPOLATION BUFFER (client_interpolator.gd)
   ├─ Store snapshot in circular buffer (max 20 snapshots)
   ├─ Maintain `render_time` based on a smoothly adjusted synchronized server clock
   ├─ Find two snapshots around render_time:
   │  └─ from_snapshot (just before render_time)
   │  └─ to_snapshot (just after render_time)
   └─ Calculate interpolation factor (alpha)

4. HERMITE INTERPOLATION (client_interpolator.gd:interpolate_entity)
   ├─ For each entity:
   │  ├─ Get position and velocity from both snapshots
   │  ├─ Calculate Hermite basis functions (h00, h10, h01, h11)
   │  └─ Interpolate: pos = h00*p0 + h10*v0*dt + h01*p1 + h11*v1*dt
   └─ Result: Smooth curved motion (not linear!)

5. RENDERING (client_renderer.gd)
   ├─ Create/update Sprite2D nodes for each entity
   ├─ Set position to interpolated value
   ├─ Update sprite frame and facing direction
   └─ Remove sprites for entities no longer visible
```

## Key Components Explained

### 1. Spatial Partitioning (Chunks)

**Purpose:** Efficiently determine which entities are visible to each client

**Data Structure:**
```gdscript
var chunks: Dictionary = {}  # Vector2i -> Array[entity_id]
```

**How it Works:**
```
World divided into 64×64 unit chunks:

   -2   -1    0    1    2    (chunk X)
  ┌────┬────┬────┬────┬────┐
  │    │    │    │    │    │ 2
  ├────┼────┼────┼────┼────┤
  │    │    │ P  │    │    │ 1  (P = Player at chunk (0,1))
  ├────┼────┼────┼────┼────┤
  │    │ ▓▓ │ ▓▓ │ ▓▓ │    │ 0  (▓ = Visible area, 5×5 chunks)
  ├────┼────┼────┼────┼────┤
  │    │ ▓▓ │ ▓▓ │ ▓▓ │    │ -1
  ├────┼────┼────┼────┼────┤
  │    │ ▓▓ │ ▓▓ │ ▓▓ │    │ -2
  └────┴────┴────┴────┴────┘

Player can see entities in chunks (-1 to 1, -1 to 3)
= 5 × 5 = 25 chunks checked
```

**Complexity:**
- **O(1)** chunk lookup (Dictionary)
- **O(k)** where k = entities in visible chunks (not all entities!)
- Scales to 10,000+ entities easily

### 2. Delta Compression

**Concept:** Only send what changed since last acknowledged snapshot

**Example:**
```
Baseline Snapshot #10:
  Entity 1: pos=(100, 200), vel=(5, 0), frame=2
  Entity 2: pos=(150, 300), vel=(0, 3), frame=1

New Snapshot #11:
  Entity 1: pos=(105, 200), vel=(5, 0), frame=2  ← CHANGED (position)
  Entity 2: pos=(150, 303), vel=(0, 3), frame=1  ← CHANGED (position)

Compressed Snapshot #11:
  Entity 1: [1 bit: CHANGED=1] + [72 bits: full data]
  Entity 2: [1 bit: CHANGED=1] + [72 bits: full data]

New Snapshot #12 (entities stopped moving):
  Entity 1: pos=(105, 200), vel=(0, 0), frame=2  ← UNCHANGED
  Entity 2: pos=(150, 303), vel=(0, 0), frame=1  ← UNCHANGED

Compressed Snapshot #12:
  Entity 1: [1 bit: CHANGED=0] ← Client copies from baseline!
  Entity 2: [1 bit: CHANGED=0]
  Total: 2 bits (vs 144 bits = 98.6% compression!)
```

**When Does This Work Best?**
- Farming/building games (many static entities)
- NPCs that don't move every frame
- Large worlds where most entities are idle

**When Does It Work Poorly?**
- Fast-paced action (all entities moving constantly)
- Physics simulations (jittery velocities)
- Insufficient `states_equal()` threshold (false positives)

### 2.5. Ack-based Delta Compression (To prevent "Death Spirals")

**Problem with previous "last-sent" delta compression:**
- If the server uses the *last sent* snapshot as the baseline, and that snapshot packet is lost, the client cannot decode subsequent delta-compressed snapshots. This leads to a request for a full snapshot and a lag spike.

**Solution: Ack-based Delta Compression**
- **Client Role:** Includes `last_received_tick` (the sequence number of the last successfully processed snapshot) in every input packet sent to the server.
- **Server Role:**
    1. Maintains a history of recent snapshots (e.g., last 1-2 seconds worth).
    2. When preparing a new snapshot for a client, it checks the `last_received_tick` sent by that client.
    3. It then retrieves the snapshot corresponding to that `last_received_tick` from its history to use as the *baseline* for delta compression.
    4. If the client's `last_received_tick` is too old or refers to a snapshot no longer in history, the server sends a full snapshot.

**Benefits:**
- **Packet Loss Resilience:** If a delta-compressed snapshot (e.g., S101) is lost, the client will continue to acknowledge S100. The server can then send S102, using S100 as the baseline, which the client can successfully decode. This prevents the "death spiral" of repeated full snapshot requests.
- **Smoother Gameplay:** Reduces lag spikes and hitches in the presence of minor packet loss.


### 3. Hermite Interpolation

**Why Not Linear?**

Linear interpolation doesn't account for velocity:
```
     From (v=5)              To (v=0)
        ┌──────────────────────●
        │                    /  │
Linear: │                  /    │ ← Sharp corner at "To"
        │                /      │
        ┴───────────────────────┴
```

Hermite uses velocity for smooth curves:
```
     From (v=5)              To (v=0)
        ┌──────────────────────●
        │                  ╱    │
Hermite:│               ╱       │ ← Smooth deceleration
        │           ╱           │
        ┴───────────────────────┴
```

**Formula:**
```gdscript
var h00 = (1 + 2*t) * (1 - t) * (1 - t)  # Hermite basis function
var h10 = t * (1 - t) * (1 - t)
var h01 = t * t * (3 - 2*t)
var h11 = t * t * (t - 1)

var interpolated_pos = h00 * pos0 + h10 * vel0 * dt + h01 * pos1 + h11 * vel1 * dt
```

Where:
- `t` = alpha (0.0 to 1.0)
- `dt` = time between snapshots (0.1s)
- `pos0, vel0` = state in from_snapshot
- `pos1, vel1` = state in to_snapshot

### 4. Interpolation Buffer

**Purpose:** Smooth out network jitter and packet loss

**Buffer Strategy:**
```
Server timeline:
  0.0s    0.1s    0.2s    0.3s    0.4s    0.5s
   │       │       │       │       │       │
   S0      S1      S2      S3      S4      S5  (Snapshots)

Client receives at variable times (network jitter):
   0.05s   0.15s   0.25s   0.35s   [LOST]  0.55s

Client render_time stays 150ms behind:
   │       │       │       │       │       │
  -0.15s  -0.05s   0.05s   0.15s   0.25s   0.35s
   ▼       ▼       ▼       ▼       ▼       ▼
   S0↔S1   S0↔S1   S1↔S2   S2↔S3   S3↔S4   S4↔S5

Interpolates between buffered snapshots, not latest!
```

**Benefits:**
- Can skip lost packets (interpolate S3 to S5)
- Absorbs network jitter (variable arrival times)
- Predictable rendering (no stuttering)

**Trade-off:**
- 150ms input lag (acceptable for non-competitive games)

### 4.5. Adaptive Clock Synchronization

**Mechanism:**
The client uses a Proportional Controller (P-Controller) to keep the `render_time` synchronized with `latest_server_time`.

**How it Works:**
1.  **Target:** `render_time` should always be exactly `TOTAL_CLIENT_DELAY` (150ms) behind `latest_server_time`.
2.  **Error Calculation:** `error = (latest_server_time - render_time) - target_delay`.
3.  **Correction:**
    - If `error > 0` (buffer too full): `time_scale > 1.0` (Fast forward slightly).
    - If `error < 0` (buffer draining): `time_scale < 1.0` (Slow motion slightly).
    - **Deadzone:** No adjustment if error is within 10ms.
    - **Gain:** `time_scale = 1.0 + (error * 0.5)`

**Code:**
```gdscript
# client_interpolator.gd
var time_scale = 1.0
if abs(error) > 0.010:
    time_scale = 1.0 + (error * 0.5)
    time_scale = clamp(time_scale, 0.90, 1.10) # ±10% max speed change
```

**Pros/Cons:**
- **Pro:** Simple to implement, keeps buffer size bounded.
- **Con:** Network jitter directly affects game speed (minor "rubber-banding").


### 5. Entity Sorting & Culling (Hysteresis)

**Problem:**
Bandwidth is limited (`MAX_ENTITIES_PER_SNAPSHOT = 100`). If 105 entities are nearby, the 5 furthest ones are culled. Without hysteresis, an entity at the edge of the cutoff distance would flicker in and out of the snapshot every tick as the player moves slightly.

**Solution: Hysteresis Score**
The server sorts entities by a "modified distance" before culling:
`Score = DistanceSquared - (IsActive ? BONUS : 0)`

**Logic (`server_world.gd`):**
1.  Collect all entities within `INTEREST_RADIUS`.
2.  Always include the **Player Entity** (priority #1).
3.  For others, calculate distance to player.
4.  If an entity was in the *previous* snapshot sent to this client, subtract `HYSTERESIS_BONUS` (10,000 units²) from its distance score.
5.  Sort by score (ascending).
6.  Take the top `MAX_ENTITIES_PER_SNAPSHOT`.

**Result:**
Once an entity "enters" the snapshot list, it becomes "sticky". It has to be significantly further away than a new candidate to be dropped. This prevents flickering at the visibility edge.

## Networking Constants

All in `scripts/network_config.gd`:

| Constant | Value | Purpose |
|----------|-------|---------|
| `TICK_RATE` | 20 Hz | Server simulation updates per second |
| `SNAPSHOT_RATE` | 20 Hz | Network snapshots sent per second |
| `INTERPOLATION_DELAY` | 100ms | Base delay for interpolation |
| `JITTER_BUFFER` | 50ms | Extra buffer for network variance |
| `CHUNK_SIZE` | 64 units | Spatial partitioning grid size |
| `INTEREST_RADIUS` | 2 chunks | How far clients can see (5×5 area) |
| `POSITION_BITS` | 18 bits | Quantization precision for positions |
| `VELOCITY_BITS` | 11 bits | Quantization precision for velocities |
| `MAX_ENTITIES_PER_SNAPSHOT` | 100 | Prevent exceeding MTU (1400 bytes) |

## Bandwidth Calculation

### Per-Entity Bandwidth (Without Compression)

```
Entity ID:      32 bits
Position X:     64 bits (float)
Position Y:     64 bits (float)
Velocity X:     64 bits (float)
Velocity Y:     64 bits (float)
Sprite Frame:   8 bits
State Flags:    8 bits
─────────────────────────
Total:          240 bits = 30 bytes per entity
```

### Per-Entity Bandwidth (With Compression)

```
Entity ID delta: 6-14 bits (variable-length, typically 6)
Position X:      18 bits (quantized)
Position Y:      18 bits (quantized)
Velocity X:      11 bits (quantized)
Velocity Y:      11 bits (quantized)
Sprite Frame:    8 bits
State Flags:     8 bits
─────────────────────────
Total:           80 bits = 10 bytes per entity (67% savings)
```

### Per-Entity Bandwidth (With Delta Compression, Unchanged)

```
Entity ID delta: 6 bits
Changed flag:    1 bit
[Entity data skipped, copied from baseline]
─────────────────────────
Total:           7 bits = 0.875 bytes per entity (97% savings!)
```

### Example: 100 Entities, 10 Hz Snapshots

**Scenario 1: All entities moving (worst case)**
```
100 entities × 10 bytes × 10 Hz = 10 KB/s per client
```

**Scenario 2: 20% entities moving (typical farming game)**
```
20 entities × 10 bytes × 10 Hz = 2 KB/s
80 entities × 0.875 bytes × 10 Hz = 0.7 KB/s
Total: 2.7 KB/s per client (73% savings)
```

**Scenario 3: Static scene (all entities idle)**
```
100 entities × 0.875 bytes × 10 Hz = 0.875 KB/s per client (91% savings)
```

### Server Bandwidth (100 clients)

```
Typical farming game: 2.7 KB/s × 100 clients = 270 KB/s = 2.16 Mbps
Static scene: 0.875 KB/s × 100 clients = 87.5 KB/s = 0.7 Mbps

Easily handled by even modest server connections!
```

## Common Pitfalls



### 2. Bit Stream Not Flushed

**Bug:**
```gdscript
func serialize(baseline) -> PackedByteArray:
    var writer = BitWriter.new(buffer)
    # ... write bits ...
    return buffer  # BUG: Last byte not written!
```

**Fix:**
```gdscript
    writer.flush()  # ← Always flush before returning!
    return buffer
```

**Symptom:** Last 1-7 bits of data lost, random corruption

### 3. Interpolation Buffer Empty

**Bug:**
```gdscript
# Client started, no snapshots yet
var from = snapshots.get(render_time - 0.05)  # null!
var to = snapshots.get(render_time + 0.05)    # null!
```

**Fix:**
```gdscript
if snapshots.size() < 2:
    print("[INTERPOLATOR] WARNING: Low buffer!")
    return  # Wait for more snapshots
```

**Symptom:** Errors on client startup, player invisible

### 4. Quantization Out of Bounds

**Bug:**
```gdscript
# Entity at position (10000, 10000)
# WORLD_MAX = 1000
var quantized = quantize_position(Vector2(10000, 10000))
# Result: Integer overflow, wraps to negative!
```

**Fix:**
```gdscript
# In network_config.gd
position.x = clamp(position.x, WORLD_MIN, WORLD_MAX)
position.y = clamp(position.y, WORLD_MIN, WORLD_MAX)
```

**Symptom:** Entities teleport to random locations

## Testing Strategy

### Unit Tests (Manual)

1. **Serialization Round-Trip:**
   ```gdscript
   var snapshot1 = create_test_snapshot()
   var data = snapshot1.serialize(null)
   var snapshot2 = EntitySnapshot.deserialize(data, null)
   assert(snapshots_equal(snapshot1, snapshot2))
   ```

2. **Delta Compression:**
   ```gdscript
   var baseline = create_snapshot([Entity(1, pos=(0,0))])
   var snapshot = create_snapshot([Entity(1, pos=(0,0))])  # Unchanged
   var data = snapshot.serialize(baseline)
   assert(data.size() < 10)  # Should be tiny (delta compressed)
   ```

3. **Interpolation:**
   ```gdscript
   var from = Snapshot(time=0.0, entities=[Entity(1, pos=(0,0), vel=(10,0))])
   var to = Snapshot(time=0.1, entities=[Entity(1, pos=(1,0), vel=(10,0))])
   var interpolated = interpolate(from, to, alpha=0.5)
   assert(interpolated.position.x ≈ 0.5)  # Halfway between
   ```

### Integration Tests (In-Game)

1. **Entity Entering View:**
   - Start client
   - Move player across chunk boundary
   - Verify: New entities appear smoothly, no errors

2. **Packet Loss Resilience:**
   - Simulate 10% packet loss
   - Move player continuously
   - Verify: Smooth motion, interpolator skips missing snapshots

3. **Compression Effectiveness:**
   - Run server for 5 minutes
   - Check logs for snapshot #100, #200, etc.
   - Verify: 70-99% compression depending on activity

## Performance Targets

| Metric | Target | Current |
|--------|--------|---------|
| Server tick rate | 20 Hz stable | ✓ |
| Client FPS | 60+ Hz | ✓ |
| Snapshot bandwidth | <10 KB/s per client | ✓ |
| Interpolation delay | 150ms ± 50ms | ✓ |
| Max entities tracked | 10,000+ | ✓ |
| Max entities visible | 100-500 per client | ✓ |
| Chunk lookup | O(1) | ✓ |
| Snapshot buffer | 20 snapshots (2 seconds) | ✓ |

## Further Reading

- **GafferOnGames:** [State Synchronization](https://gafferongames.com/post/state_synchronization/)
- **Valve Source Engine:** [Lag Compensation](https://developer.valvesoftware.com/wiki/Latency_Compensating_Methods_in_Client/Server_In-game_Protocol_Design_and_Optimization)
- **Quake 3 Networking:** [Fabien Sanglard's Article](https://fabiensanglard.net/quake3/network.php)
- **Project Docs:**
  - `DELTA_COMPRESSION_BUG.md` - Deep dive into the serialization bug
  - `CLAUDE.md` - Development guide and troubleshooting
  - `scripts/entity_snapshot.gd` - Inline code comments
