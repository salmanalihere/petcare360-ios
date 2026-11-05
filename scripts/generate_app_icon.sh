#!/bin/bash
set -euo pipefail

ASSET_DIR="PetCare360/Assets.xcassets/AppIcon.appiconset"
SOURCE="$ASSET_DIR/AppIcon.svg"
OUTPUT="$ASSET_DIR/AppIcon-1024.png"

echo "Generating the 1024x1024 App Store icon from the checked-in vector source..."
python3 -m pip install --quiet --disable-pip-version-check CairoSVG
python3 - <<'PY'
import cairosvg
cairosvg.svg2png(
    url="PetCare360/Assets.xcassets/AppIcon.appiconset/AppIcon.svg",
    write_to="PetCare360/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    output_width=1024,
    output_height=1024,
)
PY

test -s "$OUTPUT"
file "$OUTPUT"
