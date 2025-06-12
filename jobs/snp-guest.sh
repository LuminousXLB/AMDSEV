#!/bin/bash
#SBATCH --partition=mi100_mi210
#SBATCH --cpus-per-task=64

set -euox pipefail

echo "Preparing Linux source code"

SRCDIR="/local_data/$USER/linux-snp-guest"

if [ ! -d "$SRCDIR" ]; then
    mkdir -p "$SRCDIR"
    git clone --quiet --depth=1 --branch=snp-guest-latest https://github.com/AMDESE/linux.git "$SRCDIR"
else
    pushd "$SRCDIR" >/dev/null
    make -j$(nproc) distclean || true
    git fetch --depth=1 origin snp-guest-latest
    git reset --hard origin/snp-guest-latest
    popd >/dev/null
fi

cd "$SRCDIR"

TAG=$(git rev-parse --short HEAD)
LOCALVERSION="$TAG-snp-guest"
WORKDIR=/tmp/linux-$LOCALVERSION/build

mkdir -p "$WORKDIR"
make O=$WORKDIR defconfig

./scripts/config --file $WORKDIR/.config --set-str LOCALVERSION "-$LOCALVERSION"
./scripts/config --file $WORKDIR/.config --disable LOCALVERSION_AUTO
./scripts/config --file $WORKDIR/.config --disable SYSTEM_TRUSTED_KEYS
./scripts/config --file $WORKDIR/.config --disable SYSTEM_REVOCATION_KEYS
./scripts/config --file $WORKDIR/.config --disable MODULE_SIG_KEY
if ! (command -v zstd &>/dev/null); then
    ./scripts/config --file $WORKDIR/.config --disable KERNEL_ZSTD
    ./scripts/config --file $WORKDIR/.config --disable MODULE_COMPRESS_ZSTD
    ./scripts/config --file $WORKDIR/.config --enable KERNEL_XZ
    ./scripts/config --file $WORKDIR/.config --enable MODULE_COMPRESS_XZ
fi
./scripts/config --file $WORKDIR/.config --enable KVM_GUEST
./scripts/config --file $WORKDIR/.config --enable VIRT_DRIVERS
./scripts/config --file $WORKDIR/.config --enable SEV_GUEST

make O=$WORKDIR olddefconfig

cfgs=(
    KVM_GUEST
    VIRT_DRIVERS
    SEV_GUEST

)
for cfg in "${cfgs[@]}"; do
    echo "$cfg = $(./scripts/config --file $WORKDIR/.config --state $cfg)"
done

make O=$WORKDIR -j$(nproc)
make O=$WORKDIR -j$(nproc) bindeb-pkg tarxz-pkg

OUTDIR="/data/$USER/amdsev/linux-$LOCALVERSION"
mkdir -p "$OUTDIR"
find "$WORKDIR/.." -maxdepth 1 -type f -exec mv {} "$OUTDIR" \;
