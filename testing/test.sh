#!/bin/bash
# Simple wrapper for the Python Test Framework

# Detect Godot if not set
if [ -z "$GODOT_PATH" ]; then
    if command -v godot4 &> /dev/null; then
        export GODOT_PATH=$(command -v godot4)
    elif command -v godot &> /dev/null; then
        export GODOT_PATH=$(command -v godot)
    elif [ -f "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
        export GODOT_PATH="/Applications/Godot.app/Contents/MacOS/Godot"
    fi
fi

if [ -z "$GODOT_PATH" ]; then
    echo "Error: Godot executable not found."
    echo "Please set GODOT_PATH environment variable or ensure 'godot' is in your PATH."
    exit 1
fi

# Run the framework
python3 tools/test_framework.py --godot "$GODOT_PATH" "$@"
