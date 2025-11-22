# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Godot 4.3+ project implementing **server-authoritative snapshot interpolation** networking for MMO-scale games (targeting 10,000+ players). The architecture is based on GafferOnGames' snapshot interpolation and compression techniques, designed for games like Stardew Valley with multiplayer support.

## Running the Project

### Opening in Godot
```bash
# Open Godot 4.3 or later, import project.godot
# OR launch directly from command line:
/Applications/Godot.app/Contents/MacOS/Godot --path "/path/to/snapshot-interpolation" --editor
```

### Testing Server/Client

**Method 1: Two Godot Instances**
1. Run project in Godot (F5), click "Start Server"
2. Run project again in separate window, click "Start Client"
3. Use arrow keys to move in client

**Method 2: Headless Server (if implementing)**
```bash
godot --headless --path . --server
```

### Key Network Parameters

All networking constants are centralized in `NetworkConfig` (autoload singleton):
- Server tick rate: 20 Hz (50ms per tick)
- Snapshot rate: 10 Hz (sent every 2 ticks)
- Client interpolation delay: 100ms + 50ms jitter buffer = 150ms total
- Chunk size: 64 world units
- Interest radius: 2 chunks (5×5 area visible)

## Architecture

### Core Components (scripts/)

**Server-Side:**
1. `server_world.gd` - Authoritative simulation running at 20 Hz
   - Spatial partitioning using chunk-based `Dictionary` (O(1) lookup)
   - Interest management: only sends entities within INTEREST_RADIUS chunks
   - Entity class: `id`, `position`, `velocity`, `sprite_frame`, `state_flags`, `chunk`, `peer_id`
   - Key methods: `spawn_entity()`, `handle_player_input()`, `create_snapshot_for_peer()`

2. `entity_snapshot.gd` - Snapshot serialization with compression
   - Quantization: 18-bit positions (~2mm precision), 11-bit velocities
   - Delta compression: only sends changes vs acknowledged baseline
   - Variable-length entity ID encoding (6-14 bits vs 32 bits)
   - BitWriter/BitReader for efficient bit packing

3. `game_server.gd` - Network layer handling ENet connections

**Client-Side:**
1. `client_interpolator.gd` - Snapshot buffering and Hermite interpolation
   - Maintains 150ms delay buffer for smooth playback
   - Hermite spline interpolation (uses velocity for smooth curves)
   - Handles packet loss (can skip 2+ consecutive snapshots)

2. `client_renderer.gd` - Visual rendering of entities
3. `game_client.gd` - Network layer for client

**Shared:**
- `network_config.gd` - Autoload singleton with all network constants and quantization helpers
- `test_launcher.gd` - UI for launching server/client modes

### Critical Architecture Patterns

**Spatial Partitioning:**
```gdscript
# O(1) chunk lookup, not O(n) distance checks
var chunks: Dictionary = {}  # Vector2i -> Array[entity_id]
var center_chunk = NetworkConfig.world_to_chunk(player_pos)
for x in range(-INTEREST_RADIUS, INTEREST_RADIUS + 1):
    for y in range(-INTEREST_RADIUS, INTEREST_RADIUS + 1):
        if chunks.has(center_chunk + Vector2i(x, y)):
            entities.append_array(chunks[center_chunk + Vector2i(x, y)])
```

**Delta Compression:**
```gdscript
# Store last acknowledged snapshot per peer
var last_snapshots: Dictionary = {}  # peer_id -> EntitySnapshot
var baseline = last_snapshots.get(peer_id)
var compressed_data = snapshot.serialize(baseline)  # Only changed entities

# CRITICAL: Serialization and deserialization must be perfectly symmetric!
# Server: if baseline and baseline.has_entity(id): write_bits(changed, 1)
# Client: if baseline and baseline.has_entity(id): changed = read_bits(1)
# See DELTA_COMPRESSION_BUG.md for detailed explanation
```

**How Delta Compression Works:**

1. **Server tracks last acknowledged snapshot per client** (baseline)
2. **For each entity in new snapshot:**
   - If entity exists in baseline → Write 1-bit "changed" flag
     - If changed=0 → Client copies from baseline (1 bit vs 72 bits!)
     - If changed=1 → Write full entity data (73 bits)
   - If entity NOT in baseline → Write full data directly (no flag needed)
3. **Bandwidth savings:** 76-99% depending on scene activity
4. **Edge cases handled:**
   - New entities entering view (no baseline exists)
   - Entities exiting view (removed from snapshot)
   - First snapshot (no baseline, full data sent)

