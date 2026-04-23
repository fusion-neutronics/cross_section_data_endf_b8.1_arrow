#!/usr/bin/env bash
# Build ENDF/B-VIII.1 cross sections + transmutation chain file, tar each
# nuclide, and optionally upload them to a GitHub release.
#
# Usage (run from repo root):
#   ./build_release.sh              # build + tar only
#   ./build_release.sh 1.0.0        # build + tar + upload to release tag 1.0.0
#   TAG=1.0.0 ./build_release.sh    # same, via env var

set -euo pipefail

TAG="${1:-${TAG:-}}"
OUT_DIR="endf-b8.1-arrow"
GH_REPO="fusion-neutronics/cross_section_data_endf_b8.1_arrow"

echo "==> converting ENDF/B-VIII.1 neutron + photon data into $OUT_DIR/"
convert-endf --release viii.1 -d "$OUT_DIR"

echo "==> downloading decay + NFY sublibraries"
python - <<'PY'
from pathlib import Path
from nuclear_data_to_yamc_format.download import ENDF_RELEASES, download_and_extract
info = ENDF_RELEASES['viii.1']
dest = Path.home() / 'nuclear_data' / info['dir']
dl = dest / '_downloads'
for key in ('decay', 'nfy'):
    d = info[key]
    urls = [d['base_url'] + f for f in d['files']]
    download_and_extract(urls, dest, dl)
PY

echo "==> fetching SFR branching ratios"
curl -fL -o branching_ratios_sfr.json \
  https://github.com/openmc-data-storage/openmc_data/raw/main/src/openmc_data/depletion/branching_ratios_sfr.json

endf_dir="$HOME/nuclear_data/endfb-viii.1-endf"
echo "==> building transmutation chain file"
convert-chain \
  --decay-dir   "$endf_dir/decay-version.VIII.1" \
  --fpy-dir     "$endf_dir/nfy-version.VIII.1" \
  --neutron-dir "$endf_dir/neutrons-version.VIII.1" \
  --branch-ratios branching_ratios_sfr.json \
  -o transmutation-endf-b8.1-sfr.arrow --library endfb-8.1

tar -cf transmutation-endf-b8.1-sfr.arrow.tar transmutation-endf-b8.1-sfr.arrow

tar_nuclides () {
  local dir="$1"
  echo "==> tarring nuclides in $dir"
  (
    cd "$dir"
    shopt -s nullglob
    for d in *.arrow; do tar -cf "${d}.tar" "$d"; done
  )
}
tar_nuclides "$OUT_DIR/neutron"
tar_nuclides "$OUT_DIR/photon"

echo
echo "Done. Artifacts ready under $OUT_DIR/ and ./transmutation-endf-b8.1-sfr.arrow.tar."

if [[ -n "$TAG" ]]; then
  echo
  echo "==> uploading to release $TAG on $GH_REPO"
  gh release upload "$TAG" "$OUT_DIR"/neutron/*.arrow.tar         --repo "$GH_REPO" --clobber
  gh release upload "$TAG" "$OUT_DIR"/photon/*.arrow.tar          --repo "$GH_REPO" --clobber
  gh release upload "$TAG" transmutation-endf-b8.1-sfr.arrow.tar  --repo "$GH_REPO" --clobber
  echo "==> upload complete"
else
  echo
  echo "No TAG given. To upload, re-run with a tag (./build_release.sh <TAG>) or:"
  echo "  export TAG=<your-tag>"
  echo "  gh release upload \$TAG $OUT_DIR/neutron/*.arrow.tar --repo $GH_REPO --clobber"
  echo "  gh release upload \$TAG $OUT_DIR/photon/*.arrow.tar  --repo $GH_REPO --clobber"
  echo "  gh release upload \$TAG transmutation-endf-b8.1-sfr.arrow.tar --repo $GH_REPO --clobber"
fi
