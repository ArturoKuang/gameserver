# Testing Environment Guide

This directory contains the automated testing framework for the Snapshot Interpolation project.

## Files
- `test.sh`: Main entry point for running tests.
- `tools/test_framework.py`: The Python framework managing Godot instances and log analysis.
- `docs/design/TEST_ENVIRONMENT_RESEARCH.md`: Research and design document for this environment.

## Usage

### Running Tests
You can run tests using the helper script:

```bash
./test.sh --test <test_name>
```

Available test names:
- `basic` (Default): Single client, random walk.
- `stress`: High frequency movement changes.
- `lag`: 200ms simulated lag.
- `packet_loss`: 10% simulated packet loss.
- `multi_client`: 3 concurrent clients.
- `all`: Runs all standard tests in sequence.
- `custom`: Run with custom parameters.

### Custom Tests
You can define custom parameters on the fly:

```bash
./test.sh --test custom --clients 2 --duration 60 --lag 100 --loss 0.05 --mode circle_pattern
```

### Agent Integration
To use this tool with an AI agent (like Gemini or Claude):

1. Run the test with `--json-out` (optional, just ensures clean output).
2. Parse the output line starting with `REPORT_JSON:`.
3. Read the JSON file for detailed metrics.
4. Read the generated Markdown summary in `test_reports/`.

## Troubleshooting
If tests fail to start, ensure:
1. `GODOT_PATH` is set or `godot` is in your PATH.
2. The project imports successfully (run Godot Editor once if needed).
3. `scripts/logger.gd` is properly loaded (check `project.godot` Autoloads if GDScript errors occur).