**IMPORTANT BUG FIX (2025-11-16):**
The deserialization logic had a critical bug where it read the "changed" bit for ALL entities when a baseline existed, but serialization only wrote the bit for entities that existed in the baseline. This caused bit stream corruption when new entities entered view.

**Fixed in:** `scripts/entity_snapshot.gd:167`
**Symptom:** Random entity/player disappearances
**Root cause:** Bit stream desynchronization
**See:** `DELTA_COMPRESSION_BUG.md` for complete technical analysis

**IMPORTANT BUG FIX (2025-11-16): Per-Client Snapshot Sequences**
The server was using a **global** snapshot sequence counter that incremented for every client's snapshot. With 2 clients, this caused:
- Client 1 receives: seq 1, 3, 5, 7... (skipping even numbers)
- Client 2 receives: seq 2, 4, 6, 8... (skipping odd numbers)
- Both clients reported ~50% "packet loss" (actually just sequence gaps)
- Clients became jittery/laggy due to perceived packet loss

**Fixed in:** `scripts/server_world.gd:15, 223-230`
**Root cause:** Shared sequence counter incremented N times per tick (N = number of clients)
**Solution:** Changed to per-client sequence tracking: `var snapshot_sequences: Dictionary = {}  # peer_id -> int`
**Impact:** Each client now gets consecutive sequences (1, 2, 3...) regardless of how many other clients are connected

**Hermite Interpolation (not linear!):**
```gdscript
# Uses velocity for smooth acceleration/deceleration
# h00, h10, h01, h11 are Hermite basis functions
position = h00*p0 + h10*v0*dt + h01*p1 + h11*v1*dt
```

## Common Development Tasks

### Adding New Entity Properties

When extending `ServerWorld.Entity` class:
1. Add property to Entity class in `server_world.gd`
2. Update `EntitySnapshot.EntityState` in `entity_snapshot.gd`
3. Modify serialization in `EntitySnapshot.serialize()` with `writer.write_bits()`
4. Update deserialization in `EntitySnapshot.deserialize()`
5. Update `ClientInterpolator` if property needs interpolation

### Modifying Network Compression

All quantization helpers are in `network_config.gd`:
- `quantize_position()` / `dequantize_position()` - 18-bit precision
- `quantize_velocity()` / `dequantize_velocity()` - 11-bit precision
- Adjust `POSITION_BITS`, `VELOCITY_BITS`, `WORLD_MIN`, `WORLD_MAX` constants

### Performance Tuning

Key constants in `network_config.gd`:
- `TICK_RATE`: Higher = more accurate simulation, more CPU
- `SNAPSHOT_RATE`: Higher = smoother interpolation, more bandwidth
- `CHUNK_SIZE`: Smaller = finer interest management, more chunk overhead
- `INTEREST_RADIUS`: Larger = more entities visible, more bandwidth
- `MAX_ENTITIES_PER_SNAPSHOT`: Prevents packet size exceeding MTU (1400 bytes)

### Testing Compression Effectiveness

Server console prints snapshot stats every 100 snapshots:
```
Snapshot #100 to peer 1: 51 entities, 423 bytes (uncompressed: ~2550 bytes)
```

Expected bandwidth per client (100 entities visible):
- All entities changed: ~1.2 KB/s (76% savings)
- 20% changed (typical farming game): ~250 bytes/s (95% savings)
- Static scene: ~50 bytes/s (99% savings)

## Godot-Specific Notes

- Main scene: `scenes/main.tscn`
- Autoload singleton: `NetworkConfig` (automatically available everywhere)
- Uses Godot 4.3+ features (typed arrays, class_name, etc.)
- Physics process runs at variable framerate, but server simulation uses fixed timestep accumulator
- GDScript class syntax: `class Entity:` for inner classes, `class_name ServerWorld` for file-level classes

## Code Style Patterns

- Use typed arrays: `var entities: Array[int] = []`
- Dictionary type hints: `var chunks: Dictionary = {}  # Vector2i -> Array[entity_id]`
- Constants in SCREAMING_SNAKE_CASE
- Static helper functions in NetworkConfig for shared utilities
- Physics simulation always uses fixed timestep (`while tick_accumulator >= TICK_DELTA`)

## Known Limitations

