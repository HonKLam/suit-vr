#!/usr/bin/env bash
# Imports the project, then loads and briefly runs every zone. Fails on script or loading errors.
# Run from the repo root; also usable locally.
set -uo pipefail

godot --headless --import > /dev/null 2>&1

failed=0
for dir in zones/*/; do
  zone="${dir}$(basename "$dir").tscn"
  echo "Checking $zone"
  output="$(timeout 180 godot --headless --xr-mode off "res://$zone" --quit-after 60 2>&1)"
  code=$?
  # Only match these: a normal shutdown also prints leak warnings.
  errors="$(grep -E 'SCRIPT ERROR|Parse Error|Failed loading resource|Failed to load|Failed to instantiate' <<< "$output")"
  if [ "$code" -eq 124 ] || [ -n "$errors" ]; then
    echo "::error::$zone failed to load or run"
    echo "$errors"
    failed=1
  fi
done

exit "$failed"
