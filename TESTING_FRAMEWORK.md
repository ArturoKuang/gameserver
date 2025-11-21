# Testing Framework Documentation

## Overview

This project includes a comprehensive automated testing framework for validating the snapshot interpolation networking system. The framework can:

- Launch multiple server + client instances automatically
- Simulate various network conditions (lag, packet loss)
- Automate player movement patterns for testing
- Generate structured logs with timestamps
- Analyze logs and detect common issues
- Create Claude Code-friendly debug reports

## Quick Start

### Run a Basic Test

```bash
# Run a 30-second test with 1 client doing random movement
./test_framework.py --test basic

# Run stress test with rapid direction changes
./test_framework.py --test stress

# Test with simulated 10% packet loss
./test_framework.py --test packet_loss

# Test with 200ms lag
./test_framework.py --test lag

# Test with 3 clients simultaneously
./test_framework.py --test multi_client

# Run all tests
./test_framework.py --test all
```

### Analyze Test Results

```bash
# After running a test, analyze the logs
./analyze_test_logs.py test_logs/basic_single_client_20250116_120000

# Reports will be generated in test_reports/
# - analysis_report.json (machine-readable)
# - analysis_report.md (human-readable)
# - claude_debug_summary.md (Claude Code-friendly)
```

### Feed Results to Claude Code

```bash
# In Claude Code, use this prompt:
Claude, please read the file test_reports/claude_debug_summary.md
and analyze any issues found in the test run. Then read the
relevant log files to diagnose the root cause.
```

## Architecture

### 1. Test Framework (`test_framework.py`)

Python script that orchestrates testing:

**Main Components:**
- `TestConfig`: Defines test scenarios (duration, clients, network conditions)
- `GodotProcess`: Manages individual Godot instances (server/client)
- `TestFramework`: Orchestrates test execution and cleanup

**Environment Variables Set:**
- `TEST_MODE`: "server" or "client"
- `TEST_CLIENT_ID`: Unique ID for each client (0, 1, 2, ...)
- `TEST_BEHAVIOR`: Movement pattern (random_walk, stress_test, etc.)
- `TEST_PACKET_LOSS`: Packet loss rate (0.0 to 1.0)
- `TEST_LAG_MS`: Simulated lag in milliseconds

**Output:**
- Logs to `test_logs/<test_name>_<timestamp>/`
- JSON report with metrics
- Claude-friendly summary

### 2. Logger System (`scripts/logger.gd`)

Structured logging with timestamps and metadata:

```gdscript
# Usage examples:
Logger.info("SERVER", "Player spawned", {"player_id": 1, "pos": "(100,200)"})
Logger.warn("CLIENT", "Packet loss detected", {"expected_seq": 10, "got_seq": 12})
Logger.error("CLIENT", "Player entity missing", {"entity_id": 51})

# Specialized loggers:
Logger.log_snapshot_sent(peer_id, sequence, entity_count, byte_size, compression_ratio)
Logger.log_snapshot_received(sequence, entity_count, player_id, delay_ms)
Logger.log_chunk_change(entity_id, old_chunk, new_chunk, position)
```

**Log Format:**
```
[timestamp] [LEVEL] [CATEGORY] message | key=value key2=value2
[0.523] [INFO] [SERVER] Entity spawned | entity_id=1 pos=(100,200) peer_id=1
```

### 3. Test Automation (`scripts/test_automation.gd`)

Automated player movement patterns:

**Test Modes:**
- `RANDOM_WALK`: Random direction changes every 3 seconds
- `STRESS_TEST`: Rapid direction changes (0.5s interval), includes 180° turns
- `CHUNK_CROSSING`: Deliberately moves between chunks to test interest management
- `CIRCLE_PATTERN`: Smooth circular movement
- `FIGURE_EIGHT`: Figure-8 pattern (tests complex interpolation)
- `COLLISION_TEST`: Moves toward walls to test collision handling

**Activation:**
Automatically activated when `TEST_BEHAVIOR` environment variable is set.

**Integration:**
```gdscript
# In game_client.gd, input is automatically replaced:
if TestAutomation.is_active():
    input_direction = TestAutomation.get_input_direction()
else:
    # Normal manual input
    input_direction = get_manual_input()
```

### 4. Network Simulator (`scripts/network_simulator.gd`)

Simulates poor network conditions:

**Features:**
- **Packet Loss**: Drop packets randomly (configurable rate)
- **Lag**: Delay packet delivery by N milliseconds
- **Jitter**: Add random variance to lag (±20% by default)

**Usage:**
```gdscript
# In game_client.gd:
if not NetworkSimulator.should_process_packet(snapshot.sequence):
    return  # Drop packet

# Or delay packet delivery:
NetworkSimulator.send_with_delay(data, callback, sequence)
```

