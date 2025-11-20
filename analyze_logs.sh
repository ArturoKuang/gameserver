#!/bin/bash
# Log analysis script to detect player disappearance bugs

if [ -z "$1" ]; then
    echo "Usage: $0 <log_file>"
    echo "Example: $0 debug_logs/client_20250116_120000.log"
    exit 1
fi

LOG_FILE="$1"

if [ ! -f "${LOG_FILE}" ]; then
    echo "Error: Log file not found: ${LOG_FILE}"
    exit 1
fi

echo "=== Analyzing log: ${LOG_FILE} ==="
echo ""

# Count player disappearance errors
PLAYER_ERROR_COUNT=$(grep -c "\[CLIENT\] ERROR: Player entity .* NOT in snapshot" "${LOG_FILE}")
echo "Player disappearance errors: ${PLAYER_ERROR_COUNT}"

# Count interpolator entity disappeared warnings
INTERPOLATOR_PLAYER_DISAPPEARED=$(grep "\[INTERPOLATOR\] Entity .* disappeared" "${LOG_FILE}" | grep -c "Entity 51")
echo "Interpolator player disappeared warnings: ${INTERPOLATOR_PLAYER_DISAPPEARED}"

# Count total snapshots received
TOTAL_SNAPSHOTS=$(grep -c "\[CLIENT\] Received snapshot" "${LOG_FILE}")
echo "Total snapshots received: ${TOTAL_SNAPSHOTS}"

# Calculate error rate
if [ ${TOTAL_SNAPSHOTS} -gt 0 ]; then
    ERROR_RATE=$(echo "scale=2; ${PLAYER_ERROR_COUNT} * 100 / ${TOTAL_SNAPSHOTS}" | bc)
    echo "Error rate: ${ERROR_RATE}%"
fi

echo ""
echo "=== Sample player errors (first 10) ==="
grep "\[CLIENT\] ERROR: Player entity .* NOT in snapshot" "${LOG_FILE}" | head -10

echo ""
echo "=== Deserialization issues (if any) ==="
grep "\[DESERIALIZE\].*Player 51 in snapshot: false" "${LOG_FILE}" | head -10

echo ""
echo "=== Summary ==="
if [ ${PLAYER_ERROR_COUNT} -eq 0 ]; then
    echo "✓ No player disappearance errors detected!"
else
    echo "✗ Found ${PLAYER_ERROR_COUNT} player disappearance errors"
fi
