#!/bin/bash
# Rebuilds visionos/MedSimXR/Resources/Patient.usdz and Patient.json.
# Needs Blender 4.2+ (brew install --cask blender). Downloads MPFB and the CC0 asset pack on first run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
CACHE="${MEDSIM_ASSET_CACHE:-$ROOT/assets/patient/.cache}"
OUT="$CACHE/out"; mkdir -p "$OUT"

if ! "$BLENDER" -b --python-expr "import bl_ext.user_default.mpfb" >/dev/null 2>&1; then
  URL=$(curl -s https://extensions.blender.org/api/v1/extensions/ | python3 -c "import json,sys; print(next(e['archive_url'] for e in json.load(sys.stdin)['data'] if e['id']=='mpfb'))")
  curl -sL -o "$CACHE/mpfb.zip" "$URL"
  "$BLENDER" --command extension install-file -r user_default -e "$CACHE/mpfb.zip"
fi
DATA=$("$BLENDER" -b --python-expr "from bl_ext.user_default.mpfb.services.locationservice import LocationService as L; print('DATA='+L.get_user_data())" 2>/dev/null | sed -n 's/^DATA=//p')
if [ ! -d "$DATA/skins/young_caucasian_male" ]; then
  curl -L -o "$CACHE/system_assets.zip" https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip
  mkdir -p "$DATA" && unzip -q -o "$CACHE/system_assets.zip" -d "$DATA"
fi

OUT="$OUT" "$BLENDER" -b --python "$ROOT/assets/patient/build_patient.py" 2>&1 | grep -E "^SIDECAR|Error|Traceback" || true

# Hair, brows and lashes are alpha cards: cut them out instead of blending (no sorting artefacts).
cd "$OUT"
rm -rf pkg && mkdir pkg && (cd pkg && unzip -q ../Patient.usdz)
usdcat pkg/Patient.usdc -o pkg/Patient.usda
python3 - <<'PY'
import re
s = open("pkg/Patient.usda").read()
n = 0
def cut(m):
    global n
    block = m.group(0)
    if re.search(r'def Material "Human_(short|eyebrow|eyelash)', block):
        block, k = re.subn(r'(\n(\s*)float inputs:opacity = 1\n)', r'\1\2float inputs:opacityThreshold = 0.4\n', block, count=1)
        n += k
    return block
s = re.sub(r'def Material "Human_[^"]+".*?(?=\n        def Material |\Z)', cut, s, flags=re.S)
open("pkg/Patient.usda", "w").write(s)
print("alpha cut-out materials:", n)
PY
usdcat pkg/Patient.usda -o pkg/Patient.usdc && rm pkg/Patient.usda
rm -f Patient.usdz && (cd pkg && usdzip -r ../Patient.usdz .) >/dev/null
usdchecker --arkit Patient.usdz | tail -1
cp Patient.usdz Patient.json "$ROOT/visionos/MedSimXR/Resources/"
ls -la "$ROOT/visionos/MedSimXR/Resources/Patient.usdz"
