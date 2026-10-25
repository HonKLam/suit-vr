#!/usr/bin/env bash
# Downloads the GDExtension binaries (.bin/) of the OpenXR Vendors and Meta Toolkit addons,
# which are gitignored. Versions come from OPENXR_VENDORS_VERSION / META_TOOLKIT_VERSION.
# Run from the repo root; also usable locally after a fresh clone.
set -euo pipefail

fetch() {
  local url="$1" addon="$2"
  local tmp
  tmp="$(mktemp -d)"
  wget -q -O "$tmp/addon.zip" "$url"
  unzip -q "$tmp/addon.zip" -d "$tmp"
  rm -rf "addons/$addon/.bin"
  cp -r "$tmp/asset/addons/$addon/.bin" "addons/$addon/.bin"
  rm -rf "$tmp"
  echo "Fetched addons/$addon/.bin from $url"
}

fetch "https://github.com/GodotVR/godot_openxr_vendors/releases/download/${OPENXR_VENDORS_VERSION:?}/godotopenxrvendorsaddon.zip" godotopenxrvendors
fetch "https://github.com/godot-sdk-integrations/godot-meta-toolkit/releases/download/${META_TOOLKIT_VERSION:?}/godotmetatoolkitaddon.zip" godot_meta_toolkit
