#!/bin/zsh
# Renders the pitch hero slides into docs/screenshots/pitch/hero-0*.jpg (3840x2160).
#   assets/pitch_hero/render_heroes.sh [clinic|roadside|ultrasound ...]
# Needs Blender 4.2+ (EEVEE Next) and python3 with Pillow. HERO_QUICK=1 for fast low-res previews.
set -e
cd "${0:A:h}"
BLENDER=${BLENDER:-blender}
python3 fetch_assets.py
python3 composite.py --us-screen
scenes=(${@:-clinic roadside ultrasound})
for s in $scenes; do "$BLENDER" -b --python hero_$s.py > .cache/out/render_$s.log 2>&1 || { tail -20 .cache/out/render_$s.log; exit 1; }; done
typeset -A shots=(clinic hero-01-clinic roadside hero-02-roadside ultrasound hero-03-ultrasound)
for s in $scenes; do python3 composite.py ${shots[$s]} ${shots[$s]}-b; done
