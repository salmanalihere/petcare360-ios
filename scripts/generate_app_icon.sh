#!/bin/bash
set -euo pipefail

ASSET_DIR="PetCare360/Assets.xcassets/AppIcon.appiconset"
OUTPUT="$ASSET_DIR/AppIcon-1024.png"
VENV="/tmp/petcare360-icon-venv"

echo "Preparing the App Store icon generator..."
python3 -m venv "$VENV"
"$VENV/bin/python" -m pip install --quiet --disable-pip-version-check CairoSVG

echo "Rendering the 1024x1024 App Store icon..."
"$VENV/bin/python" - <<'PY'
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
