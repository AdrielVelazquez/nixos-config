#!/usr/bin/env python3
"""Bind a native MCP service to its own owned process lease before exec."""
import argparse
import importlib.util
import os
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--core', type=Path, required=True)
parser.add_argument('--config', type=Path, required=True)
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command
if not command:
    parser.error('a service command is required')
spec = importlib.util.spec_from_file_location('owned_headroom', args.core)
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)
config, acquired = core.acquire(args.config.resolve(), os.getpid())
env = core.client_environment(args.config.resolve(), config, acquired)
os.execvpe(command[0], command, env)
