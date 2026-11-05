#!/usr/bin/env bash
# Prepares the project for one demo: the zone it starts, its name, and which zones it leaves out.
# Usage (from the repo root): select-demo.sh <number> <zone folder>, e.g. select-demo.sh 2 zone_2
# Changes main.tscn, project.godot and export_presets.cfg. Locally, undo that with git restore.
set -euo pipefail

number="$1"
zone="$2"
name="SUIT-VR-S3-Demo-$number"

exclude=""
for dir in zones/*/; do
  other="$(basename "$dir")"
  if [ "$other" != "$zone" ]; then
    exclude="${exclude:+$exclude,}res://zones/$other/*"
  fi
done

sed -i "s|^main_scene = .*|main_scene = \"res://zones/$zone/$zone.tscn\"|" main.tscn
sed -i "s|^config/name=.*|config/name=\"$name\"|" project.godot
sed -i \
  -e "s|^exclude_filter=.*|exclude_filter=\"$exclude\"|" \
  -e "s|^package/unique_name=.*|package/unique_name=\"dev.hklm.suitvrs3.demo$number\"|" \
  -e "s|^package/name=.*|package/name=\"$name\"|" \
  export_presets.cfg
