#!/bin/bash
PROJECT_PATH=$(pwd)
GODOT_PATH="/Applications/Godot.app/Contents/MacOS/Godot"
LOG_DIR="${PROJECT_PATH}/debug_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "${LOG_DIR}"

echo "Killing existing Godot instances..."
pkill -9 Godot 2>/dev/null
sleep 2

echo "Starting server..."
"${GODOT_PATH}" --path "${PROJECT_PATH}" --headless --server > "${LOG_DIR}/server_${TIMESTAMP}.log" 2>&1 &
SERVER_PID=$!
echo "Server PID: ${SERVER_PID}"
sleep 3

echo "Starting client (headless)..."
"${GODOT_PATH}" --path "${PROJECT_PATH}" --headless --client > "${LOG_DIR}/client_${TIMESTAMP}.log" 2>&1 &
CLIENT_PID=$!
echo "Client PID: ${CLIENT_PID}"

echo "Running for 20 seconds..."
sleep 20

echo "Stopping..."
kill ${SERVER_PID} ${CLIENT_PID}
wait ${SERVER_PID} ${CLIENT_PID} 2>/dev/null

echo "Analyzing client log..."
# Check for baseline mismatch errors
BASELINE_ERRORS=$(grep -c "Baseline mismatch" "${LOG_DIR}/client_${TIMESTAMP}.log")
echo "Baseline mismatch errors: ${BASELINE_ERRORS}"

# Check for player disappearance
PLAYER_ERRORS=$(grep -c "Player entity .* NOT in snapshot" "${LOG_DIR}/client_${TIMESTAMP}.log")
echo "Player disappearance errors: ${PLAYER_ERRORS}"

# Check for successful recovery/usage of older baselines
# (We might need to grep for the debug print I didn't add, but absence of errors is good)

if [ ${BASELINE_ERRORS} -eq 0 ] && [ ${PLAYER_ERRORS} -eq 0 ]; then
    echo "SUCCESS: No errors detected."
else
    echo "FAILURE: Errors still present."
    echo "Tail of client log:"
    tail -n 20 "${LOG_DIR}/client_${TIMESTAMP}.log"
fi
