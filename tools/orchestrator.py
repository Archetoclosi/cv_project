"""
Process orchestrator for sensor data pipeline.
Manages receiver and interpreter subprocesses with auto-restart.
"""

from dataclasses import dataclass
from typing import Dict, List, Optional
import subprocess
import threading
import time
import os
import sys
import signal
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

    def register_process(self, config: ProcessConfig):
        """Register a process configuration."""
        self.process_configs[config.name] = config

    def start_all(self):
        """Start all registered processes."""
        self._create_pipe()
        self.running = True

        for name, config in self.process_configs.items():
            self._start_process(name, config)

        # Start monitor thread
        self.monitor_thread = threading.Thread(target=self._monitor_processes, daemon=True)
        self.monitor_thread.start()

    def _create_pipe(self):
        """Create named pipe if it doesn't exist."""
        try:
            if not os.path.exists(self.pipe_path):
                os.mkfifo(self.pipe_path)
                print(f"[Orchestrator] Created named pipe at {self.pipe_path}")
        except FileExistsError:
            pass
        except Exception as e:
            print(f"[Orchestrator] Error creating pipe: {e}", file=sys.stderr)

    def _start_process(self, name: str, config: ProcessConfig):
        """Start a single process."""
        print(f"[Orchestrator] Starting {name}...")

        cmd = [sys.executable, config.script] + config.args

        if config.console and (self.verbose or config.console):
            # Spawn in separate terminal
            process = self._spawn_in_terminal(name, cmd)
        else:
            # Suppress output
            stdout = subprocess.DEVNULL if not self.log_output else subprocess.PIPE
            stderr = subprocess.PIPE
            process = subprocess.Popen(
                cmd,
                stdout=stdout,
                stderr=stderr,
                cwd=os.path.dirname(os.path.abspath(__file__))
            )

        self.processes[name] = process
        print(f"[Orchestrator] Started {name} (PID: {process.pid})")

    def _spawn_in_terminal(self, name: str, cmd: list) -> subprocess.Popen:
        """Spawn process in a separate terminal window."""
        script_content = " ".join(cmd)

        if sys.platform == "darwin":  # macOS
            apple_script = f'tell application "Terminal" to do script "{script_content}"'
            subprocess.Popen(["osascript", "-e", apple_script])
        elif sys.platform.startswith("linux"):
            subprocess.Popen(["gnome-terminal", "--", "bash", "-c", script_content])
        elif sys.platform == "win32":
            subprocess.Popen(["start", "cmd", "/k", script_content], shell=True)

        # Return a mock process object for tracking
        process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return process

    def _monitor_processes(self):
        """Monitor processes and restart them if they crash."""
        while self.running:
            for name, config in self.process_configs.items():
                if name in self.processes:
                    process = self.processes[name]
                    if process.poll() is not None:  # Process exited
                        if config.restart:
                            print(f"[Orchestrator] Process {name} crashed, restarting...")
                            self._start_process(name, config)
            time.sleep(1)

    def stop_all(self):
        """Stop all processes gracefully."""
        self.running = False

        for name, process in self.processes.items():
            try:
                print(f"[Orchestrator] Stopping {name}...")
                process.terminate()
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                print(f"[Orchestrator] Force killing {name}...")
                process.kill()

        self._cleanup_pipe()
        print("[Orchestrator] All processes stopped")

    def _cleanup_pipe(self):
        """Remove named pipe."""
        try:
            if os.path.exists(self.pipe_path):
                os.remove(self.pipe_path)
                print(f"[Orchestrator] Cleaned up named pipe")
        except Exception as e:
            print(f"[Orchestrator] Error cleaning up pipe: {e}", file=sys.stderr)


def parse_arguments(args=None):
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Orchestrate sensor receiver and interpreter processes"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show raw sensor data in separate console (both receiver and interpreter output)"
    )
    parser.add_argument(
        "--log", "-l",
        action="store_true",
        help="Log receiver output to logs/receiver.log (default: suppressed)"
    )
    return parser.parse_args(args)


def main():
    """Main entry point."""
    args = parse_arguments()

    # Process configurations
    processes = [
        ProcessConfig(
            name="receiver",
            script=os.path.join(os.path.dirname(__file__), "sensor_receiver.py"),
            args=[],
            console=args.verbose,  # Show console only in verbose mode
            restart=True
        ),
        ProcessConfig(
            name="interpreter",
            script=os.path.join(os.path.dirname(__file__), "interpreter.py"),
            args=["/tmp/sensor_data", "--follow"],
            console=True,  # Always show interpreter output
            restart=True
        ),
    ]

    manager = ProcessManager(verbose=args.verbose, log_output=args.log)

    for config in processes:
        manager.register_process(config)

    # Start processes
    try:
        manager.start_all()
        # Keep running until interrupted
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[Orchestrator] Shutting down...")
        manager.stop_all()
        sys.exit(0)


if __name__ == "__main__":
    main()
