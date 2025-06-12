#!/bin/bash
#SBATCH --partition=mi100_mi210
#SBATCH --cpus-per-task=64

set -euox pipefail

echo "Preparing Linux source code"

SRCDIR="/local_data/$USER/linux-snp-host"

if [ ! -d "$SRCDIR" ]; then
    mkdir -p "$SRCDIR"
    git clone --quiet --depth=1 --branch=snp-host-latest https://github.com/AMDESE/linux.git "$SRCDIR"
else
    pushd "$SRCDIR" >/dev/null
    make -j$(nproc) distclean || true
    git fetch --depth=1 origin snp-host-latest
    git reset --hard origin/snp-host-latest
    popd >/dev/null
fi

cd "$SRCDIR"

TAG=$(git rev-parse --short HEAD)
LOCALVERSION="$TAG-snp-host"
WORKDIR=/tmp/linux-$LOCALVERSION/build

mkdir -p "$WORKDIR"
cp /boot/config-6.6.5-060605-generic "$WORKDIR/.config"
make O=$WORKDIR olddefconfig

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

./scripts/config --file $WORKDIR/.config --enable KVM
./scripts/config --file $WORKDIR/.config --enable KVM_AMD
./scripts/config --file $WORKDIR/.config --enable CRYPTO_DEV_CCP
./scripts/config --file $WORKDIR/.config --enable CRYPTO_DEV_CCP_DD
./scripts/config --file $WORKDIR/.config --enable CRYPTO_DEV_SP_PSP
./scripts/config --file $WORKDIR/.config --enable KVM_AMD_SEV
./scripts/config --file $WORKDIR/.config --enable AMD_MEM_ENCRYPT
./scripts/config --file $WORKDIR/.config --disable AMD_MEM_ENCRYPT_ACTIVE_BY_DEFAULT

make O=$WORKDIR olddefconfig

cfgs=(
    KVM
    KVM_AMD
    CRYPTO_DEV_CCP
    CRYPTO_DEV_CCP_DD
    CRYPTO_DEV_SP_PSP
    KVM_AMD_SEV
    AMD_MEM_ENCRYPT
    AMD_MEM_ENCRYPT_ACTIVE_BY_DEFAULT
)
for cfg in "${cfgs[@]}"; do
    echo "$cfg = $(./scripts/config --file $WORKDIR/.config --state $cfg)"
done

make O=$WORKDIR -j$(nproc) LOCALVERSION=
make O=$WORKDIR -j$(nproc) LOCALVERSION= bindeb-pkg

OUTDIR="/data/$USER/amdsev/linux-$LOCALVERSION"
mkdir -p "$OUTDIR"
find "$WORKDIR/.." -maxdepth 1 -type f -exec mv {} "$OUTDIR" \;
