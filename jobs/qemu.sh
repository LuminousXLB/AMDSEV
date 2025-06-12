#!/bin/bash
#SBATCH --partition=mi100_mi210
#SBATCH --cpus-per-task=64

set -euox pipefail

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

TAG=$(git rev-parse --short HEAD)
WORKDIR=/tmp/qemu-$TAG/build
OUTDIR="/data/$USER/amdsev/qemu-$TAG"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

$(SRCDIR)/configure --target-list=x86_64-softmmu --prefix=$OUTDIR

make -j$(nproc)
make -j$(nproc) install
