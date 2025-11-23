#!/usr/bin/env python3
"""
Network Testing Framework for Snapshot Interpolation System

This script orchestrates automated testing of:
- Client-side interpolation
- Server authority
- Delta compression
- Interest management
- Multiple simultaneous clients
- Network condition simulation (lag, packet loss)
"""

import subprocess
import time
import os
import signal
import sys
import json
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional
import argparse


class TestConfig:
    """Configuration for a single test scenario"""
    def __init__(
        self,
        name: str,
        num_clients: int = 1,
        duration: int = 60,
        test_mode: str = "random_walk",
        packet_loss: float = 0.0,
        lag_ms: int = 0,
        enable_client_prediction: bool = False
    ):
        self.name = name
        self.num_clients = num_clients
        self.duration = duration
        self.test_mode = test_mode  # random_walk, stress_test, chunk_crossing, circle_pattern
        self.packet_loss = packet_loss
        self.lag_ms = lag_ms
        self.enable_client_prediction = enable_client_prediction


class GodotProcess:
    """Manages a single Godot instance (server or client)"""
    def __init__(
        self,
        godot_path: str,
        project_path: str,
        log_path: Path,
        is_server: bool = False,
        test_mode: str = "random_walk",
        client_id: int = 0,
        packet_loss: float = 0.0,
        lag_ms: int = 0
    ):
        self.godot_path = godot_path
        self.project_path = project_path
        self.log_path = log_path
        self.is_server = is_server
        self.test_mode = test_mode
        self.client_id = client_id
        self.packet_loss = packet_loss
        self.lag_ms = lag_ms
        self.process: Optional[subprocess.Popen] = None
        self.log_file = None

    def start(self):
        """Start the Godot process"""
        args = [self.godot_path, "--path", self.project_path]

        if self.is_server:
            args.append("--headless")
            # Server test mode environment variable
            env = os.environ.copy()
            env["TEST_MODE"] = "server"
        else:
            # Client test mode environment variables
            env = os.environ.copy()
            env["TEST_MODE"] = "client"
            env["TEST_CLIENT_ID"] = str(self.client_id)
            env["TEST_BEHAVIOR"] = self.test_mode
            env["TEST_PACKET_LOSS"] = str(self.packet_loss)
            env["TEST_LAG_MS"] = str(self.lag_ms)

        # Open log file
        self.log_file = open(self.log_path, 'w')

        # Start process
        self.process = subprocess.Popen(
            args,
            stdout=self.log_file,
            stderr=subprocess.STDOUT,
            env=env
        )

        role = "Server" if self.is_server else f"Client-{self.client_id}"
        print(f"[FRAMEWORK] Started {role} (PID: {self.process.pid}) -> {self.log_path}")

    def stop(self):
        """Stop the Godot process"""
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()

            role = "Server" if self.is_server else f"Client-{self.client_id}"
            print(f"[FRAMEWORK] Stopped {role} (PID: {self.process.pid})")

        if self.log_file:
            self.log_file.close()
            self.log_file = None

    def is_alive(self) -> bool:
        """Check if process is still running"""
        return self.process is not None and self.process.poll() is None


