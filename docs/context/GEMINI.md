# Senior Netcode Audit
**Date:** 2025-11-20
**Status:** CRITICAL ISSUES IDENTIFIED

## Executive Summary
The current snapshot interpolation implementation is **mathematically unsound** for real-world network conditions. While it functions in a 0-latency, 0-loss local environment, it is guaranteed to fail on the public internet. The primary issues are an insufficient interpolation buffer that guarantees stuttering and a fragile delta-compression scheme that causes "death spirals" of full-snapshot requests upon any packet loss.

## 1. The Buffer Math is Broken
**Severity:** CRITICAL
**Location:** `scripts/network_config.gd`

The current configuration guarantees buffer underruns.

*   **Snapshot Rate:** 10 Hz → **100ms** between packets.
*   **Interpolation Delay:** 50ms.
*   **Jitter Buffer:** 25ms.
*   **Total Buffer:** 75ms.

**The Problem:** You cannot bridge a 100ms gap (the time between two snapshots) with a 75ms buffer.
*   At `t=0`, you receive Snapshot A.
*   At `t=100ms`, you receive Snapshot B.
*   The interpolator needs to render from `t=0` to `t=100ms`.
*   However, the buffer only holds data up to `t=0 + 75ms`.
*   **Result:** The interpolator runs dry at `t=75ms`, causing a 25ms freeze *every single frame* even with perfect networking.

**Immediate Fix:**
The buffer *must* be at least `Period + Jitter`. For 10Hz (100ms), the minimum buffer is ~120-150ms.
*   **Recommendation:** Increase `SNAPSHOT_RATE` to 20Hz (50ms) OR increase `INTERPOLATION_DELAY` to 150ms.

## 2. "Ack-less" Delta Compression & The Death Spiral
**Severity:** HIGH
**Location:** `scripts/game_server.gd`, `scripts/entity_snapshot.gd`

The server uses the *last sent* snapshot as the baseline for delta compression, not the *last acknowledged* snapshot.

**The Problem:**
1.  Server sends Snapshot 100. (Baseline: 99)
2.  Server sends Snapshot 101. (Baseline: 100) -> **Packet Lost.**
3.  Server sends Snapshot 102. (Baseline: 101)
4.  Client receives 102. It looks for Baseline 101. **It doesn't have it.**
5.  Client discards 102. Client requests "Full Snapshot".
6.  Client freezes until the server receives the request and the next full snapshot arrives (RTT + 50ms).

**Result:** A single dropped packet causes a massive lag spike (200ms+). On a connection with 1% packet loss, the game will hitch every few seconds.

**Recommendation:**
Implement "Ack-based" delta compression.
*   Client sends `last_received_tick` in every input packet.
*   Server keeps a history of snapshots (last ~1 sec).
*   Server constructs new snapshot using `last_received_tick` as the baseline.
*   If packet 101 drops, client keeps Acking 100. Server sends 102 using 100 as baseline. Client can decode it successfully.

## 3. Entity Flickering (Z-Fighting)
**Severity:** MEDIUM
**Location:** `scripts/server_world.gd`

The `MAX_ENTITIES_PER_SNAPSHOT` limit sorts entities by distance and hard-cuts the list.

**The Problem:**
If `MAX` is 100, and 102 entities are nearby:
*   Tick 1: Entity A is #100 (sent), Entity B is #101 (culled).
*   Tick 2: Player moves 1 pixel. Entity B is #100 (sent), Entity A is #101 (culled).
*   **Result:** Entities A and B flicker in and out of existence rapidly at the edge of vision.

**Recommendation:**
Implement **Hysteresis**.
*   "Active Set": Keep track of entities currently known to the client.
*   Give a bonus score to entities already in the Active Set during sorting.
*   This prevents them from falling off the list due to minor jitter.

## 4. Weak Clock Synchronization
**Severity:** MEDIUM
**Location:** `scripts/client_interpolator.gd`

The client adjusts its `render_time` based solely on buffer health ("time stretching").

**The Problem:**
This couples "buffering" with "clock sync". If a burst of packets arrives (jitter), the buffer fills, and the client speeds up. Then the burst ends, and it slows down. This causes "rubber-banding" speed changes.

**Recommendation:**
Separate Clock Sync from Buffer Management.
*   Use a distinct algorithm to estimate `ServerTime - ClientTime` (e.g., finding the lower bound of RTT).
*   `render_time` should track this synchronized clock smoothly.
*   Buffer health should only trigger "emergency" catch-up/slow-down if it deviates significantly (e.g., >100ms off).

## 5. Automated Testing Tools
**Location:** `testing/tools/gemini_auto_debug.py`

A specialized wrapper is available to run headless network simulations, analyze logs, and generate debugging context for LLMs.

**Usage:**
```bash
python3 testing/tools/gemini_auto_debug.py [OPTIONS]
```

**Key Options:**
*   `--test <name>`: Preset scenario (`basic`, `stress`, `lag`, `packet_loss`, `jitter`, `bad_network`, `custom`).
*   `--mode <behavior>`: Client movement behavior.
    *   `random_walk`: Default, erratic movement.
    *   `stress_test`: Rapid direction changes.
    *   `figure_eight`: Smooth continuous curves (good for interpolation checks).
    *   `circle_pattern`: Constant turning.
    *   `churn`: Periodically connects/disconnects.
    *   `convergence`: All clients move to (0,0).
    *   `route_replay`: Deterministic square path.
*   `--clients <N>`: Number of concurrent clients.
*   `--duration <sec>`: Test duration.

**Network Simulation Flags:**
*   `--loss <0.0-1.0>`: Packet loss rate (e.g., 0.05 for 5%).
*   `--lag <ms>`: Base latency.
*   `--jitter <ms>`: Random latency variance (+/-).
*   `--bw <KB/s>`: Bandwidth limit (drop packets if exceeded).
*   `--duplicate <0.0-1.0>`: Packet duplication rate.

**Common Scenarios:**

1.  **Interpolation Smoothness Check:**
    ```bash
    python3 testing/tools/gemini_auto_debug.py --test custom --mode figure_eight --jitter 30 --loss 0.02
    ```
    Tests if the interpolator handles jitter/loss smoothly on curves.

2.  **Stress Test (Chaos):**
    ```bash
    python3 testing/tools/gemini_auto_debug.py --test bad_network
    ```
    Simulates 5% loss, 150ms lag, 40ms jitter, and duplicates.

3.  **Connection Stability (Churn):**
    ```bash
    python3 testing/tools/gemini_auto_debug.py --test custom --mode churn --clients 5 --duration 60
    ```
    Tests server handling of frequent connects/disconnects.

4.  **Bandwidth Constraint:**
    ```bash
    python3 testing/tools/gemini_auto_debug.py --test custom --clients 4 --bw 64
    ```
    Limits bandwidth to 64KB/s to test compression and congestion.

**Output:**
The tool streams progress to the console and ends with a `🤖 GEMINI DEBUG CONTEXT GENERATED` block. Paste this block into the chat to have the agent analyze the logs and propose fixes.