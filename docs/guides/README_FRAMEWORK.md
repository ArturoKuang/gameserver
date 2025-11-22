# Automated Testing Framework

This framework allows you to run automated multiplayer tests for the Snapshot Interpolation project, collect logs, and analyze them for common networking issues.

## Files

*   `automated_test.py`: The main test runner and log analyzer.
*   `scripts/test_launcher.gd`: Godot script updated to support auto-start via command line arguments.
*   `debug_logs/`: Directory where logs are stored.

## Usage

### Prerequisites
*   Python 3.x
*   Godot 4.x installed.
*   Ensure `godot` or `godot4` is in your PATH, or set the `GODOT_PATH` environment variable.

### Running a Test

Run the python script from the project root:

```bash
python3 automated_test.py [num_clients] [duration_seconds]
```

**Examples:**

Run with 2 clients for 15 seconds (default):
```bash
python3 automated_test.py
```

Run with 4 clients for 30 seconds:
```bash
python3 automated_test.py 4 30
```

### Analyzing Results

The script will automatically:
1.  Start the Server (Headless).
2.  Start N Clients (Headless).
3.  Wait for the duration.
4.  Terminate all processes.
5.  **Analyze the logs** and print a report.

### Debugging with LLM (AI)

To get help debugging issues:
1.  Run the test.
2.  Copy the entire output of the `automated_test.py` script (including the "LOG ANALYSIS REPORT" section).
3.  Paste it into your chat with the AI Agent.
4.  The Agent will interpret the logs, looking for:
    *   Errors/Exceptions
    *   Packet Loss patterns
    *   Snapshot irregularities
    *   Buffer underruns (if logged)

## Log Locations

Individual raw logs are available for deep diving:
*   `debug_logs/server_YYYYMMDD_HHMMSS.log`
*   `debug_logs/client_N_YYYYMMDD_HHMMSS.log`
