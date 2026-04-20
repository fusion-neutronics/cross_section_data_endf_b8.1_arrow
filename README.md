# ENDF/B-VIII.1 Cross Section Data (Arrow format)

Pre-built ENDF/B-VIII.1 nuclear cross section data in Apache Arrow IPC format, plus a transmutation data file, converted using [nuclear_data_to_yamc_format](https://github.com/fusion-neutronics/nuclear_data_to_yamc_format).

## Download

Grab the latest release artifacts from the [Releases](https://github.com/fusion-neutronics/cross_section_data_endf_b8.1_arrow/releases) page.

## Building locally

### Prerequisites

- Python 3.10+
- NJOY2016 on PATH (`njoy` binary)
- OpenMC Python package

### Install system packages

```bash
sudo apt-get install -y cmake gfortran git gh
```

### Build and install NJOY2016

```bash
git clone https://github.com/njoy/NJOY2016.git
cd NJOY2016 && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
sudo cp njoy /usr/local/bin/
cd ../..
```

### Install Python dependencies

```bash
pip install nuclear_data_to_yamc_format
pip install --extra-index-url https://shimwell.github.io/wheels openmc
```

### Convert all nuclides

```bash
convert-endf --release viii.1 -d endf-b8.1-arrow
```

This downloads ENDF/B-VIII.1 data from NNDC (if not already present), then converts all isotopes through NJOY at 6 temperatures. Output goes to `./endf-b8.1-arrow/`.

To convert a single nuclide for testing:

```bash
convert-endf --release viii.1 --nuclides Fe56 -d endf-b8.1-arrow
```

### Build the transmutation data file

ENDF/B-VIII.1 includes its own decay and neutron fission product yield sublibraries, so the transmutation data is fully self-consistent with the cross sections (no borrowing from other libraries).

The chain is built directly from the ENDF files (reusing the neutron sublibrary
`convert-endf` already downloaded, plus the decay and NFY sublibraries which we
download explicitly). SFR branching ratios are then applied (matching
`openmc_data`'s SFR variant).

```bash
# Download decay + NFY sublibraries alongside the neutron data
python - <<'EOF'
from pathlib import Path
from nuclear_data_to_yamc_format.download import ENDF_RELEASES, download_and_extract
info = ENDF_RELEASES['viii.1']
dest = Path.home() / 'nuclear_data' / info['dir']
dl = dest / '_downloads'
for key in ('decay', 'nfy'):
    d = info[key]
    urls = [d['base_url'] + f for f in d['files']]
    download_and_extract(urls, dest, dl)
EOF

curl -L -o branching_ratios_sfr.json \
  https://github.com/openmc-data-storage/openmc_data/raw/main/src/openmc_data/depletion/branching_ratios_sfr.json

ENDF_DIR="$HOME/nuclear_data/endfb-viii.1-endf"
convert-chain \
  --decay-dir "$ENDF_DIR/decay" \
  --fpy-dir "$ENDF_DIR/nfy" \
  --neutron-dir "$ENDF_DIR/neutrons" \
  --branch-ratios branching_ratios_sfr.json \
  -o transmutation-endf-b8.1-sfr.arrow --library endfb-8.1

tar -cf transmutation-endf-b8.1-sfr.arrow.tar transmutation-endf-b8.1-sfr.arrow
```

### Compress each nuclide and upload to a release

```bash
export TAG=1.0.0

cd endf-b8.1-arrow/neutron
for d in *.arrow; do
  tar -cf "${d}.tar" "$d"
done
gh release upload $TAG *.arrow.tar \
  --repo fusion-neutronics/cross_section_data_endf_b8.1_arrow \
  --clobber
cd ../..

cd endf-b8.1-arrow/photon
for d in *.arrow; do
  tar -cf "${d}.tar" "$d"
done
gh release upload $TAG *.arrow.tar \
  --repo fusion-neutronics/cross_section_data_endf_b8.1_arrow \
  --clobber
cd ../..

# Upload the transmutation data file
gh release upload $TAG transmutation-endf-b8.1-sfr.arrow.tar \
  --repo fusion-neutronics/cross_section_data_endf_b8.1_arrow \
  --clobber
```

This uploads each nuclide as a separate uncompressed tar (e.g. `Fe56.arrow.tar`, `U235.arrow.tar`) for both neutron and photon data, plus a single `transmutation-endf-b8.1-sfr.arrow.tar`.

### Clean up source files

```bash
rm -rf "$HOME/nuclear_data/endfb-viii.1-endf" branching_ratios_sfr.json
```
