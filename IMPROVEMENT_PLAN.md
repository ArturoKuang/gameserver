# Netcode Improvement Plan

Based on the analysis of the current snapshot interpolation architecture, here are the recommended improvements categorized by robustness, bandwidth, responsiveness, and architecture.

## 1. Robustness & Reliability

### 1.1. Explicit Snapshot Acknowledgement (ACKs)
**Why:** Currently, the server assumes the client received the previous snapshot and uses it as a baseline for delta compression. If a packet is dropped, the client lacks the baseline, fails to deserialize the *next* packet (which depends on the lost one), and must request a full keyframe. This causes a "death spiral" of dropped packets leading to bandwidth spikes (full snapshots).
**How:**
1.  **Client:** In every `send_input` packet, include the `sequence_number` of the last successfully validated snapshot.
2.  **Server:** Store a buffer of recent snapshots (e.g., last 1 second) for each client.
3.  **Server:** When creating a new snapshot, look up the client's `last_acked_sequence`. Use *that* specific snapshot as the baseline, not just `N-1`.
4.  **Result:** If packet 100 is lost, the client keeps ACKing 99. The server sees "Ack: 99" and generates packet 102 using 99 as the baseline (skipping 100/101). The client can successfully read 102.

### 1.2. Redundant Input Transmission
**Why:** Input is sent via unreliable UDP. If a "stop moving" packet is lost, the character might keep walking into a wall until the next packet arrives.
**How:**
1.  **Structure:** Create an `InputPayload` struct containing `{ tick: int, axes: Vector2 }`.
2.  **Client:** Maintain a rolling buffer of the last 5-10 inputs.
3.  **Send:** In every packet, send the *history* of inputs (e.g., ticks 100, 99, 98, 97).
4.  **Server:** Process inputs by tick number. Ignore ticks already processed. Fill in gaps if a packet arrives late but contains history.

### 1.3. Clock Synchronization
**Why:** The client approximates `render_time` by simply subtracting delay from the latest snapshot timestamp. This drift is prone to RTT spikes.
**How:**
1.  Implement a dedicated "Time Sync" packet (Client request -> Server response -> Client calculate).
2.  Calculate `RTT` and `ServerTimeDelta`.
3.  Smooth the offset over time to prevent the game speed from speeding up/slowing down noticeably.

## 2. Bandwidth Optimization

### 2.1. "Sleeping" Entity Culling
**Why:** The current delta compression sends 1 bit ("unchanged") for every entity in the interest radius, even if they haven't moved for minutes. For 1000 static entities, that's 1000 bits (125 bytes) per tick per client.
**How:**
1.  **Logic:** If an entity is "asleep" (no velocity/state change for X seconds), the server stops adding it to the snapshot *even if it's in the interest radius*.
2.  **Protocol:** Add a `removed_entities` list or implicit rule: "If entity was in the last snapshot but missing in this one, AND it's still in my interest radius, assume it is static/sleeping."
3.  **Wakeup:** If the entity moves, it is re-added to the snapshot, sending full data (or delta against the "sleep" state).

### 2.2. Adaptive Snapshot Rate
**Why:** Sending 10Hz updates for a player standing still is wasteful.
**How:**
1.  **Logic:** If a player's significant entities (themselves + nearby moving things) have low velocity variance, skip sending a snapshot tick.
2.  **Implementation:** Server calculates "importance" of the update. If `importance < threshold`, skip.
3.  **Keep-alive:** Send a heartbeat every 1-2 seconds regardless of activity.

## 3. Responsiveness (UX)

### 3.1. Client-Side Prediction (CSP) - *High Priority*
**Why:** Currently, the user feels ~150ms of latency between pressing a key and seeing their character move. This feels "floaty."
**How:**
1.  **Shared Physics:** Isolate movement logic (velocity calculation, collision sliding) into a shared helper `Physics.move(entity, input)`.
2.  **Client Move:** When input is pressed, *immediately* run `Physics.move` on the local player visual.
3.  **Prediction Buffer:** Store the state and input for that tick.
4.  **Reconciliation:** When server snapshot arrives for Tick `T`:
    *   Compare predicted state `T` with server state `T`.
    *   If deviation > threshold (misprediction):
        *   Snap player to server state `T`.
        *   *Re-run* `Physics.move` for all inputs from `T+1` to `CurrentTick`.

### 3.2. Adaptive Jitter Buffer
**Why:** The jitter buffer is fixed at 50ms. Good connections don't need this much delay; bad connections might need more.
**How:**
1.  **Measure:** Client tracks the variance (standard deviation) of snapshot arrival times.
2.  **Adjust:** Set `target_delay = base_delay + (variance * 2)`.
3.  **Result:** Players with stable fiber play with 20ms jitter buffer; players on 4G play with 100ms buffer (smooth but laggy).

## 4. Code Architecture

### 4.1. Decouple Serialization
**Why:** `entity_snapshot.gd` is currently handling data storage, bit-packing, delta logic, AND serialization.
**How:**
1.  Create `class SnapshotSerializer`: Handles `serialize(snapshot, baseline) -> bytes`.
2.  Create `class BitStream`: The existing `BitWriter`/`BitReader` inner classes should be their own utility scripts (e.g., `utils/bit_stream.gd`) so they can be unit tested independently.

### 4.2. Input Command Pattern
**Why:** Passing raw `Vector2` is brittle.
**How:**
1.  Create a `UserCmd` class:
    ```gdscript
    class UserCmd:
        var tick: int
        var move_vector: Vector2
        var buttons: int # Bitmask for Jump, Attack, Interact
        var view_angle: float
    ```
2.  Use this standard object for both Client->Server transmission and CSP history.

### 4.3. Debug Overlay
**Why:** Printing to console is hard to read in real-time.
**How:**
1.  Create a `CanvasLayer` scene with a `GraphNode` or simple `Label`s.
2.  Plot:
    *   Snapshot Arrival Delta (visualize jitter).
    *   Buffer Health (how many snapshots are buffered).
    *   RTT (if clock sync is implemented).
