{ writeText }:

writeText "headroom-idempotent-memory-mcp.patch" ''
  --- a/headroom/cli/wrap.py
  +++ b/headroom/cli/wrap.py
  @@ -3382,11 +3382,18 @@
       # Use forward slashes in TOML paths (works on all platforms, avoids
       # backslash escaping issues on Windows)
       python_bin = sys.executable.replace("\\", "/")
  +    mcp_args = ["-m", "headroom.memory.mcp_server", "--user", user_id]
  +    desired_entry = {
  +        "command": python_bin,
  +        "args": mcp_args,
  +        "startup_timeout_sec": 30,
  +        "tool_timeout_sec": 30,
  +    }
       mcp_section = (
           f"\n{_MEMORY_MCP_MARKER}\n"
           f"[mcp_servers.headroom_memory]\n"
  -        f'command = "{python_bin}"\n'
  -        f'args = ["-m", "headroom.memory.mcp_server", "--user", "{user_id}"]\n'
  +        f"command = {json.dumps(python_bin)}\n"
  +        f"args = {json.dumps(mcp_args)}\n"
           f"startup_timeout_sec = 30\n"
           f"tool_timeout_sec = 30\n"
           f"{_MEMORY_MCP_END}\n"
  @@ -3399,10 +3406,45 @@
           # can fully restore it even when only `--memory` (not a full provider
           # injection) was used.
           _, backup_file = _codex_config_paths()
  +        if config_file.exists():
  +            content = _read_text(config_file)
  +            try:
  +                config = tomllib.loads(content) if content.strip() else {}
  +            except tomllib.TOMLDecodeError as exc:
  +                click.echo(
  +                    f"  Warning: could not register memory MCP: {config_file} "
  +                    f"is not valid TOML ({exc}); refusing to overwrite"
  +                )
  +                return
  +
  +            servers = config.get("mcp_servers", {})
  +            if not isinstance(servers, dict):
  +                click.echo(
  +                    f"  Warning: could not register memory MCP: {config_file} has a "
  +                    "non-table mcp_servers; refusing to overwrite"
  +                )
  +                return
  +            existing = servers.get("headroom_memory")
  +            if existing is not None:
  +                if not isinstance(existing, dict):
  +                    click.echo(
  +                        f"  Warning: could not register memory MCP: {config_file} has a "
  +                        "non-table mcp_servers.headroom_memory; refusing to overwrite"
  +                    )
  +                    return
  +                if all(existing.get(key) == value for key, value in desired_entry.items()):
  +                    click.echo(f"  Memory MCP: already registered in {config_file}")
  +                    return
  +                if _MEMORY_MCP_MARKER not in content:
  +                    click.echo(
  +                        f"  Warning: could not register memory MCP: {config_file} has a "
  +                        "user-managed [mcp_servers.headroom_memory] entry; refusing to overwrite"
  +                    )
  +                    return
  +
           _snapshot_codex_config_if_unwrapped(config_file, backup_file)

           if config_file.exists():
  -            content = _read_text(config_file)
               if _MEMORY_MCP_MARKER in content:
                   start = content.index(_MEMORY_MCP_MARKER)
                   end = content.index(_MEMORY_MCP_END) + len(_MEMORY_MCP_END)
''
