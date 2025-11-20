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