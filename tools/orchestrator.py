"""
Process orchestrator for sensor data pipeline.
Manages receiver and interpreter subprocesses with auto-restart.
Cross-platform: macOS, Linux, Windows.
"""

from dataclasses import dataclass
from typing import Dict, List, Optional
import subprocess
import tempfile
import threading
import time
import os
import sys
import argparse


@dataclass
class ProcessConfig:
    name: str
    script: str
    args: List[str]
    console: bool
    restart: bool


class ProcessManager:

    def __init__(self, verbose: bool = False, log_output: bool = False, pipe_path: str = ""):
        self.verbose = verbose
        self.log_output = log_output
        self.pipe_path = pipe_path or os.path.join(tempfile.gettempdir(), "sensor_data")
        self.processes: Dict[str, subprocess.Popen] = {}
        self.process_configs: Dict[str, ProcessConfig] = {}
        self._log_files: Dict[str, object] = {}
        self.running = False
        self.monitor_thread: Optional[threading.Thread] = None
        self._lock = threading.Lock()

    def register_process(self, config: ProcessConfig):
        self.process_configs[config.name] = config

    def start_all(self):
        self._cleanup_old_processes()
        self._create_data_file()
        self.running = True
        for name, config in self.process_configs.items():
            self._start_process(name, config)
        self.monitor_thread = threading.Thread(target=self._monitor_processes, daemon=True)
        self.monitor_thread.start()

    def _cleanup_old_processes(self):
        try:
            if sys.platform == "win32":
                result = subprocess.run(
                    "netstat -ano", shell=True, capture_output=True, text=True
                )
                killed = set()
                for line in result.stdout.splitlines():
                    if ":9000" in line:
                        parts = line.split()
                        pid = parts[-1]
                        if pid.isdigit() and pid != "0" and pid not in killed:
                            subprocess.run(f"taskkill /PID {pid} /F",
                                           shell=True, capture_output=True)
                            killed.add(pid)
                            print(f"[Orchestrator] Killed stale process PID {pid} on port 9000")
            else:
                subprocess.run(
                    "lsof -i :9000 2>/dev/null | grep -v COMMAND | awk '{print $2}' | xargs kill -9 2>/dev/null",
                    shell=True, capture_output=True
                )
            time.sleep(1.0)
        except Exception:
            pass

    def _create_data_file(self):
        """
        Create/reset the data file.
        On Windows, os.remove() fails with WinError 32 if the file is still
        held open by a previous receiver process.  We wait for it to be
        released (up to 5 s) and fall back to truncating in-place if needed.
        """
        if os.path.exists(self.pipe_path):
            for attempt in range(10):
                try:
                    os.remove(self.pipe_path)
                    break
                except PermissionError:
                    # File still locked by a dying process — wait and retry
                    time.sleep(0.5)
            else:
                # Could not delete — truncate in place instead
                try:
                    open(self.pipe_path, "w").close()
                    print(f"[Orchestrator] Reset data file at {self.pipe_path}")
                    return
                except Exception as e:
                    print(f"[Orchestrator] Error resetting data file: {e}", file=sys.stderr)
                    return
        try:
            open(self.pipe_path, "w").close()
            print(f"[Orchestrator] Created data file at {self.pipe_path}")
        except Exception as e:
            print(f"[Orchestrator] Error creating data file: {e}", file=sys.stderr)

    def _open_log(self, name: str, cwd: str):
        log_dir = os.path.join(cwd, "logs")
        os.makedirs(log_dir, exist_ok=True)
        log_file = os.path.join(log_dir, f"{name}.log")
        lf = open(log_file, "w", encoding="utf-8")
        self._log_files[name] = lf
        return lf, log_file

    def _start_process(self, name: str, config: ProcessConfig):
        cmd = [sys.executable, config.script] + config.args
        cwd = os.path.dirname(os.path.abspath(__file__))

        with self._lock:
            lf, log_file = self._open_log(name, cwd)

            # Always launch as a normal subprocess (trackable by monitor).
            # On Windows, CREATE_NEW_CONSOLE opens a visible window natively
            # without needing a shell wrapper — this is the reliable way.
            if sys.platform == "win32" and config.console:
                process = subprocess.Popen(
                    cmd,
                    stdout=lf,
                    stderr=lf,
                    cwd=cwd,
                    creationflags=subprocess.CREATE_NEW_CONSOLE
                )
            else:
                process = subprocess.Popen(
                    cmd,
                    stdout=lf,
                    stderr=lf,
                    cwd=cwd
                )
                # On macOS/Linux open a tail window for visibility
                if config.console:
                    self._open_tail_window(name, log_file)

            self.processes[name] = process
            print(f"[Orchestrator] Started {name} (PID: {process.pid})")

    def _open_tail_window(self, name: str, log_file: str):
        """Open a terminal window that tails the log (macOS/Linux only)."""
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
        except FileNotFoundError:
            print(f"[Orchestrator] Terminal not found; {name} output -> {log_file}")

    def _monitor_processes(self):
        while self.running:
            time.sleep(2)
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
                        print(f"[Orchestrator] {name} exited (code {exit_code}), restarting in 2s...")
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

        for lf in self._log_files.values():
            try:
                lf.close()
            except Exception:
                pass
        self._log_files.clear()

        # On Windows the receiver holds the data file open until its process
        # fully exits.  Wait up to 3 s for all processes to release it.
        for _ in range(6):
            try:
                if os.path.exists(self.pipe_path):
                    os.remove(self.pipe_path)
                    print("[Orchestrator] Cleaned up data file.")
                break
            except PermissionError:
                time.sleep(0.5)
        else:
            print("[Orchestrator] Could not delete data file (still locked) — will be cleaned up on next start.")

        print("[Orchestrator] All processes stopped.")


def parse_arguments(args=None):
    parser = argparse.ArgumentParser(
        description="Orchestrate sensor receiver and interpreter processes"
    )
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Open console windows for all processes")
    parser.add_argument("--log", "-l", action="store_true",
                        help="Log output to logs/<name>.log")
    return parser.parse_args(args)


def main():
    args = parse_arguments()
    base_dir = os.path.dirname(os.path.abspath(__file__))
    pipe_path = os.path.join(tempfile.gettempdir(), "sensor_data")

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
            args=[pipe_path, "--follow"],
            console=True,
            restart=True,
        ),
    ]

    manager = ProcessManager(verbose=args.verbose, log_output=args.log, pipe_path=pipe_path)
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