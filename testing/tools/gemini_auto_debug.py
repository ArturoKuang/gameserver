#!/usr/bin/env python3
"""
Gemini Auto-Debug Wrapper
Runs the test framework, captures the JSON report, and prepares context for LLM analysis.
"""

import subprocess
import sys
import json
import os
from pathlib import Path

def run_test_and_get_report(args):
    """Runs the test script and extracts the report path."""
    
    # Resolve paths
    script_dir = Path(__file__).parent.resolve()
    test_dir = script_dir.parent
    test_script = test_dir / "test.sh"
    
    if not test_script.exists():
        print(f"[AUTO-DEBUG] Error: Could not find test.sh at {test_script}")
        return None, ""

    cmd = [str(test_script), "--json-out"] + args
    print(f"[AUTO-DEBUG] Running: {' '.join(cmd)}")
    print(f"[AUTO-DEBUG] Working Directory: {test_dir}")
    
    try:
        print(f"[AUTO-DEBUG] Running: {' '.join(cmd)}")
        print(f"[AUTO-DEBUG] Working Directory: {test_dir}")

        process = subprocess.Popen(
            cmd,
            cwd=test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        full_output = []
        while True:
            line = process.stdout.readline()
            if not line and process.poll() is not None:
                break
            if line:
                print(line, end='') # Print to console in real-time
                full_output.append(line)

        exit_code = process.poll()
        output_str = "".join(full_output)

        if exit_code != 0:
             raise subprocess.CalledProcessError(exit_code, cmd, output=output_str)
        
        # Find the REPORT_JSON line
        report_path = None
        for line in full_output:
            if line.startswith("REPORT_JSON:"):
                report_path = line.split(":", 1)[1].strip()
                break
                
        if not report_path:
            print("[AUTO-DEBUG] Error: No REPORT_JSON found in output.")
            return None, output_str
            
        return report_path, output_str
        
    except subprocess.CalledProcessError as e:
        print(f"[AUTO-DEBUG] Test Failed with exit code {e.returncode}")
        print(e.stdout)
        print(e.stderr)
        return None, e.stdout + "\n" + e.stderr

def generate_llm_prompt(report_path):
    """Reads the report and generates a prompt for Gemini."""
    try:
        with open(report_path, 'r') as f:
            report = json.load(f)
    except Exception as e:
        print(f"[AUTO-DEBUG] Failed to load report: {e}")
        return

    summary_path = str(Path(report_path).parent / f"{report['test_name']}_summary.md")
    
    print("\n" + "="*80)
    print("🤖 GEMINI DEBUG CONTEXT GENERATED")
    print("="*80)
    print(f"To analyze this test run, provide the following context to Gemini:\n")
    
    print(f"I have run a network test '{report['test_name']}' with the following profile:")
    print(json.dumps(report['network_profile'], indent=2))
    
    print(f"\nPlease analyze the results found in:\n{summary_path}")
    
    print("\nAnd cross-reference with these raw logs if needed:")
    for role, path in report.get('log_files', {}).items():
        print(f"- {role}: {path}")
        
    print("\nFocus on finding:")
    print("1. Correlation between network lag/loss and 'player_disappearances'.")
    print("2. Patterns in 'buffer_underruns' (e.g., do they happen periodically?).")
    print("3. Baseline mismatches indicating state desync.")
    print("\nIf you find bugs, propose a patch for the relevant script.")
    print("="*80)

def main():
    # Pass through arguments to test.sh
    test_args = sys.argv[1:]
    if not test_args:
        test_args = ["--test", "basic"]
    
    # Ensure --debug-vis is passed if set (though sys.argv[1:] should handle it, being explicit is good if we add arg parsing here later)
    # Currently we just pass all args directly.
        
    report_path, output = run_test_and_get_report(test_args)
    
    if report_path:
        generate_llm_prompt(report_path)
    else:
        print("[AUTO-DEBUG] Could not generate analysis context due to test failure.")
        sys.exit(1)

if __name__ == "__main__":
    main()
