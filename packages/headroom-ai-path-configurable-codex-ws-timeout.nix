{ writeText }:

writeText "headroom-configurable-codex-ws-timeout.patch" ''
  --- a/headroom/proxy/handlers/openai.py
  +++ b/headroom/proxy/handlers/openai.py
  @@ -146,7 +146,19 @@
   
   
   def _codex_ws_compression_timeout_seconds() -> float:
  -    return min(COMPRESSION_TIMEOUT_SECONDS, _CODEX_WS_COMPRESSION_TIMEOUT_SECONDS)
  +    try:
  +        timeout = float(
  +            os.environ.get(
  +                "HEADROOM_CODEX_WS_COMPRESSION_TIMEOUT_SECONDS",
  +                str(_CODEX_WS_COMPRESSION_TIMEOUT_SECONDS),
  +            )
  +        )
  +    except ValueError:
  +        timeout = _CODEX_WS_COMPRESSION_TIMEOUT_SECONDS
  +    # Reject non-positive and non-finite values so the deadline stays bounded.
  +    if not 0 < timeout < float("inf"):
  +        timeout = _CODEX_WS_COMPRESSION_TIMEOUT_SECONDS
  +    return min(COMPRESSION_TIMEOUT_SECONDS, timeout)
   
   
   _WS_ALLOWED_ORIGINS_ENV = "HEADROOM_WS_ORIGINS"
''
