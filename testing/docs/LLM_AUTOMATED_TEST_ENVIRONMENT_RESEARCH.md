# LLM-Automated Server/Client Test Environment Research

**Scope:** How to spin up the Godot server and client headlessly, drive clients with scripted movement, simulate bad networks (lag, jitter, packet loss, latency/bandwidth), and let an LLM CLI (Gemini or similar) run tests, read logs, and iterate without human help.

## Existing Building Blocks (Repository)
- `testing/tools/test_framework.py` spawns a headless server and N headless clients, applies env vars for packet loss/lag, gathers logs, and emits `REPORT_JSON:<path>` plus a Markdown summary.
- `scripts/test_automation.gd` drives player movement via `TEST_BEHAVIOR` (random_walk, stress_test, chunk_crossing, circle_pattern, etc.).
- `scripts/network_simulator.gd` applies `TEST_PACKET_LOSS` and `TEST_LAG_MS`; `scripts/network_config.gd` honors overrides like `NET_CFG_INTERP_DELAY` and `NET_CFG_JITTER_BUF`.
- `testing/test.sh` is a thin wrapper over the framework; logs live in `test_logs/<test_id>` and reports in `test_reports/`.

## Target Test Environment Capabilities
- Start server and clients headlessly (`godot --headless --path <project>`).
- Drive movement via test scripts (behavior patterns + goal-based scenarios).
- Simulate network impairments: constant/variable lag, jitter, packet loss, bandwidth caps, reorder/duplication if possible.
- Collect structured logs/metrics suitable for machines.
- Let Gemini CLI (or other LLM CLIs) 1) run tests, 2) read logs/reports, 3) suggest/apply fixes, and 4) re-run in a loop.

## Orchestration Model
1. **Launcher:** `testing/tools/test_framework.py` (or `./test.sh`) starts one headless server + N headless clients with env vars for network and behavior. Example:
   ```bash
   ./test.sh --test custom --clients 3 --duration 60 --mode stress_test --lag 120 --loss 0.05 --json-out
   ```
   - Server env: `TEST_MODE=server`, optional `NET_CFG_INTERP_DELAY`, `NET_CFG_JITTER_BUF`.
   - Client env: `TEST_MODE=client`, `TEST_CLIENT_ID`, `TEST_BEHAVIOR`, `TEST_PACKET_LOSS`, `TEST_LAG_MS`.
