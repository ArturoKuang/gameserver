# Collision Issue Root Cause Analysis
**Date:** 2025-11-22
**Status:** IDENTIFIED
**Severity:** MEDIUM

## Issue Description
Users reported that non-player entities in the game world appear to have "too big" collision boxes, causing players to collide with empty space around these entities or get stuck unexpectedly.

## Root Cause
The investigation identified that the issue stems from the `spawn_moving_obstacle` function in `scripts/server_world.gd`.

While standard NPCs are spawned with a `16x16` collision shape (matching their visual sprite), "Moving Obstacles" are hardcoded with a `64x64` collision shape, which is significantly larger than the standard entity size.

### Relevant Code Snippet
**File:** `scripts/server_world.gd`

```gdscript
func spawn_moving_obstacle(start_pos: Vector2, end_pos: Vector2, speed: float = 50.0) -> int:
    # ... (Entity creation logic) ...

    # Add collision shape
    var collision = CollisionShape2D.new()
    var shape = RectangleShape2D.new()
    shape.size = Vector2(64, 64)  # <--- ROOT CAUSE: Hardcoded 64x64 size
    collision.shape = shape
    body.add_child(collision)

    # ...
```

These obstacles are spawned by the `game_server.gd` during the `_ready()` phase, populating the world with these large invisible collision boxes if there is no corresponding visual asset of that size.

## Proposed Fix
Adjust the `Vector2(64, 64)` values in `scripts/server_world.gd` to a smaller size that better represents the intended obstacle size (likely `32x32` or `16x16` depending on the visual representation), or expose this size as a parameter to the `spawn_moving_obstacle` function.
