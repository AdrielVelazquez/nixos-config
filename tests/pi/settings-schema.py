"""Validate the Pi configuration this repository generates against Pi's own JSON schemas.

  settings-schema.py SETTINGS_SCHEMA MODELS_SCHEMA NAME=SETTINGS_FILE ... [-- NAME=MODELS_FILE ...]

Pi's schemas allow extra top-level keys (extensions own `lsp`, `dap`, `subagents`), so this catches wrong types and enum
values in the keys Pi itself reads (`quietStartup`, `tuiMode`, `terminal.*`, `compaction.*`) and a malformed `models.json`
before a switch installs it.
"""
import json
import sys

from jsonschema import Draft202012Validator

settings_schema, models_schema, *rest = sys.argv[1:]
split = rest.index("--") if "--" in rest else len(rest)
settings, models = rest[:split], rest[split + 1:]
failures = []


def validate(schema_file, label, file):
    schema = json.load(open(schema_file))
    document = json.load(open(file))
    errors = sorted(Draft202012Validator(schema).iter_errors(document), key=lambda e: list(e.absolute_path))
    for error in errors:
        failures.append(f"{label}: {'/'.join(map(str, error.absolute_path)) or '(root)'}: {error.message[:200]}")
    print(f"{'FAIL' if errors else 'PASS'} {label}: {file.split('/')[-1]} ({len(document)} top-level keys)")


for entry in settings:
    name, file = entry.split("=", 1)
    validate(settings_schema, f"{name} settings.json", file)
for entry in models:
    name, file = entry.split("=", 1)
    validate(models_schema, f"{name} models.json", file)
if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