class TestFramework:
    """Main test orchestration framework"""

    def __init__(self, godot_path: str, project_path: str):
        self.godot_path = godot_path
        self.project_path = project_path
        self.log_dir = Path(project_path) / "test_logs"
        self.report_dir = Path(project_path) / "test_reports"

        # Create directories
        self.log_dir.mkdir(exist_ok=True)
        self.report_dir.mkdir(exist_ok=True)

        self.server: Optional[GodotProcess] = None
        self.clients: List[GodotProcess] = []
        self.current_test: Optional[TestConfig] = None

    def run_test(self, config: TestConfig):
        """Run a single test scenario"""
        print(f"\n{'='*80}")
        print(f"Running Test: {config.name}")
        print(f"Clients: {config.num_clients} | Duration: {config.duration}s")
        print(f"Test Mode: {config.test_mode} | Packet Loss: {config.packet_loss*100}% | Lag: {config.lag_ms}ms")
        print(f"{'='*80}\n")

        self.current_test = config
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        test_id = f"{config.name}_{timestamp}"

        # Create test-specific log directory
        test_log_dir = self.log_dir / test_id
        test_log_dir.mkdir(exist_ok=True)

        try:
            # Start server
            server_log = test_log_dir / "server.log"
            self.server = GodotProcess(
                self.godot_path,
                self.project_path,
                server_log,
                is_server=True
            )
            self.server.start()
            time.sleep(3)  # Wait for server to initialize

            # Start clients
            for i in range(config.num_clients):
                client_log = test_log_dir / f"client_{i}.log"
                client = GodotProcess(
                    self.godot_path,
                    self.project_path,
                    client_log,
                    is_server=False,
                    test_mode=config.test_mode,
                    client_id=i,
                    packet_loss=config.packet_loss,
                    lag_ms=config.lag_ms
                )
                client.start()
                self.clients.append(client)
                time.sleep(1)  # Stagger client starts

            # Monitor test
            print(f"\n[FRAMEWORK] Test running for {config.duration} seconds...")
            start_time = time.time()

            while time.time() - start_time < config.duration:
                # Check if processes are still alive
                if not self.server.is_alive():
                    print("[FRAMEWORK] ERROR: Server died!")
                    break

                alive_clients = sum(1 for c in self.clients if c.is_alive())
                if alive_clients == 0:
                    print("[FRAMEWORK] ERROR: All clients died!")
                    break

                # Print progress
                elapsed = int(time.time() - start_time)
                if elapsed % 10 == 0:
                    print(f"[FRAMEWORK] Progress: {elapsed}/{config.duration}s | "
                          f"Server: {'✓' if self.server.is_alive() else '✗'} | "
                          f"Clients: {alive_clients}/{config.num_clients}")

                time.sleep(1)

            print(f"\n[FRAMEWORK] Test completed: {config.name}")

        finally:
            # Stop all processes
            self._cleanup()

            # Analyze logs
            print(f"\n[FRAMEWORK] Analyzing logs...")
            report = self._analyze_logs(test_log_dir, config)

            # Save report
            report_path = self.report_dir / f"{test_id}_report.json"
            with open(report_path, 'w') as f:
                json.dump(report, f, indent=2)

            print(f"[FRAMEWORK] Report saved to: {report_path}")

            # Generate Claude-friendly summary
            self._generate_claude_summary(report, test_log_dir, config)

            return report

    def _cleanup(self):
        """Stop all running processes"""
        print(f"\n[FRAMEWORK] Cleaning up...")

        for client in self.clients:
            client.stop()

        if self.server:
            self.server.stop()

        self.clients.clear()
        self.server = None

    def _analyze_logs(self, log_dir: Path, config: TestConfig) -> Dict:
        """Analyze test logs and extract metrics"""
        print(f"[FRAMEWORK] Parsing logs from {log_dir}...")

        report = {
            "test_name": config.name,
            "config": {
                "num_clients": config.num_clients,
                "duration": config.duration,
                "test_mode": config.test_mode,
                "packet_loss": config.packet_loss,
                "lag_ms": config.lag_ms
            },
            "results": {
                "server": self._analyze_server_log(log_dir / "server.log"),
                "clients": []
            }
        }

        # Analyze each client
        for i in range(config.num_clients):
            client_log = log_dir / f"client_{i}.log"
            if client_log.exists():
                report["results"]["clients"].append(
                    self._analyze_client_log(client_log, i)
                )

        return report

    def _analyze_server_log(self, log_path: Path) -> Dict:
        """Extract server metrics from log file"""
        if not log_path.exists():
            return {"error": "Log file not found"}

        metrics = {
            "total_snapshots": 0,
            "avg_snapshot_size": 0,
            "total_entities": 0,
            "chunk_changes": 0,
            "errors": []
        }

        with open(log_path, 'r') as f:
            snapshot_sizes = []
            for line in f:
                # Count snapshots
                if "Snapshot #" in line and "to peer" in line:
                    metrics["total_snapshots"] += 1
                    # Extract size if available
                    if "bytes" in line:
                        try:
                            size = int(line.split("bytes")[0].split()[-1])
                            snapshot_sizes.append(size)
                        except:
                            pass

                # Count chunk changes
                if "moved from chunk" in line:
                    metrics["chunk_changes"] += 1

                # Count errors
                if "ERROR" in line or "WARNING" in line:
                    metrics["errors"].append(line.strip())

            if snapshot_sizes:
                metrics["avg_snapshot_size"] = sum(snapshot_sizes) / len(snapshot_sizes)

        return metrics

    def _analyze_client_log(self, log_path: Path, client_id: int) -> Dict:
        """Extract client metrics from log file"""
        if not log_path.exists():
            return {"error": "Log file not found", "client_id": client_id}

        metrics = {
            "client_id": client_id,
            "snapshots_received": 0,
            "player_disappearances": 0,
            "interpolation_warnings": 0,
            "baseline_mismatches": 0,
            "avg_delay_ms": 0,
            "errors": []
        }

        with open(log_path, 'r') as f:
            delays = []
            for line in f:
                # Count snapshots
                if "Received snapshot" in line:
                    metrics["snapshots_received"] += 1

                # Player disappearance errors
                if "Player entity" in line and "NOT in snapshot" in line:
                    metrics["player_disappearances"] += 1

                # Interpolation issues
                if "INTERPOLATOR" in line and "WARNING" in line:
                    metrics["interpolation_warnings"] += 1

                # Baseline mismatches
                if "Baseline mismatch" in line:
                    metrics["baseline_mismatches"] += 1

                # Extract delay measurements
                if "Delay:" in line and "ms" in line:
                    try:
                        delay_str = line.split("Delay:")[1].split("ms")[0].strip()
                        delay = float(delay_str)
                        delays.append(delay)
                    except:
                        pass

                # Errors
                if "ERROR" in line:
                    metrics["errors"].append(line.strip())

            if delays:
                metrics["avg_delay_ms"] = sum(delays) / len(delays)

        return metrics

    def _generate_claude_summary(self, report: Dict, log_dir: Path, config: TestConfig):
        """Generate a Claude-friendly summary for debugging"""
        summary_path = self.report_dir / f"{config.name}_claude_summary.md"

        with open(summary_path, 'w') as f:
            f.write(f"# Test Report: {config.name}\n\n")
            f.write(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")

            f.write("## Test Configuration\n\n")
            f.write(f"- **Clients:** {config.num_clients}\n")
            f.write(f"- **Duration:** {config.duration} seconds\n")
            f.write(f"- **Test Mode:** {config.test_mode}\n")
            f.write(f"- **Packet Loss:** {config.packet_loss * 100}%\n")
            f.write(f"- **Simulated Lag:** {config.lag_ms}ms\n\n")

            f.write("## Results Summary\n\n")

            # Server results
            server = report["results"]["server"]
            f.write("### Server\n\n")
            f.write(f"- Total Snapshots: {server.get('total_snapshots', 0)}\n")
            f.write(f"- Avg Snapshot Size: {server.get('avg_snapshot_size', 0):.1f} bytes\n")
            f.write(f"- Chunk Changes: {server.get('chunk_changes', 0)}\n")
            f.write(f"- Errors: {len(server.get('errors', []))}\n\n")

            # Client results
            f.write("### Clients\n\n")
            for client in report["results"]["clients"]:
                f.write(f"#### Client {client.get('client_id', '?')}\n\n")
                f.write(f"- Snapshots Received: {client.get('snapshots_received', 0)}\n")
                f.write(f"- Player Disappearances: {client.get('player_disappearances', 0)}\n")
                f.write(f"- Interpolation Warnings: {client.get('interpolation_warnings', 0)}\n")
                f.write(f"- Baseline Mismatches: {client.get('baseline_mismatches', 0)}\n")
                f.write(f"- Avg Network Delay: {client.get('avg_delay_ms', 0):.1f}ms\n")
                f.write(f"- Errors: {len(client.get('errors', []))}\n\n")

            # Issues detected
            f.write("## Issues Detected\n\n")

            issues_found = False

            # Check for player disappearances
            for client in report["results"]["clients"]:
                if client.get('player_disappearances', 0) > 0:
                    f.write(f"⚠️ **Player Disappearance**: Client {client['client_id']} had "
                           f"{client['player_disappearances']} occurrences\n\n")
                    issues_found = True

            # Check for high interpolation warnings
            for client in report["results"]["clients"]:
                if client.get('interpolation_warnings', 0) > 10:
                    f.write(f"⚠️ **High Interpolation Warnings**: Client {client['client_id']} had "
                           f"{client['interpolation_warnings']} warnings\n\n")
                    issues_found = True

            # Check for high baseline mismatches
            for client in report["results"]["clients"]:
                mismatches = client.get('baseline_mismatches', 0)
                received = client.get('snapshots_received', 1)
                if mismatches > received * 0.1:  # More than 10% mismatches
                    f.write(f"⚠️ **High Baseline Mismatches**: Client {client['client_id']} had "
                           f"{mismatches} mismatches out of {received} snapshots "
                           f"({mismatches*100//received}%)\n\n")
                    issues_found = True

            if not issues_found:
                f.write("✅ No major issues detected!\n\n")

            # Log file references
            f.write("## Log Files\n\n")
            f.write(f"Full logs available in: `{log_dir}`\n\n")
            f.write("- Server: `server.log`\n")
            for i in range(config.num_clients):
                f.write(f"- Client {i}: `client_{i}.log`\n")

            f.write("\n---\n\n")
            f.write("## How to Use This Report with Claude Code\n\n")
            f.write("1. Read the summary above to understand what issues were found\n")
            f.write("2. If issues exist, ask Claude to read the relevant log files\n")
            f.write("3. Example prompt:\n\n")
            f.write("```\n")
            f.write(f"Claude, please read the log file at {log_dir}/client_0.log\n")
            f.write("and analyze the player disappearance errors. Look for patterns in\n")
            f.write("the delta compression deserialization and snapshot creation.\n")
            f.write("```\n")

        print(f"[FRAMEWORK] Claude summary saved to: {summary_path}")


def main():
    parser = argparse.ArgumentParser(description="Network Testing Framework")
    parser.add_argument(
        "--godot",
        default="/Applications/Godot.app/Contents/MacOS/Godot",
        help="Path to Godot executable"
    )
    parser.add_argument(
        "--project",
        default=os.getcwd(),
        help="Path to Godot project"
    )
    parser.add_argument(
        "--test",
        choices=["all", "basic", "stress", "lag", "packet_loss", "multi_client"],
        default="basic",
        help="Test scenario to run"
    )

    args = parser.parse_args()

    # Create framework
    framework = TestFramework(args.godot, args.project)

    # Define test scenarios
    tests = {
        "basic": TestConfig(
            name="basic_single_client",
            num_clients=1,
            duration=30,
            test_mode="random_walk"
        ),
        "stress": TestConfig(
            name="stress_test",
            num_clients=1,
            duration=60,
            test_mode="stress_test"
        ),
        "lag": TestConfig(
            name="high_lag_test",
            num_clients=1,
            duration=30,
            test_mode="random_walk",
            lag_ms=200
        ),
        "packet_loss": TestConfig(
            name="packet_loss_test",
            num_clients=1,
            duration=30,
            test_mode="random_walk",
            packet_loss=0.1  # 10% packet loss
        ),
        "multi_client": TestConfig(
            name="multi_client_test",
            num_clients=3,
            duration=60,
            test_mode="random_walk"
        )
    }

    # Run selected test(s)
    if args.test == "all":
        for test_config in tests.values():
            framework.run_test(test_config)
            time.sleep(5)  # Cool down between tests
    else:
        framework.run_test(tests[args.test])

    print("\n[FRAMEWORK] All tests completed!")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[FRAMEWORK] Interrupted by user")
        sys.exit(0)
