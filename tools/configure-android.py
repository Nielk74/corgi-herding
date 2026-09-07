#!/usr/bin/env python3
"""Generate CI-only Godot export configuration without putting signing secrets in files."""
import json
import os
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
endpoint = os.environ.get("GAME_SERVER_URL") or "http://127.0.0.1:8790"
if not endpoint.startswith(("http://", "https://")):
    raise SystemExit("GAME_SERVER_URL must be an HTTP(S) base URL")
project = root / "client/project.godot"
text = project.read_text()
number = int(os.environ["GITHUB_RUN_NUMBER"])
version = os.environ.get("GITHUB_REF_NAME", "").removeprefix("v") if os.environ.get("GITHUB_REF", "").startswith("refs/tags/v") else f"0.1.{number}"
text = re.sub(r'(?m)^config/version=.*$', 'config/version=' + json.dumps(version), text)
if "[corgi]" in text:
    text = re.sub(r'(?m)^server_url=.*$', 'server_url=' + json.dumps(endpoint), text)
else:
    text += '\n[corgi]\nserver_url=' + json.dumps(endpoint) + '\n'
project.write_text(text)
preset = root / "client/export_presets.cfg"
text = preset.read_text()
text = re.sub(r'(?m)^version/code=.*$', f'version/code={number}', text)
text = re.sub(r'(?m)^version/name=.*$', 'version/name=' + json.dumps(version), text)
preset.write_text(text)
settings = Path.home() / ".config/godot/editor_settings-4.6.tres"
settings.parent.mkdir(parents=True, exist_ok=True)
settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    + 'export/android/android_sdk_path = ' + json.dumps(os.environ["ANDROID_HOME"]) + '\n'
    + 'export/android/java_sdk_path = ' + json.dumps(os.environ["JAVA_HOME"]) + '\n')
