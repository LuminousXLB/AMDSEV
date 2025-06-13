#!/bin/bash
#SBATCH --partition=mi100_mi210
#SBATCH --cpus-per-task=64

set -o pipefail #  return the exit status of the last command in the pipe that failed
set -e          #  exit on error
set -u          #  treat unset variables as an error
set -x          #  print commands and their arguments as they are executed

if ! command -v nasm &>/dev/null; then
    echo "nasm could not be found, please install it"
    exit 1
fi

PREFIX="/data/$USER/amdsev/usr"
if [ !d "$PREFIX/share/qemu" ]; then
    echo "Directory $PREFIX/share/qemu does not exist, exiting"
    exit 1
fi

WORKDIR="/tmp/ovmf-snp-latest"

if [ -d "$WORKDIR" ]; then
    time rm -rf "$WORKDIR"
fi

git clone --quiet --depth=1 --branch=snp-latest https://github.com/AMDESE/ovmf.git "$WORKDIR"
cd "$WORKDIR"
git submodule update --init --depth=1
git submodule | awk '{print $2}' | xargs -P0 -I{} git submodule update --init --recursive --depth=1 -- {}

make -C BaseTools clean
make -C BaseTools -j $(getconf _NPROCESSORS_ONLN)

set +eux
. ./edksetup.sh --reconfig
set -eux

build \
    --quiet --cmd-len=64436 \
    -p OvmfPkg/OvmfPkgX64.dsc \
    -b DEBUG \
    -a X64 \
    -t GCC \
    -n $(getconf _NPROCESSORS_ONLN) \
    -DDEBUG_ON_SERIAL_PORT=TRUE \
    -Y COMPILE_INFO -y $(mktemp)

cp -f Build/OvmfX64/DEBUG_GCC/FV/OVMF_CODE.fd "$PREFIX/share/qemu"
cp -f Build/OvmfX64/DEBUG_GCC/FV/OVMF_VARS.fd "$PREFIX/share/qemu"
cp -f Build/OvmfX64/DEBUG_GCC/FV/OVMF.fd "$PREFIX/share/qemu"
