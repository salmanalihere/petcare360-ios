#!/bin/bash
set -euo pipefail

ASSET_DIR="PetCare360/Assets.xcassets/AppIcon.appiconset"
OUTPUT="$ASSET_DIR/AppIcon-1024.png"
VENV="/tmp/petcare360-icon-venv"

echo "Preparing the App Store icon generator..."
python3 -m venv "$VENV"
"$VENV/bin/python" -m pip install --quiet --disable-pip-version-check CairoSVG Pillow

echo "Rendering an opaque 1024x1024 App Store icon..."
"$VENV/bin/python" - <<'PY'
import cairosvg
from PIL import Image
from io import BytesIO

svg_path = "PetCare360/Assets.xcassets/AppIcon.appiconset/AppIcon.svg"
png_path = "PetCare360/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

rendered = cairosvg.svg2png(url=svg_path, output_width=1024, output_height=1024)
image = Image.open(BytesIO(rendered)).convert("RGB")
if image.size != (1024, 1024):
    raise SystemExit(f"Unexpected icon dimensions: {image.size}")
image.save(png_path, format="PNG", optimize=True)
check = Image.open(png_path)
if check.mode != "RGB" or check.size != (1024, 1024):
    raise SystemExit(f"Invalid App Store icon output: mode={check.mode}, size={check.size}")
print(f"Verified opaque RGB icon: {check.size}, mode={check.mode}")
PY

test -s "$OUTPUT"
file "$OUTPUT"
