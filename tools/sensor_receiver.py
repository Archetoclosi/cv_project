#!/usr/bin/env python3
"""Minimal WebSocket server that receives sensor data and writes to named pipe."""

import asyncio
import websockets
import os
import sys

PIPE_PATH = os.getenv("SENSOR_PIPE_PATH", "/tmp/sensor_data")


def write_to_pipe(data: str):
    """Write sensor data to the named pipe."""
    try:
        with open(PIPE_PATH, 'w') as pipe:
            pipe.write(data + '\n')
    except Exception as e:
        print(f"[-] Error writing to pipe: {e}", file=sys.stderr)


async def handler(websocket):
    print(f"[+] Phone connected from {websocket.remote_address}")
    try:
        async for message in websocket:
            # Write to named pipe instead of printing
            write_to_pipe(message)
    except websockets.exceptions.ConnectionClosed:
        print("[-] Phone disconnected")


async def main():
    print(f"Sensor receiver listening on ws://0.0.0.0:8765")
    print(f"Writing data to {PIPE_PATH}")
    async with websockets.serve(handler, "0.0.0.0", 8765):
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
