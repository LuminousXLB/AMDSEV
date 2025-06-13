#!/bin/bash
#SBATCH --partition=mi100_mi210
#SBATCH --cpus-per-task=64

set -euox pipefail

PREFIX="/data/$USER/amdsev/usr"
if [ !d "$PREFIX/share/qemu" ]; then
    echo "Directory $PREFIX/share/qemu does not exist, exiting"
    exit 1
fi

WORKDIR="/tmp/ovmf-snp-latest"

if [ -d "$WORKDIR" ]; then
    rm -rf "$WORKDIR"
fi

git clone --quiet --depth=1 --branch=snp-latest https://github.com/AMDESE/ovmf.git "$WORKDIR"
cd "$WORKDIR"
git submodule | awk '{print $2}' | xargs -P0 -I{} git submodule update --init --recursive --depth=1 -- {}

make -C BaseTools clean
make -C BaseTools -j $(getconf _NPROCESSORS_ONLN)

. ./edksetup.sh --reconfig

ACTIVE_PLATFORM=OvmfPkg/OvmfPkgX64.dsc
TARGET=DEBUG
TARGET_ARCH=X64
TOOL_CHAIN_TAG=GCC
MAX_CONCURRENT_THREAD_NUMBER=$(getconf _NPROCESSORS_ONLN)

build \
    --quiet --cmd-len=64436 \
    -p $ACTIVE_PLATFORM \
    -b $TARGET \
    -a $TARGET_ARCH \
    -t $TOOL_CHAIN_TAG \
    -n $MAX_CONCURRENT_THREAD_NUMBER \
    -DDEBUG_ON_SERIAL_PORT=TRUE

cp -f Build/OvmfX64/DEBUG_GCC/FV/OVMF_CODE.fd "$PREFIX/share/qemu"
cp -f Build/OvmfX64/DEBUG_GCC/FV/OVMF_VARS.fd "$PREFIX/share/qemu"
cp -f Build/OvmfX64/DEBUG_GCC/FV/OVMF.fd "$PREFIX/share/qemu"
