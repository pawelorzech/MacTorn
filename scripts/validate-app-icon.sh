#!/usr/bin/env bash

set -euo pipefail

icon_dir="MacTorn/MacTorn/Assets.xcassets/AppIcon.appiconset"
specs=(
  "icon_16x16.png:16"
  "icon_16x16@2x.png:32"
  "icon_32x32.png:32"
  "icon_32x32@2x.png:64"
  "icon_128x128.png:128"
  "icon_128x128@2x.png:256"
  "icon_256x256.png:256"
  "icon_256x256@2x.png:512"
  "icon_512x512.png:512"
  "icon_512x512@2x.png:1024"
)

for spec in "${specs[@]}"; do
  filename="${spec%%:*}"
  expected="${spec##*:}"
  asset="$icon_dir/$filename"

  [[ -f "$asset" ]] || { echo "Missing app icon: $asset" >&2; exit 1; }

  kind="$(file -b "$asset")"
  [[ "$kind" == PNG\ image\ data* ]] || {
    echo "App icon is not PNG data: $asset ($kind)" >&2
    exit 1
  }

  width="$(sips -g pixelWidth "$asset" | awk '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$asset" | awk '/pixelHeight/ { print $2 }')"
  [[ "$width" == "$expected" && "$height" == "$expected" ]] || {
    echo "Wrong app icon size: $asset is ${width}x${height}, expected ${expected}x${expected}" >&2
    exit 1
  }

  has_alpha="$(sips -g hasAlpha "$asset" | awk '/hasAlpha/ { print $2 }')"
  [[ "$has_alpha" == "yes" ]] || {
    echo "App icon lacks the transparency required by the macOS 14 artwork: $asset" >&2
    exit 1
  }
done

echo "App icon validation passed: 10 transparent PNG assets with expected dimensions."
