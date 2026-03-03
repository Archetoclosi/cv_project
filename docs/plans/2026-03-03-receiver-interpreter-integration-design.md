# Receiver-Interpreter Integration Design

**Date:** 2026-03-03
**Status:** Approved

## Overview

Integrate `sensor_receiver.py` and `interpreter.py` so that live sensor data from the Flutter app flows through the receiver into the interpreter for real-time meaning extraction.

## Architecture

### Data Flow
```
Flutter app → WebSocket (port 8765) → sensor_receiver.py → [named pipe] → interpreter.py → console
```

### Named Pipe
- Location: `/tmp/sensor_data`
- Auto-created by orchestrator on startup
- Auto-cleaned on shutdown
- Allows both scripts to run independently while maintaining real-time streaming

### Process Management
All three components run as separate processes managed by a Python orchestrator:

1. **Orchestrator** — lifecycle management, restart logic, console management
2. **Receiver** — WebSocket server listening on port 8765, writes to pipe
3. **Interpreter** — reads from pipe, interprets sensor data, displays states

## Modes

### Default Mode
```bash
python tools/orchestrator.py
```
- Interpreter runs in separate console window (shows refined sensor states)
- Receiver runs silently (output discarded)
- Orchestrator console shows start/restart messages

### With Log Flag
```bash
python tools/orchestrator.py --log
```
- Same as default, but receiver output saved to `logs/receiver.log`
- Useful for capturing raw sensor data without console clutter

### Verbose Mode
```bash
python tools/orchestrator.py --verbose
```
- Receiver in separate console window (raw sensor data)
- Interpreter in separate console window (refined states)
- Orchestrator console shows management logs
- All three windows visible simultaneously

## Process Configuration

Processes defined in Python code for easy expansion:
```python
PROCESSES = [
    {
        "name": "receiver",
        "script": "tools/sensor_receiver.py",
        "args": [],
        "console": False,  # suppress by default
        "restart": True
    },
    {
        "name": "interpreter",
        "script": "tools/interpreter.py",
        "args": ["/tmp/sensor_data", "--follow"],
        "console": True,  # separate window
        "restart": True
    }
]
```

**Design principle:** Add new processes by extending `PROCESSES` list — no logic changes needed.

## Orchestrator Features

### Auto-Restart
- If either process crashes, automatically restart it
- Notify in orchestrator console: `[Orchestrator] Process receiver crashed, restarting...`
- Both receiver and interpreter restart independently

### Graceful Shutdown
- On Ctrl+C: kill both subprocesses, clean up named pipe, close console windows
- No orphaned processes or stale pipes

### Cross-Platform
- macOS: use `open -a Terminal` for separate windows
- Linux: use `gnome-terminal` or `xterm`
- Windows: use `start` command
- Graceful fallback if terminal command unavailable

### Logging
- Orchestrator console shows: process start, restart, error messages with timestamps
- Process output captured and displayed appropriately (console/log file)

## Receiver Modifications

Current `sensor_receiver.py`:
```python
async def handler(websocket):
    print(f"[+] Phone connected from {websocket.remote_address}")
    try:
        async for message in websocket:
            print(message)  # Just prints to stdout
```

Modified version:
```python
async def handler(websocket):
    print(f"[+] Phone connected from {websocket.remote_address}")
    try:
        async for message in websocket:
            # Write to named pipe
            with open(PIPE_PATH, 'w') as pipe:
                pipe.write(message + '\n')
```

Where `PIPE_PATH = "/tmp/sensor_data"` (created by orchestrator)

## Interpreter Modifications

**No changes needed.** Interpreter already:
- Reads from a file path: `interpreter.py /tmp/sensor_data --follow`
- Uses `--follow` mode to tail the file in real-time
- Named pipes work seamlessly as files from the interpreter's perspective

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Pipe doesn't exist | Receiver creates it automatically |
| Receiver crashes | Auto-restart, resume listening on WebSocket |
| Interpreter crashes | Auto-restart, resume reading from pipe |
| Pipe breaks | Both processes restart |
| Ctrl+C in orchestrator | Clean shutdown of both, pipe cleanup |

## Extensibility

Design supports adding more processes in the future:
- Add new entry to `PROCESSES` list
- Specify script, args, console visibility, restart policy
- Orchestrator handles all lifecycle management uniformly
- No need to modify core orchestrator logic
