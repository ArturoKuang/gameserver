# Test Environment Research & Implementation Plan

## 1. Objective
Establish a robust, automated testing environment for the Godot-based multiplayer game. This environment must support:
-   Headless execution of Server and Client(s).
-   Simulation of network conditions (Latency, Jitter, Packet Loss).
-   Automated player movement/behaviors.
-   Log aggregation and analysis for AI agents (Gemini).
-   Zero-intervention execution and debugging.

## 2. Current Capabilities Analysis
The project already possesses a sophisticated testing foundation.

### 2.1. Existing Tools
*   **`scripts/network_simulator.gd`**:
    *   Internal simulation of packet loss, lag, and jitter.
    *   Controlled via Environment Variables: `TEST_PACKET_LOSS`, `TEST_LAG_MS`.
    *   *Status:* **Functional**.

*   **`scripts/test_automation.gd`**:
    *   Scripted client behaviors (Random Walk, Stress Test, Circle Pattern, etc.).
    *   Controlled via Environment Variable: `TEST_BEHAVIOR`.
    *   *Status:* **Functional**.

*   **`tools/test_framework.py`**:
    *   Python-based orchestrator.
    *   Spawns Server and Client processes.
    *   Manages logging to `debug_logs/` or `test_logs/`.
    *   Parses logs for specific error patterns (e.g., "Player entity ... NOT in snapshot").
    *   Generates a JSON report and a Markdown summary.
    *   *Status:* **Functional but requires configuration tweaks**.

### 2.2. Key Gaps
1.  **Hardcoded Configuration:** `scripts/network_config.gd` uses `const` for critical tuning parameters (`INTERPOLATION_DELAY`, `JITTER_BUFFER`). This prevents the test framework from dynamically testing different buffer strategies without modifying source code.
2.  **Path Hardcoding:** `tools/test_framework.py` defaults to a specific macOS path for Godot. This makes it brittle in diverse CI/CLI environments.
3.  **Agent Integration:** While it produces a "Claude-friendly" summary, we should standardize this to a "Agent-friendly" format (Markdown + JSON) that Gemini can ingest natively.

## 3. Implementation Plan

### 3.1. Architecture
The testing architecture follows this flow:

```mermaid
graph TD
    A[Gemini CLI] -->|Executes| B[tools/test_framework.py]
    B -->|Spawns| C[Godot Server (Headless)]
    B -->|Spawns| D[Godot Client 1 (Headless)]
    B -->|Spawns| E[Godot Client N (Headless)]
    B -->|Sets Env Vars| C & D & E
    C & D & E -->|Write| F[Log Files]
    B -->|Reads| F
    B -->|Generates| G[Report.json]
    B -->|Generates| H[Summary.md]
    A -->|Reads| G & H
```

### 3.2. Environment Variables Strategy
We will control the test environment entirely through Environment Variables passed by the Python framework:

| Variable | Purpose | Target |
| :--- | :--- | :--- |
| `TEST_MODE` | `server` or `client` | Main Scene |
| `TEST_BEHAVIOR` | `random_walk`, `circle_pattern`, etc. | `test_automation.gd` |
| `TEST_PACKET_LOSS` | Float (0.0 - 1.0) | `network_simulator.gd` |
| `TEST_LAG_MS` | Int (Milliseconds) | `network_simulator.gd` |
| `GODOT_PATH` | Path to executable | `test_framework.py` |
| `NET_CFG_INTERP_DELAY` | Float (Override `INTERPOLATION_DELAY`) | *New Requirement* |
| `NET_CFG_JITTER_BUF` | Float (Override `JITTER_BUFFER`) | *New Requirement* |

### 3.3. Proposed Enhancements

#### A. Dynamic Network Configuration
Modify `scripts/network_config.gd` to change `const` to `static var` (or regular `var` if autoload) and initialize them with values that can be overridden by `OS.get_environment()`.

#### B. Enhanced Test Framework (`test_framework.py`)
1.  **Auto-Discovery:** Improve Godot executable detection (check `PATH`, common alias `godot4`, `godot`).
2.  **JSON Output:** Ensure the script prints the *path* to the JSON report as the final line of stdout, enabling easy parsing by the calling agent.
3.  **CLI Command:** Register a simplified shell command (e.g., `./test.sh`) that wraps the python script for ease of use.

#### C. Log Analysis for Agents
The current regex-based analysis is good. We will refine the "Patterns" list to include the specific issues identified in the audit:
*   "Buffer Underrun"
*   "Death Spiral" (Repeated full snapshot requests)
*   "Z-Fighting" (Entity ID reuse/sorting issues)

## 4. "Zero-Intervention" Workflow for Gemini
To achieve the goal of "Gemini runs and debugs without human intervention":

1.  **Run:** Gemini executes `python3 tools/test_framework.py --test stress --json-out`
2.  **Analyze:** Gemini reads the `report.json` generated.
3.  **Diagnose:** If `report.json` indicates `failure` or `high_error_rate`:
    *   Gemini reads the referenced log files (e.g., `test_logs/<id>/client_0.log`).
    *   Gemini identifies the specific error (e.g., "Buffer underrun at tick 100").
4.  **Fix:** Gemini modifies `scripts/network_config.gd` (e.g., increases buffer).
5.  **Verify:** Gemini re-runs the test command.
6.  **Result:** Gemini reports "Fix verified: Error rate dropped to 0%".

## 5. Action Items
1.  **Refactor `network_config.gd`:** Convert constants to configurable variables.
2.  **Update `test_framework.py`:** Improve path handling and output formatting.
3.  **Create `test.sh`:** A simple entry point for the agent.
4.  **Verify:** Run a test cycle to ensure logs are generated and parsed correctly.
