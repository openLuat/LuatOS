#!/usr/bin/env python

import asyncio

from websockets.asyncio.server import serve

# 生成1k的随机数据
import os
import random
import hashlib

def generate_random_data(size):
    return bytes(random.getrandbits(8) for _ in range(size))
bigdata = generate_random_data(1024)
# 计算数据的SHA256哈希值
hash_object = hashlib.sha256(bigdata * 16)
# 获取哈希值的十六进制表示
hash_hex = hash_object.hexdigest().upper()
print(f"Generated data SHA256: {hash_hex}")
# 打印原始数据的十六进制表示
# print(f"Generated data (hex): {bigdata.hex()}")

async def handler(websocket):
    while True:
        message = await websocket.recv()
        print(message)
        await websocket.send(bigdata * 16)


async def main():
    async with serve(handler, "", 8001) as server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())