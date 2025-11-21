#!/usr/bin/env bash
set -euo pipefail

# Automated multi-client test runner for snapshot-interpolation
# Spawns a headless server plus N scripted clients, captures logs, and summarizes them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"

CLIENTS=3
DURATION=25
LAG_MS=80
JITTER_MS=40
PACKET_LOSS=0.0
PATTERN="circle"

GODOT_BIN="${GODOT_BIN:-${GODOT_PATH:-}}"

usage() {
	echo "Usage: $0 [-c clients] [-d seconds] [--lag-ms N] [--jitter-ms N] [--packet-loss F] [--pattern circle|line|figure8|dashes] [--godot /path/to/Godot]"
	echo "Defaults: clients=${CLIENTS}, duration=${DURATION}s, lag=${LAG_MS}ms, jitter=${JITTER_MS}ms, loss=${PACKET_LOSS}, pattern=${PATTERN}"
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-c|--clients) CLIENTS="$2"; shift 2;;
		-d|--duration) DURATION="$2"; shift 2;;
		--lag-ms) LAG_MS="$2"; shift 2;;
		--jitter-ms) JITTER_MS="$2"; shift 2;;
		--packet-loss) PACKET_LOSS="$2"; shift 2;;
		--pattern) PATTERN="$2"; shift 2;;
		--godot) GODOT_BIN="$2"; shift 2;;
		-h|--help) usage;;
		*) echo "Unknown flag: $1"; usage;;
	esac
done

# Locate Godot binary if not provided
if [[ -z "$GODOT_BIN" ]]; then
	# Common macOS install path
	if [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
		GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
	fi
fi

if [[ -z "$GODOT_BIN" ]]; then
	for candidate in godot4 godot; do
		if command -v "$candidate" >/dev/null 2>&1; then
			GODOT_BIN="$candidate"
			break
		fi
	done
fi

if [[ -z "$GODOT_BIN" ]]; then
	echo "Godot binary not found. Set GODOT_BIN or GODOT_PATH."
	exit 1
fi

RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${PROJECT_DIR}/debug_logs/run_${RUN_ID}"
mkdir -p "$LOG_DIR"

echo "=== Starting autotest run ${RUN_ID} ==="
echo "Godot: $GODOT_BIN"
echo "Clients: $CLIENTS | Duration: ${DURATION}s | Lag: ${LAG_MS}ms+/-${JITTER_MS}ms | Loss: ${PACKET_LOSS} | Pattern: ${PATTERN}"
echo "Logs: $LOG_DIR"

PIDS=()

cleanup() {
	if [[ ${#PIDS[@]} -gt 0 ]]; then
		echo "Stopping processes: ${PIDS[*]}"
		kill "${PIDS[@]}" 2>/dev/null || true
	fi
}
trap cleanup EXIT

echo "Starting server..."
"$GODOT_BIN" --headless --path "$PROJECT_DIR" -- --mode=server --exit-after="${DURATION}" > "${LOG_DIR}/server.log" 2>&1 &
PIDS+=($!)

sleep 1

for i in $(seq 1 "$CLIENTS"); do
	label="c${i}"
	log_file="${LOG_DIR}/client_${label}.log"
	echo "Starting client ${label} -> ${log_file}"
	"$GODOT_BIN" --headless --path "$PROJECT_DIR" -- --mode=client --headless-client \
		--autotest-id="${label}" \
		--auto-move="${PATTERN}" \
		--fake-lag-ms="${LAG_MS}" \
		--fake-jitter-ms="${JITTER_MS}" \
		--packet-loss="${PACKET_LOSS}" \
		--exit-after="${DURATION}" > "${log_file}" 2>&1 &
	PIDS+=($!)
	sleep 0.25
done

echo "Waiting for run to finish..."
wait || true

if [[ -x "${PROJECT_DIR}/summarize_logs.sh" ]]; then
	"${PROJECT_DIR}/summarize_logs.sh" "${LOG_DIR}"
else
	echo "summary: summarize_logs.sh not executable; skipping summary generation."
fi

echo "Run complete. Logs at ${LOG_DIR}"
