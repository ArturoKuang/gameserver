# Quick Start Guide

## 5-Minute Setup

### 1. Test the Game Manually

```bash
# Open in Godot
open /Applications/Godot.app
# Import this project (project.godot)
# Press F5 to run
# Click "Start Server" in one window
# Run again (F5), click "Start Client" in another window
# Use arrow keys to move
```

### 2. Run Automated Tests

```bash
# Basic 30-second test
./test_framework.py --test basic

# View results
cat test_reports/claude_debug_summary.md
```

### 3. Debug with Claude Code

```
Claude, please read test_reports/claude_debug_summary.md
and analyze any issues found.
```

---

## Testing Commands Cheat Sheet

```bash
# Run different test scenarios
./test_framework.py --test basic          # Basic functionality
./test_framework.py --test stress         # Rapid movements
./test_framework.py --test packet_loss    # 10% packet loss
./test_framework.py --test lag            # 200ms lag
./test_framework.py --test multi_client   # 3 clients
./test_framework.py --test all            # All tests

# Analyze logs
./analyze_test_logs.py test_logs/<test_name>_<timestamp>

# View reports
cat test_reports/claude_debug_summary.md
cat test_reports/analysis_report.md
```

---

## Common Issues & Fixes

### Player Disappears
**Symptom**: Player randomly vanishes from screen
**Cause**: Delta compression bug or interest management issue
**Fix**: Check `scripts/entity_snapshot.gd:167` - see `DELTA_COMPRESSION_BUG.md`

### Choppy Movement
**Symptom**: Jerky interpolation
**Cause**: Low interpolation buffer
**Fix**: Increase `INTERPOLATION_DELAY` in `scripts/network_config.gd`

### High Packet Loss
**Symptom**: Test reports >5% packet loss
**Cause**: Sequence number issues
**Fix**: Check per-client sequences in `scripts/server_world.gd:15`

---

## Project Structure

```
snapshot-interpolation/
├── scripts/                  # GDScript files
│   ├── network_config.gd    # Configuration constants
│   ├── server_world.gd      # Server simulation
│   ├── client_interpolator.gd   # Client interpolation
│   ├── logger.gd            # Logging system
│   ├── test_automation.gd   # Automated testing
│   └── network_simulator.gd # Network simulation
│
├── test_framework.py        # Run tests
├── analyze_test_logs.py     # Analyze results
│
├── test_logs/               # Generated test logs
├── test_reports/            # Generated reports
│
├── README.md               # Architecture overview
├── TESTING_FRAMEWORK.md    # Complete testing docs
├── CLAUDE.md               # Claude Code instructions
└── QUICK_START.md          # This file
```

---

## Key Files to Know

| File | Purpose | When to Edit |
|------|---------|--------------|
| `network_config.gd` | Network constants | Tuning performance |
| `server_world.gd` | Server simulation | Game logic changes |
| `entity_snapshot.gd` | Compression | Adding new entity properties |
| `client_interpolator.gd` | Interpolation | Smoothness tuning |
| `logger.gd` | Logging | Adding custom logs |
| `test_automation.gd` | Test behaviors | Creating new test patterns |

---

## Debugging Workflow

1. **Run a test**
   ```bash
   ./test_framework.py --test stress
   ```

2. **Check if it passed**
   ```bash
   cat test_reports/claude_debug_summary.md | grep "✅"
   ```

3. **If issues found, analyze**
   ```bash
   # Read the Claude-friendly summary
   cat test_reports/claude_debug_summary.md

   # Check specific log files
   grep ERROR test_logs/stress_test_*/client_0.log
   ```

4. **Ask Claude to debug**
   ```
   Claude, I see player disappearances in the test report.
   Please read test_reports/claude_debug_summary.md and
   analyze test_logs/stress_test_<timestamp>/client_0.log
   to find the root cause.
   ```

5. **Fix the issue**
   - Claude will suggest file paths and line numbers
   - Make the changes
   - Re-run the test to verify

---

## Performance Targets

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| Player Disappearances | 0 | 0 | >0 |
| Packet Loss | <1% | 1-5% | >5% |
| Avg Snapshot Size | <500 bytes | 500-1000 | >1000 |
| Interpolation Warnings | <10 | 10-50 | >50 |
| FPS (Client) | 60 | 30-60 | <30 |

---

## Network Configuration Quick Reference

```gdscript
# In scripts/network_config.gd

TICK_RATE = 32              # Server Hz (higher = more accurate)
SNAPSHOT_RATE = 10          # Snapshots/sec (higher = smoother)
INTERPOLATION_DELAY = 0.05  # Buffer time (higher = more stable)
JITTER_BUFFER = 0.025       # Extra buffer (higher = more resilient)
CHUNK_SIZE = 64             # Spatial partition size
INTEREST_RADIUS = 2         # Chunks visible around player
```

**Common Adjustments:**
- **Laggy network?** Increase `INTERPOLATION_DELAY` to 0.1
- **Need precision?** Increase `TICK_RATE` to 60
- **Too much bandwidth?** Decrease `SNAPSHOT_RATE` to 5
- **Large world?** Increase `CHUNK_SIZE` to 128

---

## Next Steps

1. **Read the full docs**: `TESTING_FRAMEWORK.md`
2. **Understand the architecture**: `README.md`
3. **Learn about the bug fixes**: `DELTA_COMPRESSION_BUG.md`
4. **Run all tests**: `./test_framework.py --test all`
5. **Customize for your game**: Modify entity properties, add game logic

---

## Getting Help

1. **Check documentation**
   - `TESTING_FRAMEWORK.md` - Testing guide
   - `README.md` - Architecture details
   - `CLAUDE.md` - Project-specific instructions

2. **Use Claude Code**
   ```
   Claude, I'm having issues with [describe problem].
   Please read QUICK_START.md and help me debug.
   ```

3. **Review test logs**
   ```bash
   ./analyze_test_logs.py test_logs/<test_dir>
   cat test_reports/claude_debug_summary.md
   ```

---

## Tips

✅ **DO:**
- Run tests before committing changes
- Check `claude_debug_summary.md` after every test
- Use structured logging (`Logger.info()`, not `print()`)
- Test with multiple clients
- Simulate network conditions

❌ **DON'T:**
- Modify core files without running tests
- Ignore warnings in test reports
- Use `print()` for debugging (use `Logger.debug()`)
- Test only with 1 client
- Assume perfect network conditions
