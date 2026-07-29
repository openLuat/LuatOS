# -*- coding: utf-8 -*-
"""
WebSocket echo 测试服务器 —— 用于替代 wstest.luatos.com

接口行为与原 Java 服务端 (openLuat/luatos-airtun) 保持一致:
  /ws/echo   文本帧, JSON 解析后按 action 分发:
             action=echo 时把收到的 JSON 原样回发, 额外附加 "server" 字段
  /ws/echo2  纯回显: 文本帧/二进制帧收到什么就原样发回什么

依赖: pip install websockets

用法:
  python tools/ws_echo_server.py                     # ws://0.0.0.0:8081
  python tools/ws_echo_server.py --port 9000
  python tools/ws_echo_server.py --cert fullchain.pem --key privkey.pem   # wss

生产部署建议: 本脚本只跑 ws, 前面套 Caddy/nginx 反代处理 wss 证书与续期。
"""

import argparse
import asyncio
import json
import logging
import ssl

import websockets

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("ws_echo")


def _conn_path(ws):
    """兼容 websockets 新旧版本的 path 获取方式"""
    req = getattr(ws, "request", None)
    if req is not None and getattr(req, "path", None):
        return req.path
    return getattr(ws, "path", "/")


async def handle_echo(ws):
    """/ws/echo: 仅响应 action=echo 的 JSON 文本帧"""
    async for message in ws:
        if not isinstance(message, str):
            continue  # 与原服务端一致: 该端点只处理文本 JSON
        try:
            params = json.loads(message)
        except ValueError:
            continue
        if isinstance(params, dict) and params.get("action") == "echo":
            params["server"] = "ws_echo_server.py"
            await ws.send(json.dumps(params, ensure_ascii=False))


async def handle_echo2(ws):
    """/ws/echo2: 文本/二进制帧原样回显"""
    async for message in ws:
        await ws.send(message)


HANDLERS = {
    "/ws/echo": handle_echo,
    "/ws/echo2": handle_echo2,
}


async def dispatch(ws):
    path = _conn_path(ws).split("?", 1)[0].rstrip("/") or "/"
    handler = HANDLERS.get(path)
    log.info("connect path=%s remote=%s", path, ws.remote_address)
    if handler is None:
        await ws.close(4404, "unknown path")
        return
    try:
        await handler(ws)
    except websockets.ConnectionClosed:
        pass
    finally:
        log.info("disconnect path=%s", path)


def main():
    parser = argparse.ArgumentParser(description="WebSocket echo test server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--cert", help="TLS 证书 (fullchain.pem), 提供后启用 wss")
    parser.add_argument("--key", help="TLS 私钥 (privkey.pem)")
    args = parser.parse_args()

    ssl_ctx = None
    if args.cert and args.key:
        ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_ctx.load_cert_chain(args.cert, args.key)

    async def run():
        # max_size=None 不限制单帧大小, 兼容 testcase 的大帧回显测试
        async with websockets.serve(dispatch, args.host, args.port,
                                    ssl=ssl_ctx, max_size=None, ping_interval=None):
            log.info("listening on %s://%s:%d",
                     "wss" if ssl_ctx else "ws", args.host, args.port)
            await asyncio.Future()  # 永久运行

    asyncio.run(run())


if __name__ == "__main__":
    main()
