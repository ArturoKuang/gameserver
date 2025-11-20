#!/bin/bash
# Debug testing script for snapshot interpolation

PROJECT_PATH="/Users/arturokuang/snapshot-interpolation"
GODOT_PATH="/Applications/Godot.app/Contents/MacOS/Godot"
LOG_DIR="${PROJECT_PATH}/debug_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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

# Start client and capture output
echo "Starting client..."
"${GODOT_PATH}" --path "${PROJECT_PATH}" > "${LOG_DIR}/client_${TIMESTAMP}.log" 2>&1 &
CLIENT_PID=$!
echo "Client PID: ${CLIENT_PID}"

echo ""
echo "Server and client are running..."
echo "Server log: ${LOG_DIR}/server_${TIMESTAMP}.log"
echo "Client log: ${LOG_DIR}/client_${TIMESTAMP}.log"
echo ""
echo "Press Ctrl+C to stop and analyze logs..."

# Wait for interrupt
trap "echo 'Stopping...'; kill ${SERVER_PID} ${CLIENT_PID} 2>/dev/null; exit 0" SIGINT SIGTERM

# Keep script running
wait
