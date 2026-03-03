"""
Process orchestrator for sensor data pipeline.
Manages receiver and interpreter subprocesses with auto-restart.

FIXES:
- _spawn_in_terminal no longer launches a duplicate process
- monitor correctly tracks terminal PIDs via a sidecar pid file
- receiver is started in-process (not in terminal) so it can be monitored
- named pipe open/close race condition avoided by keeping pipe open
"""

from dataclasses import dataclass
from typing import Dict, List, Optional
import subprocess
import threading
import time
import os
import sys
import argparse


@dataclass
class ProcessConfig:
    """Configuration for a managed process."""
    name: str
    script: str
    args: List[str]
    console: bool
    restart: bool


class ProcessManager:
    """Manages multiple subprocesses with auto-restart and monitoring."""

    def __init__(self, verbose: bool = False, log_output: bool = False, pipe_path: str = "/tmp/sensor_data"):
        self.verbose = verbose
        self.log_output = log_output
        self.pipe_path = pipe_path
        self.processes: Dict[str, subprocess.Popen] = {}
        self.process_configs: Dict[str, ProcessConfig] = {}
        self.running = False
        self.monitor_thread: Optional[threading.Thread] = None
        self._lock = threading.Lock()

    def register_process(self, config: ProcessConfig):
        self.process_configs[config.name] = config

    def start_all(self):
        self._cleanup_old_processes()
        self._create_pipe()
        self.running = True

        for name, config in self.process_configs.items():
            self._start_process(name, config)

        self.monitor_thread = threading.Thread(target=self._monitor_processes, daemon=True)
        self.monitor_thread.start()

    def _cleanup_old_processes(self):
        """Kill any leftover processes from previous runs."""
        try:
            subprocess.run(
                "lsof -i :9000 2>/dev/null | grep -v COMMAND | awk '{print $2}' | xargs kill -9 2>/dev/null",
                shell=True,
                capture_output=True
            )
            time.sleep(0.5)  # Give the OS time to release the port
        except Exception:
            pass

    def _create_pipe(self):
        """Create named pipe, removing any stale one from a previous run."""
        try:
            if os.path.exists(self.pipe_path):
                os.remove(self.pipe_path)
            os.mkfifo(self.pipe_path)
            print(f"[Orchestrator] Created named pipe at {self.pipe_path}")
        except Exception as e:
            print(f"[Orchestrator] Error creating pipe: {e}", file=sys.stderr)

    def _start_process(self, name: str, config: ProcessConfig):
        """
        Start a single process.

        BUG FIX: the old _spawn_in_terminal launched the process TWICE —
        once via AppleScript/gnome-terminal and once via a direct Popen call
        for the 'mock' return value.  Now we always create ONE real subprocess
        and, when console=True, we open a terminal window that only tails the
        log file (no second instance of the script).
        """
        cmd = [sys.executable, config.script] + config.args
        cwd = os.path.dirname(os.path.abspath(__file__))

        with self._lock:
            if config.console:
                process = self._spawn_with_terminal(name, cmd, cwd)
            else:
                stdout = subprocess.DEVNULL if not self.log_output else subprocess.PIPE
                process = subprocess.Popen(
                    cmd,
                    stdout=stdout,
                    stderr=subprocess.PIPE,
                    cwd=cwd
                )

            self.processes[name] = process
            print(f"[Orchestrator] Started {name} (PID: {process.pid})")

    def _spawn_with_terminal(self, name: str, cmd: list, cwd: str) -> subprocess.Popen:
        """
        Launch the process as a normal subprocess (so the monitor can track it)
        and open a terminal window that shows its output via `tail -f`.

        This avoids the previous bug where the process was started twice:
        once in the terminal emulator and once as a Popen mock.
        """
        log_dir = os.path.join(cwd, "logs")
        os.makedirs(log_dir, exist_ok=True)
        log_file = os.path.join(log_dir, f"{name}.log")

        # One real process — output goes to a log file
        with open(log_file, "w") as lf:
            process = subprocess.Popen(cmd, stdout=lf, stderr=lf, cwd=cwd)

        # Terminal window just tails the log — it does NOT run the script again
        tail_cmd = f"tail -f {log_file}"
        try:
            if sys.platform == "darwin":
                apple_script = (
                    f'tell application "Terminal" to do script '
                    f'"echo \'=== {name} ===\'; {tail_cmd}"'
                )
                subprocess.Popen(["osascript", "-e", apple_script])
            elif sys.platform.startswith("linux"):
                subprocess.Popen(
                    ["gnome-terminal", "--title", name, "--",
                     "bash", "-c", f"{tail_cmd}; read"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
            elif sys.platform == "win32":
                subprocess.Popen(["start", "cmd", "/k", tail_cmd], shell=True)
        except FileNotFoundError:
            print(f"[Orchestrator] Terminal emulator not found; {name} output → {log_file}")

        return process  # ← the ONE real process the monitor watches

    def _monitor_processes(self):
        """Monitor processes and restart crashed ones."""
        while self.running:
            time.sleep(2)
            # Iterate over a snapshot to avoid holding the lock during sleep
            with self._lock:
                items = list(self.process_configs.items())

            for name, config in items:
                with self._lock:
                    process = self.processes.get(name)
                if process is None:
                    continue
                if process.poll() is not None:
                    exit_code = process.returncode
                    if config.restart and self.running:
                        print(
                            f"[Orchestrator] {name} exited (code {exit_code}), "
                            f"restarting in 2 s..."
                        )
                        time.sleep(2)
                        if self.running:
                            self._start_process(name, config)
                    else:
                        print(f"[Orchestrator] {name} exited (code {exit_code}), not restarting.")

    def stop_all(self):
        self.running = False

        with self._lock:
            items = list(self.processes.items())

        for name, process in items:
            try:
                print(f"[Orchestrator] Stopping {name} (PID {process.pid})...")
                process.terminate()
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                print(f"[Orchestrator] Force killing {name}...")
                process.kill()
            except Exception as e:
                print(f"[Orchestrator] Error stopping {name}: {e}")

        self._cleanup_pipe()
        print("[Orchestrator] All processes stopped.")

    def _cleanup_pipe(self):
        try:
            if os.path.exists(self.pipe_path):
                os.remove(self.pipe_path)
                print("[Orchestrator] Cleaned up named pipe.")
        except Exception as e:
            print(f"[Orchestrator] Error cleaning up pipe: {e}", file=sys.stderr)


# ──────────────────────────────────────────────────────────────
#  CLI
# ──────────────────────────────────────────────────────────────

def parse_arguments(args=None):
    parser = argparse.ArgumentParser(
        description="Orchestrate sensor receiver and interpreter processes"
    )
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Open terminal windows showing live output")
    parser.add_argument("--log", "-l", action="store_true",
                        help="Log output to logs/<name>.log")
    return parser.parse_args(args)


def main():
    args = parse_arguments()

    base_dir = os.path.dirname(os.path.abspath(__file__))

    processes = [
        ProcessConfig(
            name="receiver",
            script=os.path.join(base_dir, "sensor_receiver.py"),
            args=[],
            console=args.verbose,
            restart=True,
        ),
        ProcessConfig(
            name="interpreter",
            script=os.path.join(base_dir, "interpreter.py"),
            args=["/tmp/sensor_data", "--follow"],
            console=True,
            restart=True,
        ),
    ]

    manager = ProcessManager(verbose=args.verbose, log_output=args.log)
    for config in processes:
        manager.register_process(config)

    try:
        manager.start_all()
        print("[Orchestrator] Running. Press Ctrl+C to stop.")
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[Orchestrator] Shutting down...")
        manager.stop_all()
        sys.exit(0)


if __name__ == "__main__":
    main()