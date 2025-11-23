# Implementation Plan: Network Debug Visualization

**Status:** Completed
**Date:** 2025-11-22
**Author:** Gemini Agent

## 1. Objective
To provide a visual method for debugging network synchronization issues, specifically:
1.  **Interpolation Lag:** Visualizing the difference between the currently rendered position and the actual server target position.
2.  **Prediction Errors:** Visualizing the discrepancy between the client-predicted local player position and the authoritative server position.

## 2. Architecture

### 2.1 Global Configuration
*   **File:** `scripts/network_config.gd`
*   **Mechanism:** A global boolean flag `DEBUG_VISUALIZATION` controllable via environment variables. This allows the visualization to be toggled without code changes or UI interactions in headless/automated environments.

### 2.2 State Tracking
*   **Remote Entities (`scripts/client_interpolator.gd`):**
    *   The `InterpolatedEntity` class will store a `target_position` vector.
    *   This vector is updated every time the interpolator processes a new snapshot interval (pointing to `to_state.position`).
*   **Local Player (`scripts/local_player.gd`):**
    *   The `LocalPlayer` class will store a `last_server_position` vector.
    *   This vector is updated inside the `reconcile()` function whenever a server update is received.

### 2.3 Rendering
*   **File:** `scripts/client_renderer.gd`
*   **Mechanism:** A new pass in `_process()` checks the debug flag.
*   **Visual Style:** "Ghost" sprites (wireframe or semi-transparent).
    *   **Red Ghost:** Represents the *Server Target* for remote entities. Shows where the entity is *going*.
    *   **Green Ghost:** Represents the *Server Authority* for the local player. Shows where the server thinks you *are*.

### 2.4 Automation Integration
*   **Files:** `testing/tools/test_framework.py`, `testing/tools/gemini_auto_debug.py`
*   **Mechanism:** A new command-line argument `--debug-vis` that sets the `DEBUG_VISUALIZATION=1` environment variable for the Godot process.

## 3. Implementation Steps

### Step 1: Configuration Setup
- [x] Add `DEBUG_VISUALIZATION` var to `scripts/network_config.gd`.
- [x] Update `scripts/test_automation.gd` to read `OS.get_environment("DEBUG_VISUALIZATION")`.

### Step 2: Data Plumbing
- [x] Modify `ClientInterpolator` to expose `to_state.position` as `target_position` on interpolated entities.
- [x] Modify `LocalPlayer` to expose `server_pos` as `last_server_position` during reconciliation.

### Step 3: Rendering Logic
- [x] Implement `_draw_debug_ghosts()` in `ClientRenderer`.
- [x] Create procedural textures (hollow squares) for the ghosts to avoid asset dependencies.
- [x] Integrate the draw call into the main render loop, guarded by the debug flag.

### Step 4: Tooling Update
- [x] Add `--debug-vis` argument to `test_framework.py`.
- [x] Ensure the environment variable is passed to the subprocess.
- [x] Update `gemini_auto_debug.py` to forward the flag.

## 4. Usage

To enable debug visualization during an automated test:

```bash
# Using the Python test framework directly
python3 testing/tools/test_framework.py --test basic --debug-vis

# Using the Gemini Auto-Debug wrapper
python3 testing/tools/gemini_auto_debug.py --test custom --mode random_walk --debug-vis

# Quick toggle via debug script
`tools/debug_test.sh` now exports `DEBUG_VISUALIZATION=1` by default for all launched
processes. Override with `DEBUG_VISUALIZATION=0` if you need to disable the overlay.
```

## 5. Future Improvements
-   **Snapshot History Trails:** Draw points for the last N snapshots to visualize the interpolation curve.
-   **Prediction Error Vectors:** Draw lines connecting the ghost to the real entity to visualize the magnitude of error.
-   **State Text:** Display text labels above ghosts showing sequence numbers or state flags.
