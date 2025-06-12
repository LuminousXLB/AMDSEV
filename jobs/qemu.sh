#!/bin/bash
#SBATCH --partition=mi100_mi210
#SBATCH --cpus-per-task=64

set -euox pipefail

PREFIX="/data/$USER/amdsev/usr"

if [ -z "${PKG_CONFIG_PATH+x}" ]; then
    export PKG_CONFIG_PATH="$PREFIX/lib/x86_64-linux-gnu/pkgconfig"
else
    export PKG_CONFIG_PATH="$PREFIX/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"
fi

if [ ! command -v meson ] &>/dev/null; then
    python3 -m pip install --user meson
fi

if [ ! command -v ninja ] &>/dev/null; then
    python3 -m pip install --user ninja
fi

if ! pkg-config --exists glib-2.0; then
    TAR=/local_data/$USER/glib-2.85.0.tar.xz
    if [ ! -f "$TAR" ]; then
        wget https://download.gnome.org/sources/glib/2.85/glib-2.85.0.tar.xz --quiet -O "$TAR"
    fi

    tar xf "$TAR" -C /tmp
    cd /tmp/glib-2.85.0
    meson setup --prefix=$PREFIX --buildtype=release -Dtests=false _build
    meson compile -C _build
    meson install -C _build
fi

SRCDIR="/local_data/$USER/qemu-snp-latest"

if [ ! -d "$SRCDIR" ]; then
    mkdir -p "$SRCDIR"
    git clone --quiet --depth=1 --branch=snp-latest https://github.com/AMDESE/qemu.git "$SRCDIR"
else
    pushd "$SRCDIR" >/dev/null
    git fetch --depth=1 origin snp-latest
    git reset --hard origin/snp-latest
    popd >/dev/null
fi

cd "$SRCDIR"

TAG=$(git rev-parse --short HEAD)
WORKDIR=/tmp/qemu-$TAG-build

mkdir -p "$WORKDIR"
cd "$WORKDIR"

command -v meson
command -v ninja
pkg-config --exists glib-2.0

$SRCDIR/configure --disable-docs --target-list=x86_64-softmmu --prefix=$OUTDIR

make -j$(nproc)
make -j$(nproc) install
