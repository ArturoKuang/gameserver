#!/bin/bash
# Debug testing script for snapshot interpolation
# Usage: ./debug_test.sh [num_clients]
# Example: ./debug_test.sh 3  (starts 1 server + 3 clients)

# Number of clients to start (default: 2)
NUM_CLIENTS=${1:-2}

PROJECT_PATH="/Users/arturokuang/snapshot-interpolation"
GODOT_PATH="/Applications/Godot.app/Contents/MacOS/Godot"
LOG_DIR="${PROJECT_PATH}/debug_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Array to store all PIDs
CLIENT_PIDS=()

# Create log directory
mkdir -p "${LOG_DIR}"

# Kill existing Godot instances
echo "Killing existing Godot instances..."
pkill -9 Godot 2>/dev/null
sleep 2

# Start server and capture output
echo "Starting server..."
"${GODOT_PATH}" --path "${PROJECT_PATH}" --headless > "${LOG_DIR}/server_${TIMESTAMP}.log" 2>&1 &
SERVER_PID=$!
echo "Server PID: ${SERVER_PID}"
sleep 3

# Start multiple clients
echo "Starting ${NUM_CLIENTS} client(s)..."
for i in $(seq 1 ${NUM_CLIENTS}); do
    echo "  Starting client ${i}..."
    "${GODOT_PATH}" --path "${PROJECT_PATH}" > "${LOG_DIR}/client_${i}_${TIMESTAMP}.log" 2>&1 &
    CLIENT_PIDS+=($!)
    echo "  Client ${i} PID: ${!}"
    sleep 2  # Stagger client starts
done

echo ""
echo "Server and ${NUM_CLIENTS} client(s) are running..."
echo "Server log: ${LOG_DIR}/server_${TIMESTAMP}.log"
for i in $(seq 1 ${NUM_CLIENTS}); do
    echo "Client ${i} log: ${LOG_DIR}/client_${i}_${TIMESTAMP}.log"
done
echo ""
echo "Press Ctrl+C to stop and analyze logs..."

# Wait for interrupt
cleanup() {
    echo ""
    echo "Stopping..."
    kill ${SERVER_PID} 2>/dev/null
    for pid in "${CLIENT_PIDS[@]}"; do
        kill ${pid} 2>/dev/null
    done
    exit 0
}

trap cleanup SIGINT SIGTERM

# Tail logs and surface errors in real time
log_grep() {
    local label="$1"
    shift
    grep -E --line-buffered -n "$@" | sed "s/^/[${label}] /"
}

(
    tail -F "${LOG_DIR}/server_${TIMESTAMP}.log" | log_grep "SERVER" "ERROR|CRITICAL|Exception|stack"
) &
TAIL_SERVER_PID=$!

for i in $(seq 1 ${NUM_CLIENTS}); do
    (
        tail -F "${LOG_DIR}/client_${i}_${TIMESTAMP}.log" | log_grep "CLIENT${i}" "ERROR|CRITICAL|Exception|stack"
    ) &
done

# Keep script running
wait