2. **Network shaping:** Choose one:
   - **In-Godot:** Extend `scripts/network_simulator.gd` to add jitter and bandwidth caps (works cross-platform, zero deps). Suitable for per-client randomness.
   - **Proxy-based:** Run [Toxiproxy](https://github.com/Shopify/toxiproxy) and point clients at the proxy (`listen :7777 -> upstream :7778`), then add toxics for latency/jitter/loss/bandwidth via Python in the framework for dynamic changes mid-test.
   - **OS-level:** Use Linux `tc/netem` for qdisc-based latency/jitter/loss + `tbf` for bandwidth; best for CI runners/containers.
3. **Behavior scripts:** Use `TEST_BEHAVIOR` plus new goal-based scenarios (e.g., convergence swarm, connect/disconnect churn, long-path traversal). Movement is already programmatic; no rendering needed.
4. **Metrics/logging:** Keep stdout logs per process (`test_logs/.../server.log`, `client_<n>.log`). Add JSON/structured prefixes (e.g., `[LOG_JSON]{...}`) in `logger.gd` so LLMs can parse reliably.
5. **Reporting:** Framework already produces `<test_id>_report.json` + `<test_name>_summary.md` with snapshot counts, errors, and delays; ensure it includes paths to raw logs and any derived metrics the LLM should read first.

## Network Simulation Options (Lag/Jitter/Loss/Bandwidth)
- **Godot-level (quick win):**
  - Add jitter: random delay around `TEST_LAG_MS` (e.g., uniform or normal distribution) inside `network_simulator.gd`.
  - Add bandwidth cap: track bytes per second and delay/shed packets when over budget.
  - Add drop/duplication knobs for reliability testing.
- **Toxiproxy (recommended for flexibility):**
  ```python
  from toxiproxy import Toxiproxy
  client = Toxiproxy()
  proxy = client.create(name="godot_server", listen="0.0.0.0:7777", upstream="127.0.0.1:7778")
  proxy.add_toxic("lag", "latency", {"latency": 120, "jitter": 40})
  proxy.add_toxic("loss", "loss", {"probability": 0.05})
  proxy.add_toxic("throttle", "bandwidth", {"rate": 128})  # KB/s
  ```
  - Swap profiles on the fly (wifi_good, wifi_bad, 3g, satellite) during a single run to test recovery.
- **`tc/netem` (CI/containers):**
  ```bash
  sudo tc qdisc add dev eth0 root handle 1: netem delay 100ms 30ms loss 5%
  sudo tc qdisc add dev eth0 parent 1:1 handle 10: tbf rate 1mbit burst 32kbit latency 400ms
  ```
  - Works well inside Docker; clean up with `tc qdisc del dev eth0 root`.

## Headless Player Control
- Server: `godot --headless --path <project> --main-pack project.godot` (framework already does `--headless`).
- Clients: same headless invocation; `scripts/test_automation.gd` reads `TEST_BEHAVIOR` and `TEST_CLIENT_ID` to choose movement vectors.
- Add new behaviors to cover reliability cases:
  - **Churn:** connect/disconnect on timers to shake out cleanup bugs.
  - **Convergence swarm:** many clients rush the same point to stress collisions and interest management.
  - **Route replay:** deterministic path scripts for reproducible perf comparisons.

## LLM CLI Integration (Gemini or similar)
- **Execution hook:** Use `--json-out` so the last line contains `REPORT_JSON:<path>`. LLM reads that path, then the summary Markdown, then the referenced logs.
- **Analysis commands (Gemini CLI examples):**
  ```bash
  gemini file analyze --file test_reports/basic_summary.md
  gemini file analyze --file test_logs/basic_*/server.log
  ```
  - Provide prompt context: test config, what to look for (buffer underruns, interpolation warnings, baseline mismatches).
- **Autonomous loop sketch:**
  1) Run `./test.sh ... --json-out`.
  2) Parse `REPORT_JSON` path; load JSON + summary.
  3) Ask Gemini: "Find root cause + propose patches in scripts/*.gd".
  4) Let Gemini apply patch (e.g., via `gemini --apply` or a local wrapper).
  5) Re-run tests; compare new report vs prior; repeat until pass or max iterations.
  - Keep a rollback point (git branch or copy) to avoid bad loops.
- **Data hygiene:** Ensure logs carry stable prefixes and minimal noise; avoid ANSI; prefer JSON entries so Gemini can filter quickly.

## Reliability/Latency Metrics to Track
- Server: snapshot count/size, chunk changes, tick duration, dropped/resent packets.
- Client: snapshots received, buffer underruns, interpolation warnings, baseline mismatches, measured delay (already parsed in framework).
- Network: configured vs observed latency/jitter, loss %, bandwidth usage (can be logged by proxy or Godot).
- Stability: process exits/crashes, reconnect success rate, time-to-first-snapshot after reconnect.

## Suggested Implementation Steps (ordered)
1. Extend `scripts/network_simulator.gd` with jitter, bandwidth cap, and optional duplication/reorder toggles; expose via env vars (`TEST_JITTER_MS`, `TEST_BW_KBPS`, etc.).
2. Add new behaviors in `scripts/test_automation.gd` for churn, convergence, and deterministic path replay; wire into `TEST_BEHAVIOR`.
3. Make `testing/tools/test_framework.py` emit structured log locations and network profile metadata in the JSON report; include proxy/netem settings if used.
4. Add an optional Toxiproxy path in the framework (start/stop proxy, apply profiles mid-run).
5. Normalize logs to structured JSON lines (`[LOG_JSON]{...}`) in `scripts/logger.gd` and update the analyzer to surface the most important fields.
6. Write a small automation wrapper (e.g., `testing/tools/gemini_auto_debug.py`) that runs tests with `--json-out`, feeds logs to Gemini CLI, applies patches, and loops with a max-iteration guard.
7. For CI: create a workflow/Dockerfile that installs Godot headless + Toxiproxy, runs a quick matrix (good wifi / bad wifi / high loss), uploads reports for LLM review.

## References (practical links)
- `testing/tools/test_framework.py`, `testing/test.sh` — headless orchestration, reporting.
- `scripts/network_simulator.gd` — in-engine impairment hooks (extend for jitter/bandwidth).
- `scripts/test_automation.gd` — scripted movement behaviors for clients.
- [Toxiproxy docs](https://github.com/Shopify/toxiproxy) — API for latency/loss/bandwidth toxics.
- Linux `tc/netem` and `tbf` man pages — OS-level latency/jitter/loss/bandwidth shaping.