- Currently uses ENet (replace with custom UDP for production)
- No client-side prediction (local player has full 150ms delay)
- No lag compensation for hit detection
- No reliable message layer (all snapshots are unreliable UDP)
- Single-server architecture (no load balancing across processes)

## Search Instructions

When working in an environment where `ast-grep` is available, use the following search preferences:

- **Default to `ast-grep` for syntax-aware searches**: Whenever a search requires syntax-aware or structural matching, use `ast-grep --lang <language> -p '<pattern>'` (set `--lang` appropriately for the target language)
- **Avoid falling back to text-only tools**: Do not use `rg` or `grep` for structural searches unless explicitly requested to perform a plain-text search
- **Language detection**: Automatically detect and set the appropriate `--lang` flag based on file extensions or context

### Example Usage:
- For Rust: `ast-grep --lang rust -p 'fn $FUNC($$$)'`
- For TypeScript: `ast-grep --lang typescript -p 'class $NAME { $$$ }'`
- For Python: `ast-grep --lang python -p 'def $FUNC($$$):'`
- For Go: `ast-grep --lang go -p 'func $NAME($$$) $$$'`
- For Java: `ast-grep --lang java -p 'public class $NAME { $$$ }'`

### Pattern Syntax:
- `$NAME` - matches any single identifier
- `$$$` - matches any number of AST nodes
- `$_` - matches any single AST node
- Use exact syntax structures from the target language

## Timezone and Date Awareness

Very important: The user's timezone is {datetime(.)now().strftime("%Z")}. The current date is {datetime(.)now().strftime("%Y-%m-%d")}.

Any dates before this are in the past, and any dates after this are in the future. When the user asks for the 'latest', 'most recent', 'today's', etc. don't assume your knowledge is up to date;

## Project Structure

- **Server code**: `scripts/server_world.gd`, `scripts/game_server.gd`
- **Client code**: `scripts/client_interpolator.gd`, `scripts/client_renderer.gd`, `scripts/game_client.gd`
- **Shared code**: `scripts/entity_snapshot.gd`, `scripts/network_config.gd`
- **Debugging tools**: `debug_test.sh`, `analyze_logs.sh`
- **Main scene**: `scenes/main.tscn`

## Troubleshooting

### Entities Disappearing Randomly

**Symptoms:**
- Player or NPCs vanish from screen intermittently
- Console shows: `[CLIENT] ERROR: Player entity X NOT in snapshot`
- Console shows: `[INTERPOLATOR] Entity X disappeared`

**Common Causes:**

1. **Delta compression bit stream corruption** (FIXED 2025-11-16)
   - Check `scripts/entity_snapshot.gd:167` has correct condition
   - Verify: `if baseline and baseline.has_entity(entity_id):`
   - See `DELTA_COMPRESSION_BUG.md` for details

2. **Interest management removing entities**
   - Check player chunk position vs entity chunk position
   - Increase `INTEREST_RADIUS` in `network_config.gd` for testing
   - Look for: `[SERVER] Player entity X moved from chunk (a, b) to (c, d)`

3. **Baseline mismatch (out-of-order packets)**
   - Check for: `[DESERIALIZE] WARNING: Baseline mismatch!`
   - This is normal for UDP, client should recover on next snapshot

**Debugging Steps:**

```bash
# 1. Run with logging enabled
./debug_test.sh

# 2. Analyze logs after reproducing issue
./analyze_logs.sh debug_logs/client_*.log

# 3. Check for specific patterns
grep "ERROR: Player entity" debug_logs/client_*.log
grep "DESERIALIZE.*Player.*in snapshot: false" debug_logs/client_*.log
```

### Low Framerate / Stuttering

**Symptoms:**
- Choppy movement
- Console shows: `[INTERPOLATOR] WARNING: Low buffer!`

**Causes:**
- Interpolation buffer running dry (network delay too high)
- Client running faster than server tick rate

**Fixes:**
```gdscript
# In network_config.gd, increase interpolation delay:
const INTERPOLATION_DELAY: float = 0.2  # Was 0.1, add more buffer
const JITTER_BUFFER: float = 0.1  # Was 0.05
```

### "Behind buffer" Warnings

**Symptom:**
```
[INTERPOLATOR] WARNING: Behind buffer! Jumping render_time from X to Y
```

**Cause:** Client fell too far behind server (packet loss or processing lag)

**Behavior:** Interpolator jumps forward (acceptable, prevents infinite lag)

**Prevention:**
- Ensure client can process snapshots faster than they arrive
- Profile client code for performance issues
- Consider lowering `SNAPSHOT_RATE` if network is unreliable

