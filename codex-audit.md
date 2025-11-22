Codex Audit – Snapshot Interpolation Netcode

Robustness & Reliability
- Ack-driven baselines: piggyback last_received_seq on input RPC (reliable channel) and delta only against acked snapshots; keep a short per-peer baseline ring to avoid keyframe spam when packets drop.
- Split channels: use ENet reliable channel for control (acks, keyframe requests) and unreliable for snapshots to prevent control loss from snapshot drops.
- Clock sync: send periodic server time, estimate offset = server_time - (client_time - rtt/2) with EMA, and drive render_time using this offset to prevent buffer drift.
- Stale/OOO guard: drop snapshots with seq <= last_snapshot_sequence before deserialization to avoid polluting buffers/baselines with late packets.
- Explicit despawn/visibility: send reliable despawn lists or removed-IDs per snapshot so the client can clear ghosts instead of holding last-known forever.
- Health checks: periodic ping/pong; widen interpolation delay and request keyframe on jitter/loss spikes for smoother recovery.

Bandwidth Optimization
- Field-level bitmasks: per-entity change mask (pos/vel/frame/flags) so unchanged fields skip bits; reduces 18–36 bits when only one component changes.
- Priority/LOD cadence: lower send rate for far/low-importance entities, full rate for near/players; keeps MTU headroom under load.
- Deterministic movers: send path/seed once for scripted obstacles and simulate locally with occasional checksum corrections to remove them from every snapshot.
- Adaptive interest radius: shrink radius or clamp entity count when bandwidth/loss is high, expand when stable; prevents oversize packets.
- Variable precision: tiered quantization (coarser for distant/cheap entities) to reclaim bits where precision is not visible.

Responsiveness / UX
- Full prediction + reconciliation: include input seq numbers, echo last_processed_input in snapshots, and replay unacked inputs after applying server state to remove the feel of the interpolation buffer for the local player.
- Smarter smoothing: replace fixed blend with critically damped spring toward server position/velocity to reduce rubber-banding under jitter.
- Dynamic interpolation delay: adjust TOTAL_CLIENT_DELAY based on measured jitter/loss (widen under loss, shrink when clean) to keep the buffer healthy with minimal latency.
- Enter/exit masking: brief fade-in/out for entities entering/leaving interest to hide culling pops at chunk boundaries.

Code Architecture
- Versioned message header: prepend msg type/version/hash to snapshot payloads for safer protocol evolution and clearer erroring on mismatch.
- Baseline-aware tests: GDScript tests covering serialize/deserialize round-trip, delta vs change-bit mask, and fuzzed entity sets to prevent regressions like the previous delta bug.
- Network harness: extend debug_test to simulate loss/duplication/reorder and log buffer occupancy and correction counts before playtests.
- Transport wrapper: isolate ENet setup/channels/RPC registration in a NetTransport helper shared by client/server to decouple transport from game logic.
- Telemetry HUD: surface bandwidth, seq, loss, jitter, buffer depth in an in-game overlay to tune rates/delays during sessions.
