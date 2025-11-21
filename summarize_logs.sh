#!/usr/bin/env bash
set -euo pipefail

# Summarize autotest logs into a compact, LLM-friendly report.

RG_BIN="rg"
if ! command -v "$RG_BIN" >/dev/null 2>&1; then
	RG_BIN="grep"
fi

LOG_DIR="${1:-}"
if [[ -z "$LOG_DIR" ]]; then
	# Pick the newest debug_logs/run_* directory
	latest=$(ls -d debug_logs/run_* 2>/dev/null | sort | tail -n 1)
	if [[ -z "$latest" ]]; then
		echo "No log directory provided and none found under debug_logs/run_*"
		exit 1
	fi
	LOG_DIR="$latest"
fi

if [[ ! -d "$LOG_DIR" ]]; then
	echo "Log directory not found: $LOG_DIR"
	exit 1
fi

SUMMARY_FILE="${LOG_DIR}/summary.txt"
echo "Summarizing logs in $LOG_DIR"
echo "Writing summary to $SUMMARY_FILE"

cat > "$SUMMARY_FILE" <<EOF
Autotest log summary for $(basename "$LOG_DIR")
Generated: $(date)
EOF

# Helper to count matches with fallback
count_matches() {
	local pattern="$1"
	local file="$2"
	if [[ "$RG_BIN" == "rg" ]]; then
		"$RG_BIN" -c "$pattern" "$file" 2>/dev/null || echo 0
	else
		"$RG_BIN" -c "$pattern" "$file" 2>/dev/null || echo 0
	fi
}

for log in "$LOG_DIR"/*.log; do
	name="$(basename "$log")"
	echo "" | tee -a "$SUMMARY_FILE" >/dev/null
	echo "---- ${name} ----" | tee -a "$SUMMARY_FILE"

	if [[ "$name" == server* ]]; then
		snapshots=$(count_matches "Snapshot #" "$log")
		input_lines=$(count_matches "\\[SERVER INPUT\\]" "$log")
		echo "snapshots=${snapshots} | input_logs=${input_lines}" | tee -a "$SUMMARY_FILE"

		if command -v "$RG_BIN" >/dev/null 2>&1; then
			"$RG_BIN" -n "SERVER.*Snapshot" "$log" | tail -n 5 >> "$SUMMARY_FILE" || true
		fi
	else
		snapshots=$(count_matches "\\[CLIENT\\] Received snapshot" "$log")
		player_missing=$(count_matches "\\[CLIENT\\] ERROR: Player entity" "$log")
		packet_loss=$(count_matches "Packet loss detected" "$log")
		holds=$(count_matches "\\[INTERPOLATOR\\] Holding" "$log")
		drops=$(count_matches "\\[AUTOTEST\\].*DROP" "$log")
		pred_debug=$(count_matches "\\[RENDERER DEBUG\\]" "$log")

		echo "snapshots=${snapshots} | missing_player=${player_missing} | packet_loss_warn=${packet_loss} | holds=${holds} | drops=${drops} | prediction_debug_lines=${pred_debug}" | tee -a "$SUMMARY_FILE"

		if command -v "$RG_BIN" >/dev/null 2>&1; then
			echo "last_autotest_lines:" >> "$SUMMARY_FILE"
			"$RG_BIN" "\\[AUTOTEST\\]" "$log" | tail -n 5 >> "$SUMMARY_FILE" || true
			echo "last_interpolator_debug:" >> "$SUMMARY_FILE"
			"$RG_BIN" "\\[INTERPOLATOR DEBUG\\]" "$log" | tail -n 3 >> "$SUMMARY_FILE" || true
			echo "last_prediction_debug:" >> "$SUMMARY_FILE"
			"$RG_BIN" "\\[RENDERER DEBUG\\]" "$log" | tail -n 3 >> "$SUMMARY_FILE" || true
		fi
	fi
done

echo "" | tee -a "$SUMMARY_FILE" >/dev/null
echo "Summary saved to ${SUMMARY_FILE}"
