#!/usr/bin/env python3
"""
Advanced Log Analysis Tool for Snapshot Interpolation Testing

Parses structured logs from test runs and generates detailed reports
with Claude-friendly summaries for debugging.
"""

import re
import json
import argparse
from pathlib import Path
from typing import Dict, List, Tuple
from dataclasses import dataclass, field
from collections import defaultdict


@dataclass
class LogEntry:
    """Structured log entry"""
    timestamp: float
    level: str
    category: str
    message: str
    metadata: Dict = field(default_factory=dict)
    raw_line: str = ""


@dataclass
class AnalysisResult:
    """Analysis results for a single log file"""
    filename: str
    total_lines: int = 0
    entries: List[LogEntry] = field(default_factory=list)

    # Counters
    errors: int = 0
    warnings: int = 0
    info: int = 0
    debug: int = 0

    # Networking metrics
    snapshots_sent: int = 0
    snapshots_received: int = 0
    packet_loss_events: int = 0
    baseline_mismatches: int = 0
    player_disappearances: int = 0
    interpolation_warnings: int = 0

    # Chunk system
    chunk_changes: int = 0

    # Issues detected
    critical_issues: List[str] = field(default_factory=list)
    warnings_list: List[str] = field(default_factory=list)

    # Timing
    start_time: float = 0.0
    end_time: float = 0.0


class LogAnalyzer:
    """Parse and analyze structured logs"""

    # Log format: [timestamp] [level] [category] message | key=value ...
    LOG_PATTERN = re.compile(
        r'\[(\d+\.\d+)\]\s+\[(\w+)\]\s+\[([^\]]+)\]\s+([^|]+)(?:\s*\|\s*(.+))?'
    )

    def __init__(self, log_path: Path):
        self.log_path = log_path
        self.result = AnalysisResult(filename=str(log_path))

    def parse(self) -> AnalysisResult:
        """Parse the entire log file"""
        print(f"[ANALYZER] Parsing {self.log_path}...")

        with open(self.log_path, 'r') as f:
            for line in f:
                self.result.total_lines += 1
                entry = self._parse_line(line.strip())

                if entry:
                    self.result.entries.append(entry)
                    self._update_metrics(entry)

        # Calculate timing
        if self.result.entries:
            self.result.start_time = self.result.entries[0].timestamp
            self.result.end_time = self.result.entries[-1].timestamp

        # Detect issues
        self._detect_issues()

        print(f"[ANALYZER] Parsed {len(self.result.entries)} structured log entries "
              f"from {self.result.total_lines} total lines")

        return self.result

    def _parse_line(self, line: str) -> LogEntry:
        """Parse a single log line"""
        match = self.LOG_PATTERN.match(line)

        if not match:
            # Not a structured log, skip
            return None

        timestamp = float(match.group(1))
        level = match.group(2)
        category = match.group(3)
        message = match.group(4).strip()
        metadata_str = match.group(5)

        metadata = {}
        if metadata_str:
            # Parse key=value pairs
            for pair in metadata_str.split():
                if '=' in pair:
                    key, value = pair.split('=', 1)
                    metadata[key] = value

        return LogEntry(
            timestamp=timestamp,
            level=level,
            category=category,
            message=message,
            metadata=metadata,
            raw_line=line
        )

    def _update_metrics(self, entry: LogEntry):
        """Update metrics based on log entry"""
        # Count by level
        if entry.level == "ERROR":
            self.result.errors += 1
        elif entry.level == "WARN":
            self.result.warnings += 1
        elif entry.level == "INFO":
            self.result.info += 1
        elif entry.level == "DEBUG":
            self.result.debug += 1

        # Count specific events
        if entry.category == "SERVER_SNAPSHOT":
            self.result.snapshots_sent += 1

        if entry.category == "CLIENT_SNAPSHOT":
            self.result.snapshots_received += 1

        if "packet loss" in entry.message.lower():
            self.result.packet_loss_events += 1

        if entry.category == "CLIENT_DELTA" and "mismatch" in entry.message.lower():
            self.result.baseline_mismatches += 1

        if entry.category == "CLIENT_ERROR" and "missing" in entry.message.lower():
            self.result.player_disappearances += 1

        if entry.category == "INTERPOLATOR" and entry.level == "WARN":
            self.result.interpolation_warnings += 1

        if entry.category == "SERVER_CHUNK" and "changed chunk" in entry.message.lower():
            self.result.chunk_changes += 1

    def _detect_issues(self):
        """Detect common issues from parsed entries"""

        # Issue 1: High player disappearance rate
        if self.result.player_disappearances > 0:
            self.result.critical_issues.append(
                f"Player disappearance detected {self.result.player_disappearances} times! "
                f"This indicates delta compression bugs or interest management issues."
            )

        # Issue 2: High interpolation warnings
        if self.result.interpolation_warnings > 10:
            self.result.warnings_list.append(
                f"High interpolation warnings ({self.result.interpolation_warnings}). "
                f"Client may be struggling to keep buffer filled."
            )

        # Issue 3: High baseline mismatch rate
        if self.result.snapshots_received > 0:
            mismatch_rate = self.result.baseline_mismatches / self.result.snapshots_received
            if mismatch_rate > 0.1:  # More than 10% mismatches
                self.result.warnings_list.append(
                    f"High baseline mismatch rate ({mismatch_rate*100:.1f}%). "
                    f"This is expected for UDP but seems unusually high."
                )

        # Issue 4: No snapshots received/sent
        if self.result.snapshots_sent == 0 and "server" in str(self.log_path).lower():
            self.result.critical_issues.append(
                "Server sent 0 snapshots! Server may not be running correctly."
            )

        if self.result.snapshots_received == 0 and "client" in str(self.log_path).lower():
            self.result.critical_issues.append(
                "Client received 0 snapshots! Client may not be connected."
            )


