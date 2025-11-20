# GEMINI.md

This file provides context and guidance for Gemini when working on the **Snapshot Interpolation** project.

## Core Reference
**Primary Documentation:** See [`CLAUDE.md`](./CLAUDE.md) for deep technical details, architecture diagrams, and troubleshooting steps. This file serves as a quick reference and specific guide for Gemini-based workflows.

## Project Context
- **Engine:** Godot 4.3+ (GDScript)
- **Architecture:** Server-Authoritative Snapshot Interpolation (Valve/GafferOnGames style)
- **Target:** MMO-scale (10k+ players), unreliable UDP (ENet currently)

## Key Constraints & Conventions
- **Networking:** All constants in `NetworkConfig`. 20Hz Tick, 10Hz Snapshot.
- **Compression:** Delta compression with quantization. **Critical:** Serialization/Deserialization must be symmetric.
- **Style:** typed arrays (`Array[int]`), `class_name`, SCREAMING_SNAKE_CASE constants.
- **Testing:** `debug_test.sh` for logging, `analyze_logs.sh` for analysis.

## Common Tasks

### Running Tests
- Run `./debug_test.sh` to launch server+client with logging.
- Logs output to `debug_logs/`.

### Debugging
- Use `./analyze_logs.sh debug_logs/client_*.log` to find specific errors.
- Check `scripts/entity_snapshot.gd` for bit-packing logic.

## File Structure Highlights
- `scripts/server_world.gd`: Authoritative game loop.
- `scripts/client_interpolator.gd`: Client prediction/smoothing.
- `scripts/entity_snapshot.gd`: The core networking logic (serialization).
- `DELTA_COMPRESSION_BUG.md`: Reference for previous critical bugs.
