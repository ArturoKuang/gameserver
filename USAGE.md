# Usage Guide

This document explains how to run and test the snapshot interpolation system.

## Opening the Project

1. Open Godot 4.3 or later
2. Click "Import" and select the `project.godot` file in this directory
3. The project will open with the test launcher scene

## Running the Test

### Method 1: Two Instances (Recommended)

**Terminal 1 - Server:**
```bash
# Open Godot and run the project
# Click "Start Server" button
```

**Terminal 2 - Client:**
```bash
# Open another instance of Godot
# Run the same project
# Click "Start Client" button
# Use arrow keys to move around
```

### Method 2: Using Godot Editor

1. Open the project in Godot Editor
2. Press F5 to run the project
3. Click "Start Server" in the first instance
4. Run the project again (F5) in a separate window
5. Click "Start Client" in the second instance
6. Use arrow keys (↑↓←→) to move your character

## What to Expect

### Server Instance
- Displays "Server running on port 7777"
- Shows console output with:
  - Connected peers
  - Spawned entities
  - Snapshot statistics (every 100 snapshots)

### Client Instance
- Shows a visual game world with colored squares representing entities
- Your character responds to arrow key input
- Other entities (NPCs and other players) move smoothly
- Status bar shows:
  - Number of visible entities
  - Network delay (should be ~150ms)

## Testing the Features

### 1. Snapshot Interpolation
- **What**: Smooth movement despite receiving only 10 updates/second
- **How to test**: Move your character and observe smooth motion
- **Expected**: No stuttering or jittering

### 2. Delta Compression
- **What**: Bandwidth optimization by only sending changes
- **How to test**: Check server console for snapshot sizes
- **Expected**: Snapshots with few changes are ~200-500 bytes, not 5KB+

### 3. Spatial Partitioning
- **What**: Only receive updates for nearby entities
- **How to test**: Move around the world, entity count should vary
- **Expected**: See fewer entities when in empty areas

### 4. Hermite Interpolation
- **What**: Smooth velocity transitions (not just linear)
- **How to test**: Watch NPCs moving - they should accelerate/decelerate smoothly
- **Expected**: Natural-looking movement curves

## Console Output Examples

### Server Output
```
=== SERVER MODE ===
Server started on port 7777
Tick rate: 20 Hz
Snapshot rate: 10 Hz
Peer connected: 1
Snapshot #100 to peer 1: 51 entities, 423 bytes (uncompressed: ~2550 bytes)
Snapshot #200 to peer 1: 51 entities, 198 bytes (uncompressed: ~2550 bytes)
```

### Client Output
```
=== CLIENT MODE ===
Connecting to server at 127.0.0.1:7777
Connected to server!
Received snapshot #1: 51 entities, 428 bytes, render delay: 152ms
Received snapshot #100: 51 entities, 210 bytes, render delay: 148ms
```

## Troubleshooting

### "Connection failed"
- Make sure server is running first
- Check firewall settings
- Verify port 7777 is not in use

### "No entities visible"
- Wait 1-2 seconds for initial snapshots
- Check console for connection status
- Verify server is sending snapshots

### "Stuttering movement"
- Normal for first few seconds (buffer filling)
- Check network delay is ~150ms
- If >300ms, may indicate network issues

## Network Statistics

Expected bandwidth per client (100 entities visible):

| Scenario | Uncompressed | Compressed | Savings |
|----------|--------------|------------|---------|
| All changed | 5,000 bytes/s | 1,200 bytes/s | 76% |
| 20% changed | 5,000 bytes/s | 250 bytes/s | 95% |
| Static | 5,000 bytes/s | 50 bytes/s | 99% |

## Performance Targets

- **Server Tick Rate**: 20 Hz (50ms per tick)
- **Snapshot Rate**: 10 Hz (100ms per snapshot)
- **Client Delay**: 150ms (100ms interpolation + 50ms jitter)
- **Max Entities**: 10,000+ (with spatial partitioning)
- **Max Clients**: Limited by server hardware and bandwidth

## Next Steps

See [README.md](README.md) for:
- Architecture details
- Implementation guide
- Extending the system
- Production deployment tips