**Configuration:**
Set via environment variables:
- `TEST_PACKET_LOSS`: 0.1 = 10% packet loss
- `TEST_LAG_MS`: 200 = 200ms delay

### 5. Log Analyzer (`analyze_test_logs.py`)

Parses structured logs and detects issues:

**Metrics Tracked:**
- Total errors/warnings
- Snapshots sent/received
- Packet loss events
- Baseline mismatches
- Player disappearances
- Interpolation warnings
- Chunk changes

**Issue Detection:**
- ❌ **Critical**: Player disappearances, zero snapshots, server crashes
- ⚠️ **Warnings**: High interpolation warnings, high baseline mismatches

**Output Reports:**
1. `analysis_report.json`: Machine-readable metrics
2. `analysis_report.md`: Human-readable summary
3. `claude_debug_summary.md`: Claude Code debugging guide

## Test Scenarios

### Basic Single Client
**Purpose**: Verify basic functionality
- 1 client, 30 seconds
- Random walk movement
- No network simulation

### Stress Test
**Purpose**: Test rapid state changes
- 1 client, 60 seconds
- Rapid direction changes (0.5s interval)
- Tests interpolation under stress

### High Lag Test
**Purpose**: Verify graceful degradation
- 1 client, 30 seconds
- 200ms simulated lag
- Tests interpolation buffer handling

### Packet Loss Test
**Purpose**: Verify resilience to packet loss
- 1 client, 30 seconds
- 10% packet loss
- Tests delta compression recovery

### Multi-Client Test
**Purpose**: Test server scalability
- 3 clients, 60 seconds
- Tests per-client snapshot sequences
- Tests interest management with multiple players

## Writing Custom Tests

### Create a New Test Scenario

Edit `test_framework.py` and add to the `tests` dictionary:

```python
tests = {
    # ... existing tests ...

    "my_custom_test": TestConfig(
        name="my_custom_test",
        num_clients=2,           # Number of clients
        duration=45,             # Test duration in seconds
        test_mode="circle_pattern",  # Movement pattern
        packet_loss=0.05,        # 5% packet loss
        lag_ms=100               # 100ms lag
    )
}
```

Run it:
```bash
./test_framework.py --test my_custom_test
```

### Add a New Movement Pattern

Edit `scripts/test_automation.gd` and add to the `TestMode` enum:

```gdscript
enum TestMode {
    # ... existing modes ...
    MY_CUSTOM_PATTERN
}

# In _process():
match current_mode:
    # ... existing cases ...
    TestMode.MY_CUSTOM_PATTERN:
        _update_my_custom_pattern(delta)

# Implement the pattern:
func _update_my_custom_pattern(delta: float):
    # Set current_direction based on your pattern
    current_direction = Vector2(cos(time), sin(time))
```

## Debugging with Claude Code

### Workflow

1. **Run a test:**
   ```bash
   ./test_framework.py --test stress
   ```

2. **Analyze logs:**
   ```bash
   ./analyze_test_logs.py test_logs/stress_test_20250116_120000
   ```

3. **Read the Claude summary:**
   ```bash
   cat test_reports/claude_debug_summary.md
   ```

4. **Ask Claude to investigate:**
   ```
   Claude, I ran a stress test and got player disappearances.
   Please read test_reports/claude_debug_summary.md and then
   analyze the logs in test_logs/stress_test_20250116_120000/
   to find the root cause.
   ```

5. **Claude will:**
   - Read the summary report
   - Identify which log files to examine
   - Parse the structured logs
   - Correlate events (e.g., chunk changes vs disappearances)
   - Suggest fixes with file paths and line numbers

### Example Claude Prompts

**For Player Disappearances:**
```
Claude, analyze player disappearance errors in test_logs/.../client_0.log
Focus on:
- Delta compression deserialization (entity_snapshot.gd)
- Interest management (server_world.gd)
- Snapshot sequence numbers
```

**For Performance Issues:**
```
Claude, analyze the network performance from the test logs.
Calculate:
- Average snapshot sizes
- Compression ratios
- Packet loss rates
- Interpolation buffer health
```

**For Multi-Client Issues:**
```
Claude, I'm seeing different behavior between clients.
Compare client_0.log and client_1.log and identify:
- Snapshot sequence differences
- Entity count differences
- Timing discrepancies
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Network Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Install Godot
        run: |
          wget https://downloads.tuxfamily.org/godotengine/4.3/Godot_v4.3-stable_linux.x86_64.zip
          unzip Godot_v4.3-stable_linux.x86_64.zip

      - name: Run Tests
        run: |
          ./test_framework.py --godot ./Godot_v4.3-stable_linux.x86_64 --test all

      - name: Analyze Results
        run: |
          ./analyze_test_logs.py test_logs/*/

      - name: Upload Reports
        uses: actions/upload-artifact@v2
        with:
          name: test-reports
          path: test_reports/
```

