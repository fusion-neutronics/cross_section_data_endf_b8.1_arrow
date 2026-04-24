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

echo "==> downloading decay + NFY sublibraries (skipped if already extracted)"
python - <<'PY'
from pathlib import Path
from nuclear_data_to_yamc_format.download import ENDF_RELEASES, download_and_extract

info = ENDF_RELEASES['viii.1']
dest = Path.home() / 'nuclear_data' / info['dir']
dl = dest / '_downloads'
sublib_globs = {'decay': 'dec-*.endf', 'nfy': 'nfy-*.endf'}
for key in ('decay', 'nfy'):
    pattern = sublib_globs[key]
    if next(dest.rglob(pattern), None) is not None:
        print(f'  {key}: already present ({pattern} in {dest}), skipping')
        continue
    d = info[key]
    urls = [d['base_url'] + f for f in d['files']]
    download_and_extract(urls, dest, dl)
PY

if [[ -f branching_ratios_sfr.json ]]; then
  echo "==> SFR branching ratios already present, skipping download"
else
  echo "==> fetching SFR branching ratios"
  curl -fL -o branching_ratios_sfr.json \
    https://github.com/openmc-data-storage/openmc_data/raw/main/src/openmc_data/depletion/branching_ratios_sfr.json
fi

endf_dir="$HOME/nuclear_data/endfb-viii.1-endf"
echo "==> building transmutation chain file"
convert-chain \
  --decay-dir   "$endf_dir/decay-version.VIII.1" \
  --fpy-dir     "$endf_dir/nfy-version.VIII.1" \
  --neutron-dir "$endf_dir/neutrons-version.VIII.1" \
  --branch-ratios branching_ratios_sfr.json \
  -o transmutation-endf-b8.1-sfr.arrow --library endfb-8.1

tar_arrows () {
  local dir="$1"
  echo "==> tarring arrow files/folders in $dir"
  (
    cd "$dir"
    shopt -s nullglob
    for d in *.arrow; do tar -cf "${d}.tar" "$d"; done
  )
}
tar_arrows "$OUT_DIR/neutron"
tar_arrows "$OUT_DIR/photon"
tar_arrows "transmutation-endf-b8.1-sfr.arrow"

echo
echo "Done. Artifacts ready under $OUT_DIR/ and ./transmutation-endf-b8.1-sfr.arrow/."

if [[ -n "$TAG" ]]; then
  echo
  echo "==> uploading to release $TAG on $GH_REPO"
  shopt -s nullglob
  neutron_tars=("$OUT_DIR"/neutron/*.arrow.tar)
  photon_tars=("$OUT_DIR"/photon/*.arrow.tar)
  chain_tars=(transmutation-endf-b8.1-sfr.arrow/*.arrow.tar)
  shopt -u nullglob
  [[ ${#neutron_tars[@]} -gt 0 ]] && gh release upload "$TAG" "${neutron_tars[@]}" --repo "$GH_REPO" --clobber
  [[ ${#photon_tars[@]}  -gt 0 ]] && gh release upload "$TAG" "${photon_tars[@]}"  --repo "$GH_REPO" --clobber
  [[ ${#chain_tars[@]}   -gt 0 ]] && gh release upload "$TAG" "${chain_tars[@]}"   --repo "$GH_REPO" --clobber
  gh release upload "$TAG" "$OUT_DIR/index.txt" --repo "$GH_REPO" --clobber
  echo "==> upload complete"
else
  echo
  echo "No TAG given. To upload, re-run with a tag (./build_release.sh <TAG>) or:"
  echo "  export TAG=<your-tag>"
  echo "  gh release upload \$TAG $OUT_DIR/neutron/*.arrow.tar --repo $GH_REPO --clobber"
  echo "  gh release upload \$TAG $OUT_DIR/photon/*.arrow.tar  --repo $GH_REPO --clobber"
  echo "  gh release upload \$TAG transmutation-endf-b8.1-sfr.arrow/*.arrow.tar --repo $GH_REPO --clobber"
  echo "  gh release upload \$TAG $OUT_DIR/index.txt --repo $GH_REPO --clobber"
fi