class ReportGenerator:
    """Generate comprehensive reports from analysis results"""

    def __init__(self, results: List[AnalysisResult], output_dir: Path):
        self.results = results
        self.output_dir = output_dir
        self.output_dir.mkdir(exist_ok=True)

    def generate_all(self):
        """Generate all report formats"""
        print("[REPORT] Generating reports...")

        # JSON report (machine-readable)
        self.generate_json_report()

        # Markdown report (human-readable)
        self.generate_markdown_report()

        # Claude-friendly summary
        self.generate_claude_summary()

        print(f"[REPORT] Reports saved to {self.output_dir}")

    def generate_json_report(self):
        """Generate JSON report"""
        report_path = self.output_dir / "analysis_report.json"

        report_data = {
            "files": [],
            "summary": self._calculate_summary()
        }

        for result in self.results:
            report_data["files"].append({
                "filename": result.filename,
                "total_lines": result.total_lines,
                "entries": len(result.entries),
                "errors": result.errors,
                "warnings": result.warnings,
                "snapshots_sent": result.snapshots_sent,
                "snapshots_received": result.snapshots_received,
                "packet_loss_events": result.packet_loss_events,
                "baseline_mismatches": result.baseline_mismatches,
                "player_disappearances": result.player_disappearances,
                "interpolation_warnings": result.interpolation_warnings,
                "chunk_changes": result.chunk_changes,
                "critical_issues": result.critical_issues,
                "warnings_list": result.warnings_list,
                "duration": result.end_time - result.start_time
            })

        with open(report_path, 'w') as f:
            json.dump(report_data, f, indent=2)

        print(f"[REPORT] JSON report: {report_path}")

    def generate_markdown_report(self):
        """Generate human-readable Markdown report"""
        report_path = self.output_dir / "analysis_report.md"

        with open(report_path, 'w') as f:
            f.write("# Log Analysis Report\n\n")

            # Summary
            summary = self._calculate_summary()
            f.write("## Overall Summary\n\n")
            f.write(f"- **Total Errors:** {summary['total_errors']}\n")
            f.write(f"- **Total Warnings:** {summary['total_warnings']}\n")
            f.write(f"- **Total Snapshots Sent:** {summary['total_snapshots_sent']}\n")
            f.write(f"- **Total Snapshots Received:** {summary['total_snapshots_received']}\n")
            f.write(f"- **Player Disappearances:** {summary['total_player_disappearances']}\n")
            f.write(f"- **Interpolation Warnings:** {summary['total_interpolation_warnings']}\n\n")

            # Issues
            if summary['has_critical_issues']:
                f.write("## ⚠️ Critical Issues Detected\n\n")
                for result in self.results:
                    if result.critical_issues:
                        f.write(f"### {Path(result.filename).name}\n\n")
                        for issue in result.critical_issues:
                            f.write(f"- ❌ {issue}\n")
                        f.write("\n")

            if summary['has_warnings']:
                f.write("## ⚠️ Warnings\n\n")
                for result in self.results:
                    if result.warnings_list:
                        f.write(f"### {Path(result.filename).name}\n\n")
                        for warning in result.warnings_list:
                            f.write(f"- ⚠️ {warning}\n")
                        f.write("\n")

            # Per-file details
            f.write("## Per-File Analysis\n\n")
            for result in self.results:
                f.write(f"### {Path(result.filename).name}\n\n")
                f.write(f"- **Duration:** {result.end_time - result.start_time:.1f}s\n")
                f.write(f"- **Total Lines:** {result.total_lines}\n")
                f.write(f"- **Structured Entries:** {len(result.entries)}\n")
                f.write(f"- **Errors:** {result.errors}\n")
                f.write(f"- **Warnings:** {result.warnings}\n")
                f.write(f"- **Snapshots Sent:** {result.snapshots_sent}\n")
                f.write(f"- **Snapshots Received:** {result.snapshots_received}\n")
                f.write(f"- **Packet Loss Events:** {result.packet_loss_events}\n")
                f.write(f"- **Baseline Mismatches:** {result.baseline_mismatches}\n")
                f.write(f"- **Player Disappearances:** {result.player_disappearances}\n")
                f.write(f"- **Chunk Changes:** {result.chunk_changes}\n\n")

        print(f"[REPORT] Markdown report: {report_path}")

    def generate_claude_summary(self):
        """Generate Claude-friendly debugging summary"""
        summary_path = self.output_dir / "claude_debug_summary.md"

        with open(summary_path, 'w') as f:
            f.write("# Network Testing Debug Summary for Claude Code\n\n")
            f.write("This report summarizes test results for the snapshot interpolation system.\n\n")

            summary = self._calculate_summary()

            # Quick status
            f.write("## Quick Status\n\n")
            if not summary['has_critical_issues'] and not summary['has_warnings']:
                f.write("✅ **All tests passed!** No critical issues detected.\n\n")
            else:
                f.write("⚠️ **Issues detected.** See details below.\n\n")

            # Critical issues
            if summary['has_critical_issues']:
                f.write("## 🔴 Critical Issues Requiring Immediate Attention\n\n")
                for result in self.results:
                    if result.critical_issues:
                        f.write(f"### File: `{result.filename}`\n\n")
                        for issue in result.critical_issues:
                            f.write(f"**Issue:** {issue}\n\n")
                            f.write(self._suggest_fix(issue))
                            f.write("\n")

            # Warnings
            if summary['has_warnings']:
                f.write("## ⚠️ Warnings (May Need Investigation)\n\n")
                for result in self.results:
                    if result.warnings_list:
                        f.write(f"### File: `{result.filename}`\n\n")
                        for warning in result.warnings_list:
                            f.write(f"**Warning:** {warning}\n\n")

            # Recommendations
            f.write("## Recommendations\n\n")
            f.write(self._generate_recommendations(summary))

            # Claude prompts
            f.write("## Suggested Claude Code Prompts\n\n")
            f.write(self._generate_claude_prompts(summary))

        print(f"[REPORT] Claude summary: {summary_path}")

    def _calculate_summary(self) -> Dict:
        """Calculate overall summary statistics"""
        summary = {
            "total_errors": 0,
            "total_warnings": 0,
            "total_snapshots_sent": 0,
            "total_snapshots_received": 0,
            "total_player_disappearances": 0,
            "total_interpolation_warnings": 0,
            "has_critical_issues": False,
            "has_warnings": False
        }

        for result in self.results:
            summary["total_errors"] += result.errors
            summary["total_warnings"] += result.warnings
            summary["total_snapshots_sent"] += result.snapshots_sent
            summary["total_snapshots_received"] += result.snapshots_received
            summary["total_player_disappearances"] += result.player_disappearances
            summary["total_interpolation_warnings"] += result.interpolation_warnings

            if result.critical_issues:
                summary["has_critical_issues"] = True
            if result.warnings_list:
                summary["has_warnings"] = True

        return summary

    def _suggest_fix(self, issue: str) -> str:
        """Suggest fixes for common issues"""
        if "disappearance" in issue.lower():
            return """
**Likely Cause:** Delta compression deserialization bug or interest management issue.

**Files to Check:**
- `scripts/entity_snapshot.gd` (lines 150-180) - Delta compression logic
- `scripts/server_world.gd` (lines 230-330) - Interest management

**What to Look For:**
- Ensure deserialization reads "changed" bit only for entities that exist in baseline
- Verify player entity is always included in snapshot (should be at index 0)
- Check if interest area calculation includes player's own position
"""

        if "interpolation warnings" in issue.lower():
            return """
**Likely Cause:** Network delay too high or client falling behind server.

**Solutions:**
- Increase `INTERPOLATION_DELAY` in `scripts/network_config.gd`
- Check if client is receiving snapshots at expected rate
- Verify server tick rate matches configuration
"""

        if "baseline mismatch" in issue.lower():
            return """
**Likely Cause:** Out-of-order packet delivery (normal for UDP).

**Expected Behavior:** Occasional mismatches are normal. High rates (>10%) indicate network issues.

**Solutions:**
- If rate is very high, check network quality
- Consider implementing sequence buffering for out-of-order packets
"""

        return "No specific suggestion available.\n"

    def _generate_recommendations(self, summary: Dict) -> str:
        """Generate recommendations based on summary"""
        recommendations = []

        if summary["total_player_disappearances"] > 0:
            recommendations.append(
                "1. **Fix delta compression:** Player disappearances indicate a critical bug. "
                "Review `DELTA_COMPRESSION_BUG.md` and verify the fix is applied."
            )

        if summary["total_interpolation_warnings"] > 50:
            recommendations.append(
                "2. **Tune interpolation buffer:** High interpolation warnings suggest buffer tuning needed. "
                "Consider increasing `INTERPOLATION_DELAY` in `network_config.gd`."
            )

        if not recommendations:
            recommendations.append("✅ No recommendations - system is working as expected!")

        return "\n".join(recommendations) + "\n\n"

    def _generate_claude_prompts(self, summary: Dict) -> str:
        """Generate suggested prompts for Claude Code"""
        prompts = []

        if summary["has_critical_issues"]:
            prompts.append("""
### For Critical Issues:

```
Claude, please analyze the critical issues in the test logs. Focus on:

1. Read the log files listed in the report
2. Identify patterns in player disappearance errors
3. Check the delta compression logic in scripts/entity_snapshot.gd
4. Verify the interest management in scripts/server_world.gd

Provide a detailed analysis of what's going wrong and suggest fixes.
```
""")

        prompts.append("""
### For Performance Analysis:

```
Claude, please analyze the network performance from these test logs:

1. Calculate average snapshot sizes and compression ratios
2. Identify bandwidth usage patterns
3. Check if tick rates match configuration
4. Verify interpolation buffer is maintained correctly

Generate a performance report with optimization suggestions.
```
""")

        return "\n".join(prompts)


def main():
    parser = argparse.ArgumentParser(description="Analyze test logs")
    parser.add_argument("log_dir", help="Directory containing log files")
    parser.add_argument(
        "--output",
        default="test_reports",
        help="Output directory for reports"
    )

    args = parser.parse_args()

    log_dir = Path(args.log_dir)
    output_dir = Path(args.output)

    if not log_dir.exists():
        print(f"Error: Log directory not found: {log_dir}")
        return 1

    # Find all log files
    log_files = list(log_dir.glob("*.log"))

    if not log_files:
        print(f"Error: No log files found in {log_dir}")
        return 1

    print(f"[ANALYZER] Found {len(log_files)} log files")

    # Analyze each file
    results = []
    for log_file in log_files:
        analyzer = LogAnalyzer(log_file)
        result = analyzer.parse()
        results.append(result)

    # Generate reports
    report_gen = ReportGenerator(results, output_dir)
    report_gen.generate_all()

    print("\n[ANALYZER] Analysis complete!")

    return 0


if __name__ == "__main__":
    exit(main())
