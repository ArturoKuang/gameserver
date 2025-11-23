# Implementation Plan: Advanced Netcode Features

## Overview
This document outlines the implementation strategy for Client-Side Prediction, Server Reconciliation, Lag Compensation, and Robust Clock Synchronization. These features are essential for a responsive, competitive multiplayer experience, moving beyond the current basic Snapshot Interpolation model.

## 1. Client-Side Prediction (CSP)
**Goal:** Eliminate input delay for the local player.

### Current State
The client sends input to the server and waits for the server to return the new position in a snapshot. This results in a delay equal to RTT + Server Processing Time.

### Implementation Steps
1.  **Input Storage:**
    *   Create a `struct` or `Dictionary` for `PlayerInput`: `{ tick: int, direction: Vector2, timestamp: float }`.
    *   Maintain a circular buffer of `PlayerInput`s on the client.

2.  **Local Simulation:**
    *   In `_physics_process`, instead of just sending input:
        *   Apply the input to the local player's position immediately using the shared physics logic (velocity, collision, etc.).
        *   Store the resulting `PredictedState` `{ tick: int, position: Vector2, velocity: Vector2 }` in a history buffer.
    *   Send the `PlayerInput` (including the `tick` number) to the server.

3.  **Separation of Concerns:**
    *   The `ClientInterpolator` should **stop** controlling the local player entity.
    *   The local player entity should be controlled by a new `LocalPlayerController` script that handles CSP.
    *   Remote entities continue to be handled by `ClientInterpolator`.

## 2. Server Reconciliation
**Goal:** Correct client-side prediction errors caused by packet loss, variable timesteps, or cheating.

### Implementation Steps
1.  **Server Authoritative Response:**
    *   The server processes the input for a specific `tick`.
    *   The server's snapshot MUST include the `last_processed_input_tick` for each client.

