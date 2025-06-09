#!/bin/bash
#SBATCH --partition=mi100_mi210
#SBATCH --cpus-per-task=96

set -euox pipefail

echo "Preparing Linux source code"

SRCDIR="/local_data/$USER/linux-snp-host"

if [ ! -d "$SRCDIR" ]; then
    mkdir -p "$SRCDIR"
    git clone --depth=1 --branch=snp-host-latest https://github.com/AMDESE/linux.git "$SRCDIR"
else
    pushd "$SRCDIR" >/dev/null
    make -j$(nproc) distclean || true
    git fetch --depth=1 origin snp-host-latest
    git reset --hard origin/snp-host-latest
    popd >/dev/null
fi

cd "$SRCDIR"

TAG=$(git rev-parse --short HEAD)
# TMPDIR=$(mktemp -d /tmp/$USER.$TAG.XXXXXX)
TMPDIR=/tmp/jiamin.85ef1ac03.I0p4P2

make O=$TMPDIR olddefconfig
./scripts/config --file $TMPDIR/.config --set-str LOCALVERSION "-snp-host-$TAG"
./scripts/config --file $TMPDIR/.config --disable SYSTEM_TRUSTED_KEYS
./scripts/config --file $TMPDIR/.config --disable SYSTEM_REVOCATION_KEYS
./scripts/config --file $TMPDIR/.config --disable MODULE_SIG_KEY
if ! (command -v zstd &>/dev/null); then
    ./scripts/config --file $TMPDIR/.config --disable KERNEL_ZSTD
    ./scripts/config --file $TMPDIR/.config --enable KERNEL_GZIP
fi
make O=$TMPDIR olddefconfig

make O=$TMPDIR -j$(nproc) bindeb-pkg || make O=$TMPDIR bindeb-pkg

OUTDIR="/data/$USER/amdsev/snp-host-$(hostname).$TAG"
mkdir -p "$OUTDIR"