## Performance Benchmarks

### Expected Metrics (Basic Test)

- **Snapshots sent**: ~300 (10 Hz × 30 seconds)
- **Snapshots received**: ~300 (with <1% loss)
- **Average snapshot size**: 200-500 bytes (with delta compression)
- **Compression ratio**: 70-95% (depending on scene activity)
- **Interpolation warnings**: <5 (occasional buffer warnings are OK)
- **Player disappearances**: 0 (any value is a bug!)
- **Baseline mismatches**: <5% (UDP out-of-order packets)

### Warning Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Player Disappearances | >0 | >0 |
| Packet Loss | >5% | >20% |
| Interpolation Warnings | >20 | >100 |
| Baseline Mismatches | >10% | >30% |
| Avg Snapshot Size | >1000 bytes | >1400 bytes |

## Troubleshooting

### Test Won't Start

**Check:**
- Godot path is correct: `which godot` or check `/Applications/Godot.app/`
- Project path is correct: `pwd` should show project root
- No other Godot instances running: `pkill -9 Godot`

### Logs Are Empty

**Check:**
- Logger autoload is registered in `project.godot`
- Test mode environment variable is set (framework does this automatically)
- Log files are being written to correct directory

### Network Simulator Not Working

**Check:**
- NetworkSimulator autoload is registered
- Environment variables are set (`echo $TEST_PACKET_LOSS`)
- `NetworkSimulator.should_process_packet()` is called in client

### Test Automation Not Working

**Check:**
- TestAutomation autoload is registered
- `TEST_BEHAVIOR` environment variable is set
- `TestAutomation.is_active()` returns true
- Client is calling `TestAutomation.get_input_direction()`

## Advanced Topics

### Custom Log Analyzers

Extend `analyze_test_logs.py` to detect custom issues:

```python
def _detect_custom_issue(self):
    # Count specific event patterns
    rapid_chunk_changes = 0
    for entry in self.result.entries:
        if entry.category == "SERVER_CHUNK":
            rapid_chunk_changes += 1

    if rapid_chunk_changes > 100:
        self.result.warnings_list.append(
            "Player is changing chunks very rapidly (>100 times). "
            "Consider increasing CHUNK_SIZE."
        )
```

### Real-Time Log Monitoring

Use `tail -f` with structured log parsing:

```bash
# Monitor client logs in real-time
tail -f test_logs/*/client_0.log | grep ERROR

# Filter for specific issues
tail -f test_logs/*/client_0.log | grep "INTERPOLATOR.*WARNING"
```

### Performance Profiling

Add performance metrics to logs:

```gdscript
var start_time = Time.get_ticks_usec()
# ... do work ...
var elapsed = Time.get_ticks_usec() - start_time
Logger.debug("PERF", "Snapshot deserialization", {"time_us": elapsed})
```

Then analyze with custom script:

```python
# Extract all PERF logs
perf_entries = [e for e in entries if e.category == "PERF"]
avg_time = sum(float(e.metadata["time_us"]) for e in perf_entries) / len(perf_entries)
```

## Best Practices

1. **Run tests before committing**: Catch regressions early
2. **Test with multiple clients**: Server behavior changes with >1 client
3. **Test network conditions**: Real networks have lag and packet loss
4. **Analyze trends**: Compare test results over time
5. **Keep logs**: They're valuable for debugging later
6. **Use structured logging**: Makes analysis much easier
7. **Write custom analyzers**: Detect project-specific issues

## Files Reference

### Framework Files
- `test_framework.py` - Main test orchestration
- `analyze_test_logs.py` - Log analysis and reporting

### Godot Scripts
- `scripts/logger.gd` - Structured logging system
- `scripts/test_automation.gd` - Automated player movement
- `scripts/network_simulator.gd` - Network condition simulation

### Output Directories
- `test_logs/` - Raw log files from test runs
- `test_reports/` - Analysis reports (JSON, Markdown, Claude summaries)

### Documentation
- `TESTING_FRAMEWORK.md` - This file
- `CLAUDE.md` - Project-specific Claude Code instructions
- `DELTA_COMPRESSION_BUG.md` - Technical deep-dive on delta compression bug

## Support

For issues with the testing framework:
1. Check the troubleshooting section above
2. Review the example test scenarios
3. Ask Claude Code to analyze your logs
4. Check recent commits for breaking changes

## License

Same as the main project.
