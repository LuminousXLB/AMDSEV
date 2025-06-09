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
WORKDIR=/tmp/linux.85ef1ac03/build

make O=$WORKDIR olddefconfig
./scripts/config --file $WORKDIR/.config --set-str LOCALVERSION "-$TAG-defconfig"
./scripts/config --file $WORKDIR/.config --disable SYSTEM_TRUSTED_KEYS
./scripts/config --file $WORKDIR/.config --disable SYSTEM_REVOCATION_KEYS
./scripts/config --file $WORKDIR/.config --disable MODULE_SIG_KEY
if ! (command -v zstd &>/dev/null); then
    ./scripts/config --file $WORKDIR/.config --disable KERNEL_ZSTD
    ./scripts/config --file $WORKDIR/.config --disable MODULE_COMPRESS_ZSTD
    ./scripts/config --file $WORKDIR/.config --enable KERNEL_XZ
    ./scripts/config --file $WORKDIR/.config --enable MODULE_COMPRESS_XZ
fi
make O=$WORKDIR olddefconfig

make O=$WORKDIR -j$(nproc) bindeb-pkg

OUTDIR="/data/$USER/amdsev/linux-$TAG-defconfig.$(hostname)"
mkdir -p "$OUTDIR"
find "$WORKDIR/.." -maxdepth 1 -type f -exec mv {} "$OUTDIR" \;
