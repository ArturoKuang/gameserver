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
import shutil
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
        jitter_ms: int = 0,
        bandwidth_kbps: float = 0.0,
        duplicate_rate: float = 0.0,
        interp_delay: Optional[float] = None,
        jitter_buf: Optional[float] = None,
        enable_client_prediction: bool = False
    ):
        self.name = name
        self.num_clients = num_clients
        self.duration = duration
        self.test_mode = test_mode  # random_walk, stress_test, chunk_crossing, circle_pattern
        self.packet_loss = packet_loss
        self.lag_ms = lag_ms
        self.jitter_ms = jitter_ms
        self.bandwidth_kbps = bandwidth_kbps
        self.duplicate_rate = duplicate_rate
        self.interp_delay = interp_delay
        self.jitter_buf = jitter_buf
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
        lag_ms: int = 0,
        jitter_ms: int = 0,
        bandwidth_kbps: float = 0.0,
        duplicate_rate: float = 0.0,
        interp_delay: Optional[float] = None,
        jitter_buf: Optional[float] = None
    ):
        self.godot_path = godot_path
        self.project_path = project_path
        self.log_path = log_path
        self.is_server = is_server
        self.test_mode = test_mode
        self.client_id = client_id
        self.packet_loss = packet_loss
        self.lag_ms = lag_ms
        self.jitter_ms = jitter_ms
        self.bandwidth_kbps = bandwidth_kbps
        self.duplicate_rate = duplicate_rate
        self.interp_delay = interp_delay
        self.jitter_buf = jitter_buf
        self.process: Optional[subprocess.Popen] = None

    def start(self):
        """Start the Godot process"""
        args = [self.godot_path, "--path", self.project_path]

        # Base environment variables
        env = os.environ.copy()
        
        # Network Configuration Overrides
        if self.interp_delay is not None:
            env["NET_CFG_INTERP_DELAY"] = str(self.interp_delay)
        if self.jitter_buf is not None:
            env["NET_CFG_JITTER_BUF"] = str(self.jitter_buf)

        if self.is_server:
            args.append("--headless")
            env["TEST_MODE"] = "server"
        else:
            # Client test mode environment variables
            args.append("--headless") # Default to headless for automation
            env["TEST_MODE"] = "client"
            env["TEST_CLIENT_ID"] = str(self.client_id)
            env["TEST_BEHAVIOR"] = self.test_mode
            env["TEST_PACKET_LOSS"] = str(self.packet_loss)
            env["TEST_LAG_MS"] = str(self.lag_ms)
            env["TEST_JITTER_MS"] = str(self.jitter_ms)
            env["TEST_BW_KBPS"] = str(self.bandwidth_kbps)
            env["TEST_DUPLICATE_RATE"] = str(self.duplicate_rate)

        # Open log file
        log_file = open(self.log_path, 'w')

        # Start process
        self.process = subprocess.Popen(
            args,
            stdout=log_file,
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
        print(f"Test Mode: {config.test_mode}")
        print(f"Net Profile: Loss={config.packet_loss*100}%, Lag={config.lag_ms}ms, "
              f"Jitter={config.jitter_ms}ms, BW={config.bandwidth_kbps}KB/s, Dup={config.duplicate_rate*100}%")
        if config.interp_delay:
            print(f"Override Interp Delay: {config.interp_delay}s")
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
                is_server=True,
                interp_delay=config.interp_delay,
                jitter_buf=config.jitter_buf
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
                    lag_ms=config.lag_ms,
                    jitter_ms=config.jitter_ms,
                    bandwidth_kbps=config.bandwidth_kbps,
                    duplicate_rate=config.duplicate_rate,
                    interp_delay=config.interp_delay,
                    jitter_buf=config.jitter_buf
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
                          f"Server: {{'✓' if self.server.is_alive() else '✗'}} | "
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

            # Generate Agent-friendly summary
            self._generate_agent_summary(report, test_log_dir, config)

            print(f"REPORT_JSON:{report_path}") # Key signal for CLI agent
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

        # explicit log paths for machine consumption (absolute paths)
        log_files = {
            "server": str(log_dir.resolve() / "server.log")
        }
        for i in range(config.num_clients):
            log_files[f"client_{i}"] = str(log_dir.resolve() / f"client_{i}.log")

        # expanded network profile
        network_profile = {
            "packet_loss_percent": config.packet_loss * 100,
            "lag_base_ms": config.lag_ms,
            "jitter_ms": config.jitter_ms,
            "bandwidth_cap_kbps": config.bandwidth_kbps,
            "duplicate_percent": config.duplicate_rate * 100,
            "jitter_buffer_ms": config.jitter_buf if config.jitter_buf else "default",
            "interpolation_delay_s": config.interp_delay if config.interp_delay else "default"
        }

        report = {
            "test_name": config.name,
            "timestamp": datetime.now().isoformat(),
            "config": {
                "num_clients": config.num_clients,
                "duration": config.duration,
                "test_mode": config.test_mode,
            },
            "network_profile": network_profile,
            "log_files": log_files,
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
            "buffer_underruns": 0,
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
                
                if "Buffer underrun" in line or "stutter" in line.lower():
                    metrics["buffer_underruns"] += 1

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

    def _generate_agent_summary(self, report: Dict, log_dir: Path, config: TestConfig):
        """Generate a Agent-friendly summary for debugging"""
        summary_path = self.report_dir / f"{config.name}_summary.md"

        with open(summary_path, 'w') as f:
            f.write(f"# Test Report: {config.name}\n\n")
            f.write(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")

            f.write("## Test Configuration\n\n")
            f.write(f"- **Clients:** {config.num_clients}\n")
            f.write(f"- **Duration:** {config.duration} seconds\n")
            f.write(f"- **Test Mode:** {config.test_mode}\n")
            f.write(f"- **Packet Loss:** {config.packet_loss * 100}%\n")
            f.write(f"- **Simulated Lag:** {config.lag_ms}ms\n")
            f.write(f"- **Jitter:** {config.jitter_ms}ms\n")
            f.write(f"- **Bandwidth Limit:** {config.bandwidth_kbps} KB/s\n")
            f.write(f"- **Duplication Rate:** {config.duplicate_rate * 100}%\n\n")
            if config.interp_delay:
                f.write(f"- **Interp Delay Override:** {config.interp_delay}s\n")

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
                f.write(f"- Buffer Underruns: {client.get('buffer_underruns', 0)}\n")
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

            # Check for buffer underruns
            for client in report["results"]["clients"]:
                if client.get('buffer_underruns', 0) > 0:
                    f.write(f"⚠️ **Buffer Underrun**: Client {client['client_id']} had "
                           f"{client['buffer_underruns']} stutters\n\n")
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
                
        print(f"[FRAMEWORK] Summary saved to: {summary_path}")

def find_godot_executable():
    # Check environment variable
    if "GODOT_PATH" in os.environ:
        return os.environ["GODOT_PATH"]
    
    # Check common command names in PATH
    common_names = ["godot4", "godot"]
    for name in common_names:
        path = shutil.which(name)
        if path:
            return path
            
    # Check common macOS path
    macos_path = "/Applications/Godot.app/Contents/MacOS/Godot"
    if os.path.exists(macos_path):
        return macos_path
        
    # Check common Linux paths (e.g. flatpak or steam) - simplified
    linux_path = "/usr/bin/godot"
    if os.path.exists(linux_path):
        return linux_path

    return None

def main():
    parser = argparse.ArgumentParser(description="Network Testing Framework")
    parser.add_argument(
        "--godot",
        help="Path to Godot executable"
    )
    parser.add_argument(
        "--project",
        default=os.getcwd(),
        help="Path to Godot project"
    )
    parser.add_argument(
        "--test",
        choices=["all", "basic", "stress", "lag", "packet_loss", "multi_client", "jitter", "bad_network", "custom"],
        default="basic",
        help="Test scenario to run"
    )
    
    # Custom test args
    parser.add_argument("--clients", type=int, default=1)
    parser.add_argument("--duration", type=int, default=30)
    parser.add_argument("--mode", default="random_walk")
    parser.add_argument("--lag", type=int, default=0)
    parser.add_argument("--loss", type=float, default=0.0)
    parser.add_argument("--jitter", type=int, default=0)
    parser.add_argument("--bw", type=float, default=0.0)
    parser.add_argument("--duplicate", type=float, default=0.0)
    parser.add_argument("--json-out", action="store_true", help="Ensure JSON path is last output")

    args = parser.parse_args()

    # Find Godot
    godot_path = args.godot or find_godot_executable()
    if not godot_path:
        print("ERROR: Godot executable not found. Please set GODOT_PATH or pass --godot.")
        sys.exit(1)

    # Create framework
    framework = TestFramework(godot_path, args.project)

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
        ),
        "jitter": TestConfig(
            name="high_jitter_test",
            num_clients=1,
            duration=30,
            test_mode="random_walk",
            lag_ms=100,
            jitter_ms=50  # High jitter
        ),
        "bad_network": TestConfig(
            name="bad_network_chaos",
            num_clients=2,
            duration=60,
            test_mode="stress_test",
            packet_loss=0.05,
            lag_ms=150,
            jitter_ms=40,
            duplicate_rate=0.02
        )
    }

    # Run selected test(s)
    if args.test == "all":
        for test_config in tests.values():
            framework.run_test(test_config)
            time.sleep(5)  # Cool down between tests
    elif args.test == "custom":
        config = TestConfig(
            name="custom_test",
            num_clients=args.clients,
            duration=args.duration,
            test_mode=args.mode,
            lag_ms=args.lag,
            packet_loss=args.loss,
            jitter_ms=args.jitter,
            bandwidth_kbps=args.bw,
            duplicate_rate=args.duplicate
        )
        framework.run_test(config)
    else:
        framework.run_test(tests[args.test])

    print("\n[FRAMEWORK] All tests completed!")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[FRAMEWORK] Interrupted by user")
        sys.exit(0)
