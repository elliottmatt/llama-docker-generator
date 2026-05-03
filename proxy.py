#!/usr/bin/env python3
"""
Reverse proxy for llama-server.
- Touches /workspace/.last_request on every inbound request (for watchdog)
- Forwards all traffic to llama-server on localhost:8081
- Handles streaming (SSE / chunked) responses correctly
"""
import os
import sys
import pathlib
import aiohttp
from aiohttp import web

ACTIVITY_FILE = pathlib.Path("/workspace/.last_request")
UPSTREAM = f"http://127.0.0.1:{os.environ.get('LLAMA_INTERNAL_PORT', '8081')}"

HOP_BY_HOP = frozenset([
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
])


async def proxy(request):
    ACTIVITY_FILE.touch()

    url = UPSTREAM + str(request.rel_url)
    req_headers = {k: v for k, v in request.headers.items()
                   if k.lower() not in (*HOP_BY_HOP, "host")}
    body = await request.read()

    timeout = aiohttp.ClientTimeout(total=600)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        async with session.request(
            method=request.method,
            url=url,
            headers=req_headers,
            data=body or None,
            allow_redirects=False,
        ) as upstream:
            resp_headers = {k: v for k, v in upstream.headers.items()
                            if k.lower() not in HOP_BY_HOP}
            response = web.StreamResponse(
                status=upstream.status,
                reason=upstream.reason,
                headers=resp_headers,
            )
            await response.prepare(request)
            async for chunk in upstream.content.iter_any():
                await response.write(chunk)
            await response.write_eof()
            return response


app = web.Application(client_max_size=100 * 1024 * 1024)
app.router.add_route("*", "/",              proxy)
app.router.add_route("*", "/{path_info:.*}", proxy)

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print(f"==> Proxy on :{port} → {UPSTREAM}", flush=True)
    web.run_app(app, host="0.0.0.0", port=port, print=None)