2.  **Client Correction Logic:**
    *   On receiving a snapshot:
        *   Extract the authoritative position for the local player.
        *   Extract `last_processed_input_tick` (let's call it `T_server`).
        *   Look up the `PredictedState` for `T_server` in the client's history.
    *   **Comparison:**
        *   Calculate `error = distance(predicted_pos, auth_pos)`.
    *   **Reconciliation:**
        *   If `error > threshold` (e.g., 1.0 unit):
            *   **Snap:** Set local player position to `auth_pos`.
            *   **Replay:** Re-simulate all inputs in the history from `T_server + 1` up to `CurrentTick`.
            *   Update the `PredictedState` history with the new corrected values.

## 3. Robust Clock Synchronization
**Goal:** Ensure client and server agree on "time" to allow accurate Lag Compensation and Interpolation, decoupled from buffer health.

### Current State
Client adjusts time based on buffer size. This causes time scaling (speed up/slow down) which is jarring and inaccurate for lag compensation.

### Implementation Steps
1.  **Time Sync Packet:**
    *   Add a periodic "Ping" packet (every 1s):
        *   Client sends: `{ client_send_time }`
        *   Server receives, adds processing time, sends back: `{ client_send_time, server_receive_time, server_send_time }`
    *   Client receives: `{ client_receive_time }`.

2.  **Offset Calculation:**
    *   `RTT = (client_receive_time - client_send_time) - (server_send_time - server_receive_time)`
    *   `ServerTime = server_send_time + (RTT / 2)`
    *   `TimeOffset = ServerTime - ClientTime`

3.  **Smoothing:**
    *   Collect multiple samples of `TimeOffset`. discard outliers (std dev).
    *   Use a moving average or median to determine the true `TimeOffset`.
    *   Gradually adjust `ClientRenderTime` to match `ServerTime - InterpolationDelay`.

## 4. Lag Compensation
**Goal:** Allow players to shoot at what they see, not where the target "actually" is on the server.

### Implementation Steps
1.  **Server History:**
    *   The `ServerWorld` must maintain a `HistoryBuffer` of entity states (position, hitbox) for the last ~1 second.
    *   Structure: `Dictionary<tick, Dictionary<entity_id, HitboxState>>`.

2.  **Input Timestamping:**
    *   Client inputs MUST include the `render_time` (or the specific server tick) the client was seeing when they fired.

3.  **Server Rewind (During Hit Detection):**
    *   When processing a "shoot" action:
        *   Read the `interaction_time` from the input packet.
        *   Check if `interaction_time` is valid (within history limits).
        *   **Rewind:** Temporarily move all relevant entities to their positions at `interaction_time`.
            *   Interpolate between the two closest ticks in the history for accuracy.
        *   **Raycast:** Perform the raycast/hit check in this rewound state.
        *   **Restore:** Move entities back to their current server-time positions.
        *   Apply damage/effects if hit was successful.

## 5. Causality & Packet Structure Updates
**Goal:** Ensure every packet carries the necessary timing information.

### Update `PlayerInput` Packet
*   **Old:** `(direction, ack)`
*   **New:** `(tick_number, direction, render_time, ack)`
    *   `tick_number`: The client's predicted tick (for reconciliation).
    *   `render_time`: The server time the client was seeing (for lag compensation).

### Update `EntitySnapshot` Packet
*   **Old:** `(sequence, timestamp, entities...)`
*   **New:** `(sequence, timestamp, last_processed_input_tick, entities...)`
    *   `last_processed_input_tick`: Tells the specific client which of their inputs have been confirmed.

## Implementation Order
1.  **Clock Sync:** Foundation for everything else.
2.  **Causality (Packet Updates):** Prepare the data structures.
3.  **Client-Side Prediction:** Improves feel immediately.
4.  **Server Reconciliation:** Fixes the desyncs from CSP.
5.  **Lag Compensation:** Fixes combat fairness.

## 6. Verification & Debugging
**Goal:** Ensure the implementation is stable and correct through automated builds and testing.

### Build Verification
Before running complex tests, ensure the project "builds" (scripts parse correctly) by running it in headless mode.

```bash
# Run the server in headless mode to verify script integrity
godot --headless --server --quit
```

### Automated Testing
Use the provided test framework to validate changes.

**1. Run Basic Tests:**
Verify that basic movement and networking still work.
```bash
./tools/test_framework.py --test basic
```

**2. Stress Testing:**
Validate stability under load and rapid input changes.
```bash
./tools/test_framework.py --test stress
```

**3. Network Simulation:**
Test with simulated lag and packet loss to ensure the new features (Reconciliation, Lag Compensation) actually work under adverse conditions.
```bash
./tools/test_framework.py --test packet_loss
./tools/test_framework.py --test lag
```

### Log Analysis & Debugging
The test framework generates detailed logs in `test_logs/` and reports in `test_reports/`.

**1. Analyze Logs:**
After running a test, use the analyzer to generate a summary of issues (packet loss, discontinuities, entities missing).
```bash
./tools/analyze_test_logs.py test_logs/<latest_test_dir>
```

**2. Claude/LLM Debugging:**
The analyzer generates a `claude_debug_summary.md` in `test_reports/`. Feed this to your LLM to get a high-level overview of what went wrong.

**3. Manual Inspection:**
Check `test_logs/<test_dir>/server.log` and `client_0.log` for specific error messages or logic traces. Look for tags like `[CSP]` or `[Reconciliation]` if you added them.

## 7. Optimization & Cleanup
**Goal:** Remove legacy patterns and "lag-inducing" logic identified in the audit.

*   **Fix Buffer Math:** Remove the incorrect buffer calculation in `network_config.gd` that guarantees stuttering (Buffer < Period + Jitter). Replace with a robust formula.
*   **Remove "Death Spiral" Logic:** The current "Ack-less" delta compression causes massive lag spikes on packet loss. Remove this dependency by implementing the Ack-based system (Section 5).
*   **Minimize Hot-Loop Allocation:** Check `_process` loops for unnecessary object creation (new Vectors/Dictionaries) which can cause GC pauses (lag).
*   **Strip Debug Logging:** Ensure verbose logging (string concatenation) is wrapped in checks or removed from critical network paths in production builds.
