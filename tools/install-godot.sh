#!/usr/bin/env bash
set -euo pipefail
# Official, version-matched editor and templates, checked against pinned upstream hashes.
GODOT_VERSION=4.6.3
destination="${1:?Usage: install-godot.sh DIRECTORY}"
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"
base="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable"
editor="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
templates="Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
curl -fsSL --retry 3 "$base/$editor" -o "$destination/$editor"
curl -fsSL --retry 3 "$base/$templates" -o "$destination/$templates"
cd "$destination"
echo "a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c  $editor" | sha512sum -c -
echo "da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68  $templates" | sha512sum -c -
unzip -q -o "$editor"
mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" godot
chmod +x godot
mkdir -p "$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
unzip -q -o "$templates" 'templates/android*' 'templates/version.txt'
cp templates/android* templates/version.txt "$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable/"
./godot --headless --version
