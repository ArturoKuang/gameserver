# Collision Issue Root Cause Analysis
**Date:** 2025-11-22
**Status:** FIXED
**Severity:** MEDIUM

## Issue Description
Users reported that non-player entities in the game world appear to have "too big" collision boxes, causing players to collide with empty space around these entities or get stuck unexpectedly.

## Root Cause
The investigation identified two contributing factors:
1. **Misaligned Rotation:** "Moving Obstacles" (`AnimatableBody2D`) were not being rotated on the server, but were being rotated visually on the client (via client-side prediction). This caused the axis-aligned server collision box (Square) to mismatch the rotated visual sprite (Diamond), leading to "invisible corners" sticking out.
2. **Corner Snagging:** Standard NPCs (`CharacterBody2D`) used a `RectangleShape2D` (Square). When rotating (visually), the square corners would snag on walls or extend beyond the visual representation, causing perceived collision errors.

## Applied Fix
1. **Moving Obstacles:** Updated `scripts/server_world.gd` to rotate the `AnimatableBody2D` obstacles on the server to match their movement direction. Also enabled velocity metadata so the client can correctly predict the rotation.
2. **NPCs/Entities:** Changed `spawn_entity` to use `CircleShape2D` (Radius 8) instead of `RectangleShape2D` (16x16). This makes collision rotation-invariant and prevents corners from snagging or extending beyond the visual sprite, providing a much smoother gameplay experience.

## Verification
- Code changes applied to `scripts/server_world.gd`.
- Server startup verified with `testing/test.sh`.