### Baseline Mismatch Warnings

**Symptom:**
```
[DESERIALIZE] WARNING: Baseline mismatch! Snapshot #50 expects baseline #48 but we have #47
```

**Cause:** Out-of-order packet delivery (normal for UDP)

**Behavior:** Client ignores delta compression for that snapshot and reads full data

**Impact:** Slight bandwidth spike for one snapshot, then recovers

**Fix:** This is expected behavior, not a bug. If excessive:
- Check network quality
- Consider implementing sequence buffering for out-of-order packets

### Debugging Delta Compression Issues

If you suspect delta compression problems:

1. **Disable delta compression temporarily:**
   ```gdscript
   # In server_world.gd, line ~200
   var baseline = null  # Force full snapshots (was: last_snapshots.get(peer_id))
   ```

2. **Verify serialization/deserialization symmetry:**
   ```bash
   # Check that "changed" bit conditions match
   grep -A5 "if baseline" scripts/entity_snapshot.gd
   ```

3. **Enable extensive logging:**
   - Already enabled for snapshots divisible by 10
   - Modify `if sequence % 10 == 0:` to `if true:` for all snapshots (verbose!)

4. **Compare server vs client entity counts:**
   ```bash
   # Server log shows entities sent
   grep "About to add .* entities to snapshot" debug_logs/server_*.log

   # Client log shows entities received
   grep "Received snapshot.*Entities:" debug_logs/client_*.log
   ```

### Performance Profiling

**Measure snapshot compression effectiveness:**
```bash
# Every 100 snapshots, server logs compression stats
grep "Snapshot #.*to peer.*entities.*bytes" debug_logs/server_*.log
```

**Expected results:**
- Static scene: 95-99% compression (50-100 bytes/snapshot)
- Low activity: 90-95% compression (100-250 bytes/snapshot)
- High activity: 70-85% compression (250-500 bytes/snapshot)

**If compression is poor (<50%):**
- Check if entities are constantly "changing" (velocity jitter?)
- Verify `states_equal()` threshold (currently 0.01 units)
- Increase threshold if entities vibrate due to floating-point error

### Network Debugging Commands

```bash
# Monitor real-time logs
tail -f debug_logs/client_*.log | grep ERROR

# Count total errors
grep -c "ERROR" debug_logs/client_*.log

# Find when player disappears
grep "Player entity .* NOT in snapshot" debug_logs/client_*.log

# Check interpolator state
grep "INTERPOLATOR.*Buffer state" debug_logs/client_*.log

# Verify server entity tracking
grep "Player entity .* moved from chunk" debug_logs/server_*.log
```

### Common GDScript Pitfalls

1. **Baseline not being updated after ack:**
   - Ensure `last_snapshots[peer_id] = snapshot` in server after send
   - Check `game_server.gd` and `server_world.gd`

2. **Entity IDs not sorted before delta encoding:**
   - Delta encoding assumes sorted IDs for efficiency
   - Check `entity_ids.sort()` at line 66 in `entity_snapshot.gd`

3. **Bit writer not flushed:**
   - Always call `writer.flush()` before returning buffer
   - Check line 116 in `entity_snapshot.gd`

4. **Integer overflow in quantization:**
   - Positions outside `WORLD_MIN`/`WORLD_MAX` will wrap
   - Check `NetworkConfig.quantize_position()` bounds

### Testing Checklist

Before deploying networking changes:

- [ ] Run with delta compression enabled
- [ ] Test entity entering view (new baseline entry)
- [ ] Test entity exiting view (removed from snapshot)
- [ ] Test player crossing chunk boundaries
- [ ] Test with packet loss simulation (if available)
- [ ] Verify no `[CLIENT] ERROR` messages for 5+ minutes
- [ ] Check compression stats (`Snapshot #100` logs)
- [ ] Profile client FPS (should match server tick rate)

### Advanced: Simulating Packet Loss

Add to `game_client.gd` receive logic:
```gdscript
# Simulate 10% packet loss
if randf() < 0.1:
    print("[DEBUG] Simulating packet loss, dropping snapshot")
    return

# Normal processing...
```

This tests interpolator resilience to network issues.

## Additional Documentation

- `DELTA_COMPRESSION_BUG.md` - Deep dive into the delta compression bug and fix
- `README.md` - Project overview and quick start guide
- `scripts/entity_snapshot.gd` - Inline comments explain bit packing format
