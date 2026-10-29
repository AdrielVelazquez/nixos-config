"""Run real Headroom with only its external Codex destinations replaced by loopback."""

import os
from urllib.parse import urlparse

import httpx
from headroom.cli import main
from headroom.providers.codex import endpoints

origin = os.environ["PI_CODEX_FIXTURE_ORIGIN"]
assert urlparse(origin).hostname == "127.0.0.1"
endpoints.CHATGPT_BACKEND_API_URL = origin
endpoints.CHATGPT_BACKEND_WS_URL = origin.replace("http://", "ws://", 1)

send = httpx.AsyncClient.send


async def local_send(self, request, *args, **kwargs):
    assert request.url.host == "127.0.0.1", "Fixture attempted non-loopback HTTP"
    return await send(self, request, *args, **kwargs)


httpx.AsyncClient.send = local_send
main()
