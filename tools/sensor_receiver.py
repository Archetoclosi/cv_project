#!/usr/bin/env python3
"""Minimal WebSocket server that receives and prints sensor data from the Flutter app."""

import asyncio
import websockets

async def handler(websocket):
    print(f"[+] Phone connected from {websocket.remote_address}")
    try:
        async for message in websocket:
            print(message)
    except websockets.exceptions.ConnectionClosed:
        print("[-] Phone disconnected")

async def main():
    print("Sensor receiver listening on ws://0.0.0.0:8765")
    async with websockets.serve(handler, "0.0.0.0", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
