#!/usr/bin/env python3
"""Minimal WebSocket server that receives sensor data and writes to file/pipe."""

import asyncio
import tempfile
import websockets
import os
import sys

PIPE_PATH = os.getenv("SENSOR_PIPE_PATH", os.path.join(tempfile.gettempdir(), "sensor_data"))
PORT = int(os.getenv("SENSOR_PORT", "9000"))

# Keep the file open for the lifetime of the server to avoid
# open/close on every message (causes file locking issues on Windows)
_pipe_handle = None


def open_pipe():
    global _pipe_handle
    try:
        _pipe_handle = open(PIPE_PATH, 'a', buffering=1, encoding='utf-8')
        print(f"[+] Opened data file: {PIPE_PATH}")
    except Exception as e:
        print(f"[-] Error opening pipe: {e}", file=sys.stderr)
        sys.exit(1)


def write_to_pipe(data: str):
    """Write sensor data — file is kept open for the lifetime of the process."""
    try:
        if _pipe_handle and not _pipe_handle.closed:
            _pipe_handle.write(data + '\n')
            _pipe_handle.flush()
    except Exception as e:
        print(f"[-] Error writing to pipe: {e}", file=sys.stderr)


def close_pipe():
    global _pipe_handle
    if _pipe_handle and not _pipe_handle.closed:
        _pipe_handle.close()


async def handler(websocket):
    print(f"[+] Phone connected from {websocket.remote_address}")
    try:
        async for message in websocket:
            write_to_pipe(message)
    except websockets.exceptions.ConnectionClosed:
        print("[-] Phone disconnected")


async def serve():
    print(f"[+] Sensor receiver listening on ws://0.0.0.0:{PORT}")
    print(f"[+] Writing data to {PIPE_PATH}")
    try:
        async with websockets.serve(handler, "0.0.0.0", PORT):
            await asyncio.Future()  # run forever
    except OSError as e:
        if "Address already in use" in str(e) or "10048" in str(e):
            print(f"[-] Port {PORT} already in use. Kill existing process and try again:")
            if sys.platform == "win32":
                print(f"    netstat -ano | findstr :{PORT}  -> then: taskkill /PID <pid> /F",
                      file=sys.stderr)
            else:
                print(f"    pkill -f sensor_receiver.py", file=sys.stderr)
            sys.exit(1)
        raise


def main():
    open_pipe()
    try:
        if sys.platform == "win32":
            # ProactorEventLoop (Windows default) has issues with websockets.
            # On Python 3.12+ create the SelectorEventLoop directly.
            loop = asyncio.SelectorEventLoop()
            asyncio.set_event_loop(loop)
            try:
                loop.run_until_complete(serve())
            finally:
                loop.close()
        else:
            asyncio.run(serve())
    except KeyboardInterrupt:
        print("\n[-] Receiver stopped.")
    finally:
        close_pipe()


if __name__ == "__main__":
    main()