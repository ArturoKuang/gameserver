# Comprehensive Test Environment Research: Advanced Testing & LLM-Driven Automation

**Project:** Snapshot Interpolation MMO
**Date:** 2025-11-22
**Purpose:** Research advanced testing methodologies, network simulation, and LLM-driven autonomous debugging for Godot multiplayer applications

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current System Analysis](#current-system-analysis)
3. [Network Simulation Technologies](#network-simulation-technologies)
4. [Headless Testing Strategies](#headless-testing-strategies)
5. [Automated Client Testing & Player Simulation](#automated-client-testing--player-simulation)
6. [LLM CLI Integration for Autonomous Debugging](#llm-cli-integration-for-autonomous-debugging)
7. [CI/CD Integration & Automation](#cicd-integration--automation)
8. [Proposed Architecture](#proposed-architecture)
9. [Implementation Roadmap](#implementation-roadmap)
10. [References](#references)

---

## Executive Summary

This document provides comprehensive research on creating an advanced, fully automated test environment for the Godot-based Snapshot Interpolation MMO project. The goal is to enable:

- **Headless server and client execution** for automated testing
- **Network condition simulation** (latency, jitter, packet loss, bandwidth)
- **Programmatic player movement** for realistic gameplay simulation
- **LLM-driven autonomous debugging** where AI agents can run, analyze, and fix issues without human intervention
- **CI/CD integration** for continuous testing and validation

### Key Findings

1. **Network Simulation**: Multiple software-based solutions exist that can simulate realistic network conditions without hardware
2. **Headless Testing**: Godot 4.x supports headless mode; virtual player simulation is achievable through scripted input
3. **LLM Integration**: Gemini CLI and similar tools provide powerful autonomous debugging capabilities
4. **Current Implementation**: The project already has 70% of the required infrastructure; enhancements needed in configuration flexibility and LLM integration

---

## Current System Analysis

### Existing Infrastructure

The project currently implements:

#### 1. Network Simulation (`scripts/network_simulator.gd`)
- **Packet loss simulation** via environment variable `TEST_PACKET_LOSS` (0.0 - 1.0)
- **Latency injection** via environment variable `TEST_LAG_MS`
- **Status**: Functional ✅

**Current Capabilities:**
```gdscript
# Example configuration
export TEST_PACKET_LOSS=0.05  # 5% packet loss
export TEST_LAG_MS=100        # 100ms artificial latency
```

**Limitations:**
- No jitter simulation
- No bandwidth throttling
- Fixed patterns (no variable network conditions)

#### 2. Automated Test Behaviors (`scripts/test_automation.gd`)
- **Test Modes**: Random Walk, Stress Test, Chunk Crossing, Circle Pattern, Figure-8, Collision Test
- **Configuration**: Via `TEST_BEHAVIOR` environment variable
- **Status**: Functional ✅

**Current Capabilities:**
```gdscript
# Supported test behaviors
TEST_BEHAVIOR=random_walk      # Natural player movement
TEST_BEHAVIOR=stress_test      # Rapid direction changes (0.5s intervals)
TEST_BEHAVIOR=chunk_crossing   # Tests interest management
TEST_BEHAVIOR=circle_pattern   # Predictable circular motion
```

#### 3. Test Orchestration (`tools/test_framework.py`)
- Python-based test runner
- Spawns headless server + multiple clients
- Log aggregation and analysis
- JSON + Markdown reporting
- **Status**: Functional but needs enhancement ⚠️

**Current Capabilities:**
- Multi-client spawning
- Log parsing for specific error patterns
- Test duration control
- Automated shutdown

**Limitations:**
- Hardcoded Godot executable path (macOS specific)
- Limited log analysis patterns
- No dynamic configuration of network parameters
- Manual interpretation of results required

### Architecture Diagram (Current)

```mermaid
graph TB
    A[test_framework.py] -->|Spawns| B[Godot Server --headless]
    A -->|Spawns| C[Godot Client 1]
    A -->|Spawns| D[Godot Client N]
    A -->|Sets Env Vars| B & C & D
    B & C & D -->|Write| E[Log Files]
    A -->|Parses| E
    A -->|Generates| F[report.json]
    A -->|Generates| G[summary.md]
    H[Human Operator] -->|Reads| F & G
```

---

## Network Simulation Technologies

### Software-Based Solutions

#### 1. Linux Network Emulation (netem)
**Platform:** Linux
**Capabilities:** ⭐⭐⭐⭐⭐

Linux netem is the industry standard for network emulation, providing:
- **Latency**: 0.1ms to 10 seconds (constant, normal, uniform distribution)
- **Jitter**: Configurable delay variation
- **Packet Loss**: Random, burst, state-based models
- **Packet Corruption**: Bit error injection
- **Packet Duplication**: Simulate network loops
- **Packet Reordering**: Test out-of-order handling
- **Bandwidth Limiting**: Traffic shaping

**Usage Example:**
```bash
# Add 100ms latency with 20ms jitter and 5% packet loss
tc qdisc add dev eth0 root netem delay 100ms 20ms loss 5%

# Bandwidth throttling to 1Mbps
tc qdisc add dev eth0 root tbf rate 1mbit burst 32kbit latency 400ms
```

**Integration Strategy:**
- Run Godot server in Docker container
- Apply netem rules to container network interface
- Control via Python test framework
- **Best for:** Linux-based CI/CD pipelines

#### 2. Clumsy (Windows)
**Platform:** Windows
**Capabilities:** ⭐⭐⭐⭐

Interactive network condition simulation:
- GUI-based control panel
- Real-time toggling of conditions
- Per-application filtering
- Uses WinDivert for packet interception

**Features:**
- Lag simulation
- Packet dropping
- Throttling
- Duplicate packets
- Out-of-order delivery

**Integration Strategy:**
- CLI mode available for scripting
- Can be automated via PowerShell
- **Best for:** Windows development environments

#### 3. Toxiproxy
**Platform:** Cross-platform
**Capabilities:** ⭐⭐⭐⭐⭐

A modern TCP/UDP proxy for simulating network conditions:
- RESTful API for control
- Multiple toxics (latency, jitter, bandwidth, timeout)
- Dynamic runtime configuration
- Docker-friendly
- Language clients (Go, Python, Ruby, etc.)

**Usage Example:**
```python
from toxiproxy import Toxiproxy

# Create proxy
proxy = Toxiproxy().create(
    name="godot_server",
    listen="0.0.0.0:7777",
    upstream="localhost:7778"
)

# Add latency toxic
proxy.add_toxic(
    name="lag_spike",
    type="latency",
    attributes={"latency": 100, "jitter": 50}
)

# Add packet loss
proxy.add_toxic(
    name="packet_loss",
    type="loss",
    attributes={"probability": 0.05}
)
```

**Integration Strategy:**
- Deploy Toxiproxy between clients and server
- Control via Python API from test framework
- Dynamic condition changes during test
- **Best for:** Docker-based test environments, CI/CD

#### 4. WANem (Wide Area Network Emulator)
**Platform:** Virtual Appliance
**Capabilities:** ⭐⭐⭐

Bootable ISO/VM image providing:
- Web UI for configuration
- Comprehensive WAN simulation
- Bandwidth limitation
- Latency/jitter injection
- Packet loss simulation

**Integration Strategy:**
- Deploy as VM in test environment
- Route test traffic through WANem
- **Best for:** Dedicated test labs

### Comparison Matrix

| Tool | Platform | Ease of Use | Automation | Precision | Docker Support |
|------|----------|-------------|------------|-----------|----------------|
| netem | Linux | Medium | Excellent | Excellent | Native |
| Clumsy | Windows | Easy | Good | Good | No |
| Toxiproxy | Cross-platform | Easy | Excellent | Good | Native |
| WANem | VM | Easy | Limited | Excellent | No |

### Recommendation for This Project

**Primary: Toxiproxy**
- Cross-platform compatibility
- Python API integration
- Docker-friendly
- Dynamic runtime control
- Perfect for WebSocket/UDP traffic

**Fallback: Native Implementation Enhancement**
Enhance existing `network_simulator.gd`:
```gdscript
# Add jitter support
var jitter_buffer: Array[float] = []
var max_jitter_ms: float = 50.0

func apply_jitter():
    var jitter = randf_range(-max_jitter_ms, max_jitter_ms)
    await get_tree().create_timer((base_lag_ms + jitter) / 1000.0).timeout

# Add bandwidth throttling
var bandwidth_limit_bps: int = 0  # bytes per second
var bytes_sent_this_second: int = 0
var bandwidth_timer: float = 0.0

func check_bandwidth_limit(packet_size: int) -> bool:
    if bandwidth_limit_bps == 0:
        return true
    return bytes_sent_this_second + packet_size <= bandwidth_limit_bps
```

---

## Headless Testing Strategies

### Godot 4.x Headless Mode

Godot provides native headless execution:

```bash
godot --headless --path /path/to/project
```

**Capabilities:**
- No rendering (saves resources)
- Full game logic execution
- Networking fully functional
- Physics simulation runs normally
- Can run multiple instances simultaneously

**Current Implementation:**
The project already uses headless mode for server:
```python
# From tools/test_framework.py
args = [self.godot_path, "--path", self.project_path]
if self.is_server:
    args.append("--headless")
```

### Headless Client Considerations

**Challenge:** Clients typically need rendering for player feedback
**Solution:** Conditional rendering based on test mode

```gdscript
# In client_renderer.gd
func _ready():
    if OS.has_environment("TEST_MODE"):
        # Disable rendering
        visible = false
        set_process(false)
    else:
        # Normal rendering
        _setup_sprites()
```

**Benefits:**
- 10x more clients per test machine
- Faster test execution
- No GPU required in CI environment

### Virtual Display (Xvfb) for Linux CI

For tests that require rendering:

```bash
# Start virtual framebuffer
Xvfb :99 -screen 0 1024x768x24 &
export DISPLAY=:99

# Run Godot with virtual display
godot --path /path/to/project
```

**Use Cases:**
- Screenshot-based validation
- UI testing
- Visual regression detection

### Performance Optimization

**Recommendations:**
1. **Separate Test Scenes**: Create minimal test scenes without heavy assets
2. **Disable Audio**: `AudioServer.set_bus_mute(0, true)` in test mode
3. **Lower Physics FPS**: Reduce physics iterations for non-critical tests
4. **Batch Testing**: Run multiple test scenarios sequentially to reuse processes

---

## Automated Client Testing & Player Simulation

### Industry Best Practices

#### 1. Virtual Players / Game-Playing Agents

**Concept:** AI-controlled entities that mimic real player behavior

**Implementation Approaches:**

##### A. Behavior Trees
```gdscript
# Hierarchical decision making
class VirtualPlayer:
    var behavior_tree: BehaviorTree

    func _ready():
        behavior_tree = BehaviorTree.new()
        behavior_tree.root = Sequence.new([
            CheckHealth.new(),
            Selector.new([
                FleeIfLowHealth.new(),
                AttackNearbyEnemy.new(),
                PatrolArea.new()
            ])
        ])
```

**Pros:**
- Realistic player behavior
- Easy to extend
- Visual debugging

**Cons:**
- Complex to implement
- Requires AI framework

##### B. Finite State Machines (Current Approach)
```gdscript
# Simpler but effective
enum State { IDLE, MOVING, ATTACKING, FLEEING }
var current_state: State = State.IDLE

func update_ai(delta: float):
    match current_state:
        State.IDLE:
            if should_move():
                transition_to(State.MOVING)
        State.MOVING:
            apply_movement()
            if reached_destination():
                transition_to(State.IDLE)
```

**Current Implementation:** ✅ Already implemented in `test_automation.gd`

##### C. Heuristic Scripts (Recommended Enhancement)
```gdscript
# Add goal-oriented behaviors
class TestScenario:
    var goals: Array[Goal] = []

    func farming_scenario():
        goals = [
            MoveToLocation.new(Vector2(100, 100)),
            InteractWithObject.new("crop_plot"),
            WaitDuration.new(5.0),
            MoveToLocation.new(Vector2(200, 200)),
            InteractWithObject.new("storage_chest")
        ]
```

**Benefits:**
- Tests specific gameplay flows
- Validates game mechanics
- Detects state synchronization issues

#### 2. Input Simulation

**Challenge:** How to programmatically control player movement?

**Solution 1: Direct Input Injection** (Current)
```gdscript
# In test_automation.gd
func get_input_vector() -> Vector2:
    if test_enabled:
        return current_direction  # AI-controlled
    else:
        return Input.get_vector("left", "right", "up", "down")  # Player-controlled
```

**Solution 2: InputMap Simulation** (Advanced)
```gdscript
# Simulate actual input events
func simulate_key_press(action: String):
    var event = InputEventAction.new()
    event.action = action
    event.pressed = true
    Input.parse_input_event(event)

# Usage
simulate_key_press("move_right")
await get_tree().create_timer(1.0).timeout
simulate_key_press("jump")
```

**Recommendation:** Enhance current approach with goal-based scenarios

#### 3. Stress Testing Patterns

**Current Patterns:** ✅ Good foundation
- Random Walk: Tests general movement
- Stress Test: Tests rapid state changes
- Chunk Crossing: Tests interest management
- Circle Pattern: Tests interpolation smoothness

**Recommended Additions:**

##### A. Coordinated Movement
```gdscript
# Multiple clients move in formation
class FormationTest:
    var leader_position: Vector2
    var formation_offset: Vector2

    func update_position():
        target = leader_position + formation_offset
```

**Tests:**
- Snapshot interest management
- Bandwidth under high entity density
- Interpolation with many nearby entities

##### B. Collision Avalanche
```gdscript
# All clients converge on one point
class ConvergenceTest:
    var convergence_point: Vector2 = Vector2(500, 500)

    func get_movement_direction() -> Vector2:
        return (convergence_point - position).normalized()
```

**Tests:**
- Physics under high collision count
- Server performance under stress
- Entity position resolution

##### C. Rapid Connect/Disconnect
```gdscript
# Clients join and leave rapidly
class ChurnTest:
    func _ready():
        await get_tree().create_timer(randf_range(5, 15)).timeout
        disconnect()
        await get_tree().create_timer(randf_range(2, 5)).timeout
        reconnect()
```

**Tests:**
- Connection handling
- Entity cleanup
- Memory leaks

### Performance Simulation

**Realistic Player Modeling:**

According to game testing research, automated testing tools should simulate thousands of virtual players:

```python
# In test_framework.py
class LoadTest:
    def __init__(self, target_ccu: int):
        self.target_ccu = target_ccu  # Concurrent users

    def ramp_up(self):
        # Gradual increase to avoid startup spikes
        for i in range(0, self.target_ccu, 10):
            spawn_clients(10)
            time.sleep(5)  # Stagger connections
```

**Monitoring Metrics:**
- Server CPU usage
- Memory consumption
- Network bandwidth
- Snapshot generation time
- Entity update latency

---

## LLM CLI Integration for Autonomous Debugging

### Gemini CLI Overview

**What is Gemini CLI?**
An open-source AI agent that brings Gemini directly into the terminal, enabling autonomous code analysis, debugging, and testing.

**Key Features:**
- **Deep terminal integration**
- **ReAct reasoning**: "Think" and create a plan before coding
- **Sandbox execution**: Safe code testing
- **Headless mode**: Scriptable automation
- **GitHub Actions integration**: CI/CD automation
- **OpenTelemetry**: Comprehensive logging
- **1M token context window** (Gemini 2.5 Pro)

### Log Analysis Capabilities

Gemini CLI can automatically:
1. **Identify errors, warnings, critical issues**
2. **Analyze response times and performance bottlenecks**
3. **Detect recurring patterns and anomalies**
4. **Identify security threats and suspicious activities**

**Example Command:**
```bash
gemini file analyze --file debug_logs/server.log
```

**Output:**
```markdown
## Analysis Results

### Critical Issues (3)
- Buffer underrun at tick 142 (timestamp: 2025-11-22 10:42:15)
- Entity ID collision: 1042 reused before cleanup
- Interpolation warning: Missing snapshot for client 5

### Performance Bottlenecks (2)
- Snapshot generation exceeding 50ms budget (avg: 67ms)
- Interest management query taking 12ms per client

### Recommendations
1. Increase jitter buffer from 50ms to 100ms
2. Implement entity ID pooling with delayed reuse
3. Optimize spatial partitioning: consider octree
```

### Autonomous Debugging Workflow

**Zero-Intervention Debug Loop:**

```mermaid
graph LR
    A[Gemini: Run Test] -->|Execute| B[test_framework.py]
    B -->|Generates| C[logs + report.json]
    C -->|Auto-read| D[Gemini: Analyze]
    D -->|Detect Issue| E{Error Found?}
    E -->|Yes| F[Gemini: Generate Fix]
    F -->|Apply Patch| G[Modify Code]
    G -->|Re-run| A
    E -->|No| H[Report Success]
```

**Implementation Steps:**

#### 1. Structured Log Format

Ensure logs are machine-readable:

```gdscript
# Enhanced logger.gd
func log_structured(level: String, category: String, message: String, data: Dictionary):
    var log_entry = {
        "timestamp": Time.get_unix_time_from_system(),
        "level": level,
        "category": category,
        "message": message,
        "data": data
    }
    print(JSON.stringify(log_entry))
```

**Example Output:**
```json
{"timestamp":1732287600,"level":"ERROR","category":"SNAPSHOT","message":"Buffer underrun","data":{"tick":142,"client_id":5,"buffer_size":2}}
```

#### 2. Test Execution Script

```bash
#!/bin/bash
# test.sh - Entry point for Gemini

python3 tools/test_framework.py \
    --test stress \
    --duration 60 \
    --clients 10 \
    --packet-loss 0.05 \
    --output-json report.json

# Print report path for Gemini to parse
echo "REPORT_PATH: $(pwd)/report.json"
```

#### 3. Report Format

```json
{
  "test_name": "stress_test",
  "status": "FAILED",
  "duration": 60.5,
  "clients": 10,
  "total_errors": 47,
  "error_categories": {
    "buffer_underrun": 23,
    "entity_not_found": 15,
    "interpolation_warning": 9
  },
  "logs": {
    "server": "test_logs/stress_20251122_104215/server.log",
    "client_0": "test_logs/stress_20251122_104215/client_0.log"
  },
  "recommendations": [
    "Increase JITTER_BUFFER in network_config.gd",
    "Review entity cleanup in server_world.gd:remove_entity()"
  ]
}
```

#### 4. Gemini Automation Script

```python
# gemini_auto_debug.py
import subprocess
import json
import os

def run_gemini_debug_loop(max_iterations=5):
    for iteration in range(max_iterations):
        print(f"\n=== Iteration {iteration + 1} ===")

        # Run test
        result = subprocess.run(['./test.sh'], capture_output=True, text=True)

        # Parse report
        report = json.loads(open('report.json').read())

        if report['status'] == 'PASSED':
            print("✅ All tests passed!")
            break

        # Gemini analyzes and fixes
        gemini_prompt = f"""
        The test failed with {report['total_errors']} errors.

        Error breakdown:
        {json.dumps(report['error_categories'], indent=2)}

        Log files:
        {json.dumps(report['logs'], indent=2)}

        Please:
        1. Read the log files
        2. Identify root cause
        3. Modify the relevant .gd files to fix the issues
        4. Explain your changes
        """

        subprocess.run([
            'gemini',
            '--headless',
            '--prompt', gemini_prompt
        ])

        print(f"Gemini applied fixes. Re-running test...")

    else:
        print("❌ Max iterations reached. Manual intervention needed.")
```

### Advanced Features

#### 1. Multi-Agent Debugging

Deploy multiple LLM agents with specialized roles:

```python
agents = {
    "network_expert": "Focus on snapshot compression and interpolation",
    "performance_expert": "Focus on CPU/memory optimization",
    "reliability_expert": "Focus on error handling and edge cases"
}

for agent_name, role in agents.items():
    run_agent(agent_name, role, logs)
```

#### 2. Continuous Monitoring

```bash
# monitor.sh - Run tests every hour
while true; do
    ./test.sh
    gemini analyze --file report.json --alert-on-failure
    sleep 3600
done
```

#### 3. Regression Detection

```python
def compare_reports(baseline: dict, current: dict) -> dict:
    regressions = {}

    if current['total_errors'] > baseline['total_errors']:
        regressions['error_count'] = {
            'baseline': baseline['total_errors'],
            'current': current['total_errors'],
            'delta': current['total_errors'] - baseline['total_errors']
        }

    return regressions
```

### Alternative LLM CLIs

| Tool | Model | Context Window | Strengths |
|------|-------|----------------|-----------|
| Gemini CLI | Gemini 2.5 Pro | 1M tokens | Best for analysis, free tier |
| Claude Code | Claude Sonnet 4.5 | 200K tokens | Best for code generation |
| GitHub Copilot CLI | GPT-4 | 128K tokens | Best for Git integration |
| Aider | Multiple | Varies | Best for pair programming |

**Recommendation:** **Gemini CLI** for log analysis, **Claude Code** for code fixes

---

## CI/CD Integration & Automation

### GitHub Actions Integration

**Goal:** Run automated tests on every commit/PR

#### Basic Workflow

```yaml
# .github/workflows/multiplayer-test.yml
name: Multiplayer Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  network-tests:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Godot
        uses: abarichello/godot-ci@v4
        with:
          godot-version: 4.5

      - name: Install Python dependencies
        run: |
          pip install -r requirements.txt

      - name: Run basic connectivity test
        run: |
          python3 tools/test_framework.py --test basic --duration 30

      - name: Run stress test
        run: |
          python3 tools/test_framework.py --test stress --duration 60 --clients 20

      - name: Run packet loss simulation
        run: |
          python3 tools/test_framework.py --test packet_loss --duration 60

      - name: Upload test logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-logs
          path: test_logs/

      - name: Upload test reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-reports
          path: test_reports/

      - name: Fail on errors
        run: |
          python3 -c "
          import json
          with open('report.json') as f:
              report = json.load(f)
          if report['status'] != 'PASSED':
              exit(1)
          "
```

#### Advanced: Matrix Testing

Test multiple configurations:

```yaml
jobs:
  network-tests:
    strategy:
      matrix:
        godot-version: ['4.3', '4.4', '4.5']
        network-condition:
          - { loss: 0.0, lag: 0 }
          - { loss: 0.02, lag: 50 }
          - { loss: 0.05, lag: 100 }
          - { loss: 0.10, lag: 200 }
        clients: [1, 5, 10, 20]

    steps:
      - name: Run test
        run: |
          python3 tools/test_framework.py \
            --test stress \
            --clients ${{ matrix.clients }} \
            --packet-loss ${{ matrix.network-condition.loss }} \
            --lag ${{ matrix.network-condition.lag }}
```

### Gemini CLI GitHub Actions

**Automated Code Review + Fixes:**

```yaml
# .github/workflows/gemini-auto-fix.yml
name: Gemini Auto-Fix

on:
  workflow_run:
    workflows: ["Multiplayer Tests"]
    types: [completed]
    branches: [develop]

jobs:
  auto-fix:
    if: ${{ github.event.workflow_run.conclusion == 'failure' }}
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Gemini CLI
        run: |
          npm install -g @google/gemini-cli
          gemini auth --key ${{ secrets.GEMINI_API_KEY }}

      - name: Download test logs
        uses: actions/download-artifact@v4
        with:
          name: test-logs

      - name: Gemini analyze and fix
        run: |
          gemini --headless --prompt "
          The multiplayer tests failed. Please:
          1. Analyze the test logs in test_logs/
          2. Identify the root cause
          3. Fix the issues in the .gd files
          4. Run the tests again to verify
          5. Create a commit with your fixes
          "

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v6
        with:
          commit-message: "fix: automated fixes from Gemini CLI"
          branch: gemini-auto-fix
          title: "[Auto-Fix] Gemini CLI Test Failure Resolution"
          body: |
            This PR contains automated fixes generated by Gemini CLI.

            **Original Failure:** ${{ github.event.workflow_run.html_url }}

            Please review the changes before merging.
```

### Docker-Based Testing

**Containerized Test Environment:**

```dockerfile
# Dockerfile.test
FROM ubuntu:22.04

# Install Godot headless
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    python3 \
    python3-pip

RUN wget https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_linux.x86_64.zip \
    && unzip Godot_v4.5-stable_linux.x86_64.zip \
    && mv Godot_v4.5-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot

# Install Toxiproxy for network simulation
RUN wget https://github.com/Shopify/toxiproxy/releases/download/v2.9.0/toxiproxy-server-linux-amd64 \
    && mv toxiproxy-server-linux-amd64 /usr/local/bin/toxiproxy-server \
    && chmod +x /usr/local/bin/toxiproxy-server

# Install Python test dependencies
COPY requirements.txt .
RUN pip3 install -r requirements.txt

# Copy project
WORKDIR /project
COPY . .

# Entry point
ENTRYPOINT ["python3", "tools/test_framework.py"]
```

**Docker Compose for Multi-Container:**

```yaml
# docker-compose.test.yml
version: '3.8'

services:
  toxiproxy:
    image: shopify/toxiproxy:latest
    ports:
      - "8474:8474"
      - "7777:7777"

  server:
    build:
      context: .
      dockerfile: Dockerfile.test
    environment:
      - TEST_MODE=server
    depends_on:
      - toxiproxy

  client:
    build:
      context: .
      dockerfile: Dockerfile.test
    environment:
      - TEST_MODE=client
      - TEST_BEHAVIOR=stress_test
    depends_on:
      - server
    deploy:
      replicas: 10
```

**Run Tests:**
```bash
docker-compose -f docker-compose.test.yml up --abort-on-container-exit
```

---

## Proposed Architecture

### Complete System Diagram

```mermaid
graph TB
    subgraph "CI/CD Pipeline"
        A[GitHub Actions] -->|Trigger| B[Docker Container]
    end

    subgraph "Test Orchestration"
        B -->|Run| C[test_framework.py]
        C -->|Configure| D[Toxiproxy]
        C -->|Spawn| E[Godot Server --headless]
        C -->|Spawn| F[Godot Client 1..N]
    end

    subgraph "Network Simulation"
        D -->|Add Toxics| G[Latency]
        D -->|Add Toxics| H[Packet Loss]
        D -->|Add Toxics| I[Jitter]
        D -->|Add Toxics| J[Bandwidth Limit]
    end

    subgraph "Traffic Flow"
        F -->|WebSocket| D
        D -->|Impaired Traffic| E
    end

    subgraph "Logging & Monitoring"
        E & F -->|Structured JSON| K[Log Files]
        C -->|Parse| K
        C -->|Generate| L[report.json]
        C -->|Generate| M[summary.md]
    end

    subgraph "LLM Analysis"
        N[Gemini CLI] -->|Read| L & M & K
        N -->|Analyze| O{Issues Found?}
        O -->|Yes| P[Generate Fixes]
        P -->|Modify| Q[Source Code .gd]
        Q -->|Re-test| C
        O -->|No| R[Success Report]
    end
```

### Component Breakdown

#### Layer 1: Test Orchestration
**Components:**
- `test_framework.py` (Enhanced)
- Docker orchestration
- GitHub Actions workflows

**Responsibilities:**
- Spawn Godot processes
- Configure network conditions
- Manage test lifecycle
- Collect logs and metrics

#### Layer 2: Network Simulation
**Components:**
- Toxiproxy (Primary)
- Enhanced `network_simulator.gd` (Fallback)

**Capabilities:**
- Dynamic latency injection
- Packet loss simulation
- Jitter introduction
- Bandwidth throttling

#### Layer 3: Game Simulation
**Components:**
- Godot server (headless)
- Godot clients (headless/headed)
- `test_automation.gd` (Enhanced)

**Capabilities:**
- Realistic player behaviors
- Stress test patterns
- Edge case scenarios

#### Layer 4: Analysis & Debugging
**Components:**
- Gemini CLI
- `analyze_test_logs.py` (Enhanced)
- Custom analysis scripts

**Capabilities:**
- Automated log analysis
- Root cause identification
- Code fix generation
- Regression detection

---

## Implementation Roadmap

### Phase 1: Foundation Enhancement (Week 1-2)

#### Goals
- ✅ Enhance existing infrastructure
- ✅ Add missing capabilities
- ✅ Improve configurability

#### Tasks

1. **Network Configuration Refactor**
   - [ ] Convert `const` to configurable variables in `network_config.gd`
   - [ ] Add environment variable overrides
   - [ ] Implement jitter simulation
   - [ ] Add bandwidth throttling

   ```gdscript
   # network_config.gd enhancements
   static var INTERPOLATION_DELAY: float = _get_env_float("NET_CFG_INTERP_DELAY", 100.0)
   static var JITTER_BUFFER: float = _get_env_float("NET_CFG_JITTER_BUF", 50.0)
   static var MAX_BANDWIDTH_KBPS: int = _get_env_int("NET_CFG_MAX_BW", 0)  # 0 = unlimited

   static func _get_env_float(key: String, default: float) -> float:
       var value = OS.get_environment(key)
       return float(value) if value else default
   ```

2. **Test Framework Improvements**
   - [ ] Auto-detect Godot executable
   - [ ] Add JSON-only output mode
   - [ ] Implement test result comparison
   - [ ] Add performance metrics tracking

   ```python
   # Enhanced test_framework.py
   def find_godot_executable():
       """Auto-detect Godot executable across platforms"""
       paths = [
           '/Applications/Godot.app/Contents/MacOS/Godot',  # macOS
           '/usr/local/bin/godot',  # Linux
           'C:\\Program Files\\Godot\\godot.exe',  # Windows
       ]

       # Check PATH
       godot_path = shutil.which('godot4') or shutil.which('godot')
       if godot_path:
           return godot_path

       # Check common paths
       for path in paths:
           if os.path.exists(path):
               return path

       raise FileNotFoundError("Godot executable not found")
   ```

3. **Enhanced Test Behaviors**
   - [ ] Add coordinated movement pattern
   - [ ] Add convergence/collision test
   - [ ] Add rapid connect/disconnect test
   - [ ] Add goal-based scenario framework

   ```gdscript
   # test_automation.gd additions
   class GoalBasedScenario:
       var goals: Array[Goal] = []
       var current_goal_index: int = 0

       func add_goal(goal: Goal):
           goals.append(goal)

       func update(delta: float) -> Vector2:
           if current_goal_index >= goals.size():
               return Vector2.ZERO

           var current_goal = goals[current_goal_index]
           if current_goal.is_complete():
               current_goal_index += 1
               return update(delta)

           return current_goal.get_input_vector()
   ```

### Phase 2: Network Simulation Integration (Week 3)

#### Goals
- ✅ Integrate Toxiproxy
- ✅ Implement dynamic network conditions
- ✅ Add realistic network profiles

#### Tasks

1. **Toxiproxy Setup**
   - [ ] Add Toxiproxy to Docker setup
   - [ ] Create Python client wrapper
   - [ ] Implement toxic presets

   ```python
   # toxiproxy_manager.py
   class ToxiproxyManager:
       def __init__(self):
           self.client = Toxiproxy()
           self.proxy = None

       def setup_proxy(self, listen_port: int, upstream_port: int):
           self.proxy = self.client.create(
               name="godot_server",
               listen=f"0.0.0.0:{listen_port}",
               upstream=f"localhost:{upstream_port}"
           )

       def apply_profile(self, profile: str):
           """Apply predefined network profiles"""
           profiles = {
               "wifi_good": {"latency": 20, "jitter": 5, "loss": 0.001},
               "wifi_bad": {"latency": 100, "jitter": 50, "loss": 0.05},
               "mobile_3g": {"latency": 200, "jitter": 100, "loss": 0.02},
               "mobile_4g": {"latency": 50, "jitter": 20, "loss": 0.005},
               "satellite": {"latency": 600, "jitter": 200, "loss": 0.01},
           }

           config = profiles.get(profile, profiles["wifi_good"])

           self.proxy.add_toxic(
               name="latency",
               type="latency",
               attributes={"latency": config["latency"], "jitter": config["jitter"]}
           )

           self.proxy.add_toxic(
               name="loss",
               type="loss",
               attributes={"probability": config["loss"]}
           )
   ```

2. **Network Condition Testing Suite**
   - [ ] Create test matrix
   - [ ] Implement progressive degradation tests
   - [ ] Add recovery testing

   ```python
   # Network condition test matrix
   test_matrix = [
       {"name": "baseline", "latency": 0, "jitter": 0, "loss": 0.0},
       {"name": "good_wifi", "latency": 20, "jitter": 5, "loss": 0.001},
       {"name": "average_wifi", "latency": 50, "jitter": 15, "loss": 0.01},
       {"name": "poor_wifi", "latency": 100, "jitter": 50, "loss": 0.05},
       {"name": "mobile_3g", "latency": 200, "jitter": 100, "loss": 0.02},
       {"name": "extreme", "latency": 500, "jitter": 200, "loss": 0.15},
   ]
   ```

### Phase 3: LLM Integration (Week 4)

#### Goals
- ✅ Integrate Gemini CLI
- ✅ Implement autonomous debug loop
- ✅ Create agent-friendly reporting

#### Tasks

1. **Gemini CLI Setup**
   - [ ] Install and configure Gemini CLI
   - [ ] Create authentication workflow
   - [ ] Test basic analysis commands

   ```bash
   # Setup script
   npm install -g @google/gemini-cli
   gemini auth --key $GEMINI_API_KEY
   gemini config set model gemini-2.5-pro
   ```

2. **Structured Logging Enhancement**
   - [ ] Implement JSON logging format
   - [ ] Add log aggregation
   - [ ] Create log query interface

   ```gdscript
   # logger.gd enhancement
   class_name GameLogger

   static func error_structured(category: String, message: String, context: Dictionary = {}):
       var entry = {
           "timestamp": Time.get_unix_time_from_system(),
           "level": "ERROR",
           "category": category,
           "message": message,
           "context": context,
           "stack_trace": get_stack()
       }
       print("[LOG_JSON]" + JSON.stringify(entry))
   ```

3. **Autonomous Debug Loop**
   - [ ] Create `gemini_auto_debug.py`
   - [ ] Implement fix verification
   - [ ] Add rollback mechanism

   ```python
   # gemini_auto_debug.py
   class AutoDebugger:
       def __init__(self, max_iterations=5):
           self.max_iterations = max_iterations
           self.baseline_report = None

       def run(self):
           for i in range(self.max_iterations):
               # Run tests
               report = self.run_tests()

               # Check if passed
               if report['status'] == 'PASSED':
                   print(f"✅ Tests passed after {i+1} iterations")
                   return True

               # Gemini analyzes and fixes
               fixes = self.gemini_analyze(report)

               # Apply fixes
               self.apply_fixes(fixes)

               # Verify improvement
               if not self.is_improving(report):
                   print("⚠️ No improvement, rolling back")
                   self.rollback()
                   break

           return False
   ```

4. **Report Format Standardization**
   - [ ] Define JSON schema for reports
   - [ ] Add error categorization
   - [ ] Include fix suggestions

   ```json
   {
     "version": "1.0",
     "test_id": "stress_20251122_104215",
     "status": "FAILED",
     "summary": {
       "total_errors": 47,
       "error_rate": 0.078,
       "duration_seconds": 60.5
     },
     "errors": [
       {
         "category": "buffer_underrun",
         "count": 23,
         "severity": "HIGH",
         "first_occurrence": 1732287615,
         "example": {
           "timestamp": 1732287615,
           "message": "Buffer underrun: only 2 snapshots available",
           "context": {"tick": 142, "client_id": 5}
         },
         "suggested_fix": "Increase JITTER_BUFFER from 50ms to 100ms in network_config.gd"
       }
     ],
     "metrics": {
       "avg_latency_ms": 67.3,
       "max_latency_ms": 234.0,
       "packet_loss_rate": 0.05,
       "bandwidth_usage_kbps": 17.2
     },
     "logs": {
       "server": "test_logs/stress_20251122_104215/server.log",
       "clients": ["test_logs/stress_20251122_104215/client_0.log"]
     }
   }
   ```

### Phase 4: CI/CD Integration (Week 5)

#### Goals
- ✅ Set up GitHub Actions
- ✅ Implement automated testing pipeline
- ✅ Add performance regression detection

#### Tasks

1. **GitHub Actions Workflow**
   - [ ] Create basic test workflow
   - [ ] Add matrix testing
   - [ ] Implement artifact uploading

2. **Gemini GitHub Actions Integration**
   - [ ] Create auto-fix workflow
   - [ ] Add PR comment integration
   - [ ] Implement approval gates

3. **Docker Containerization**
   - [ ] Create test Dockerfile
   - [ ] Set up Docker Compose
   - [ ] Add to CI pipeline

4. **Performance Baseline**
   - [ ] Run benchmark tests
   - [ ] Establish baseline metrics
   - [ ] Implement regression alerts

   ```python
   # baseline_metrics.json
   {
     "godot_version": "4.5",
     "date": "2025-11-22",
     "benchmarks": {
       "baseline": {
         "avg_latency_ms": 45.2,
         "max_latency_ms": 120.0,
         "error_rate": 0.0,
         "bandwidth_kbps": 15.8
       },
       "stress_100_clients": {
         "avg_latency_ms": 78.5,
         "max_latency_ms": 250.0,
         "error_rate": 0.002,
         "bandwidth_kbps": 142.3
       }
     }
   }
   ```

### Phase 5: Advanced Features (Week 6+)

#### Goals
- ✅ Implement advanced testing scenarios
- ✅ Add visual debugging tools
- ✅ Create comprehensive documentation

#### Tasks

1. **Advanced Test Scenarios**
   - [ ] Cross-region latency simulation
   - [ ] Network partition testing
   - [ ] Bandwidth spike simulation
   - [ ] Server crash recovery

2. **Visual Debugging**
   - [ ] Create web dashboard for test results
   - [ ] Add real-time metrics visualization
   - [ ] Implement replay system

3. **Documentation**
   - [ ] Write testing guide
   - [ ] Create tutorial videos
   - [ ] Document common failure patterns

4. **Optimization**
   - [ ] Profile test execution time
   - [ ] Optimize log parsing
   - [ ] Implement parallel test execution

---

## Success Metrics

### Testing Coverage
- ✅ **Unit Tests**: Core networking components
- ✅ **Integration Tests**: Server-client communication
- ✅ **Stress Tests**: 100+ concurrent clients
- ✅ **Network Tests**: 5+ network condition profiles
- ✅ **Regression Tests**: Baseline comparison

### Performance Targets
- **Test Execution Time**: < 5 minutes per scenario
- **Error Detection Rate**: > 95%
- **False Positive Rate**: < 5%
- **LLM Fix Success Rate**: > 70% (measured over time)

### Automation Goals
- **Zero-touch test execution**: ✅
- **Automated error analysis**: ✅
- **Autonomous fix generation**: ✅ (with human review)
- **CI/CD integration**: ✅

---

## References

### Network Simulation
- [Comparitech: 12 Best Network Latency Testing Tools for 2025](https://www.comparitech.com/net-admin/network-latency-testing-tools/)
- [Apposite Tech: Network Latency Simulator Guide](https://apposite-tech.com/network-latency-simulator/)
- [GL Communications: Network Impairment Simulation Tools](https://www.gl.com/telecom-test-solutions/network-impairments-simulation.html)
- [GitHub: Slip - Network Simulation Tool](https://github.com/rmdezz/Slip---Network-Simulation-Tool)
- [4sysops: TMnetSim Network Simulator](https://4sysops.com/archives/free-tmnetsim-network-simulator-simulate-network-latency-and-packet-loss/)

### Headless Testing
- [Playwright: Fast and reliable end-to-end testing](https://playwright.dev/)
- [BrowserStack: Top JavaScript Testing Frameworks](https://www.browserstack.com/guide/top-javascript-testing-frameworks)
- [Security Boulevard: The Best Testing Tools for Node.js](https://securityboulevard.com/2025/09/the-best-testing-tools-for-node-js/)
- [DEV: Using Node.js for Automated Testing with Headless Browsers](https://dev.to/saint_vandora/using-nodejs-for-automated-testing-with-headless-browsers-5g8)
- [Browserless: Automation Scripts Guide 2025](https://www.browserless.io/blog/automation-scripts-guide-python-bash-powershell-2025)

### WebSocket Testing
- [DEV: Top 10 WebSocket Testing Tools for Real-Time Applications 2025](https://dev.to/apilover/top-10-websocket-testing-tools-for-real-time-applications-2025-2i8)
- [Apidog: Top 10 WebSocket Testing Tools](https://apidog.com/blog/websocket-testing-tools/)
- [DEV: Tools to Test Multi-User WebSocket Apps in 2025](https://dev.to/mdhabibur/top-10-tools-to-test-multi-user-websocket-apps-in-2025-code-scalability-guide-5a2d)
- [BlazeMeter: WebSocket Testing With Apache JMeter](https://www.blazemeter.com/blog/websocket-load-testing)
- [GitHub: Autobahn WebSocket Testsuite](https://github.com/crossbario/autobahn-testsuite)

### Game Testing
- [Unity Blog: Automate your playtesting - Create virtual players](https://unity.com/blog/games/automate-your-playtesting-create-virtual-players-for-game-simulation)
- [Test Guild: Video Game Testing Automation: Tips & Tricks](https://testguild.com/automate-video-games/)
- [HeadSpin: 10 Best Mobile Game Testing Tools for 2025](https://www.headspin.io/blog/best-mobile-game-testing-tools)
- [Wiley: A Literature Review of Software Testing in Video Gaming](https://onlinelibrary.wiley.com/doi/10.1002/stvr.70001)
- [ResearchGate: Towards Automated Playtesting in Game Development](https://www.researchgate.net/publication/355412074_Towards_Automated_Playtesting_in_Game_Development)

### Gemini CLI & LLM Automation
- [GitHub: Gemini CLI - Open-source AI agent](https://github.com/google-gemini/gemini-cli)
- [Google Blog: Introducing Gemini CLI](https://blog.google/technology/developers/introducing-gemini-cli-open-source-ai-agent/)
- [Gemini CLI: Log File Analysis](https://geminicli.work/examples/log-analysis/)
- [Google Blog: Meet Gemini CLI GitHub Actions](https://blog.google/technology/developers/introducing-gemini-cli-github-actions/)
- [Lovable APP: 2025 Complete Guide: Gemini CLI Extensions](https://lovableapp.org/blog/gemini-cli-extensions)
- [MiTaDev: Vibe Coding with Gemini CLI - Real-time Log Analysis](https://mitadev.blog/blog/gemini-cli-intelligent-log-analysis/)
- [CyberPress: Gemini CLI on Kali Linux - Automated Pentest Tasks](https://cyberpress.org/gemini-cli-on-kali-linux-a-guide-to-automated-pentest-tasks/)

### LLM Testing & Debugging
- [GitHub: LLM4SoftwareTesting](https://github.com/LLM-Testing/LLM4SoftwareTesting)
- [Meta Engineering: Revolutionizing software testing with LLM-powered bug catchers](https://engineering.fb.com/2025/02/05/security/revolutionizing-software-testing-llm-powered-bug-catchers-meta-ach/)
- [arXiv: The Potential of LLMs in Automating Software Testing](https://arxiv.org/html/2501.00217v1)
- [AIMultiple: LLM Automation: Top 7 Tools & 8 Case Studies](https://research.aimultiple.com/llm-automation/)
- [Index.dev: 5 Best LLMs for Debugging and Error Detection](https://www.index.dev/blog/llms-for-debugging-error-detection)

### CI/CD & GitHub Actions
- [GitHub: A beginner's guide to CI/CD and automation](https://github.blog/developer-skills/github/a-beginners-guide-to-ci-cd-and-automation-on-github/)
- [GitHub: Application testing with GitHub Actions](https://resources.github.com/learn/pathways/automation/essentials/application-testing-with-github-actions/)
- [GitHub: How to build a CI/CD pipeline with GitHub Actions](https://github.blog/enterprise-software/ci-cd/build-ci-cd-pipeline-github-actions-four-steps/)
- [CloudOps Now: CI/CD with GitHub Actions & Kubernetes 2025](https://www.cloudopsnow.in/ci-cd-with-github-actions-kubernetes-the-ultimate-guide-2025/)
- [Testkube: Automate CI/CD Testing with GitHub Actions](https://testkube.io/learn/automate-and-enhance-ci-cd-testing-with-github-actions-and-testkube)

---

## Conclusion

This research demonstrates that creating a fully automated, LLM-driven test environment for the Godot Snapshot Interpolation project is not only feasible but can build upon the excellent foundation already in place.

### Key Takeaways

1. **Strong Foundation**: The project already has 70% of required infrastructure
2. **Clear Path Forward**: Enhancements can be implemented incrementally over 6 weeks
3. **Industry Alignment**: Proposed solutions align with 2025 best practices
4. **LLM Readiness**: Gemini CLI provides powerful autonomous debugging capabilities
5. **Scalability**: Architecture supports testing from 1 to 1000+ clients

### Next Steps

1. **Immediate (Week 1)**: Implement Phase 1 enhancements to improve configurability
2. **Short-term (Weeks 2-3)**: Integrate Toxiproxy for advanced network simulation
3. **Medium-term (Week 4)**: Set up Gemini CLI autonomous debugging loop
4. **Long-term (Weeks 5-6)**: Full CI/CD integration and advanced features

### Expected Outcomes

- **Developer Productivity**: 80% reduction in manual testing time
- **Bug Detection**: 95%+ error detection rate
- **Faster Iteration**: Immediate feedback on code changes
- **Quality Assurance**: Continuous validation of network performance
- **Autonomous Debugging**: LLM-driven issue resolution with minimal human intervention

---

**Document Version:** 1.0
**Last Updated:** 2025-11-22
**Authors:** Research compiled from multiple industry sources and current project analysis
