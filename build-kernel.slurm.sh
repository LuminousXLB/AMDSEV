#!/bin/bash
#SBATCH --partition=mi100_mi210
#SBATCH --cpus-per-task=96

set -euo pipefail
set -x

env

SCRIPT="/home/$USER/AMDSEV/build-kernel.py"
OUTDIR="/data/$USER/AMDSEV/linux/$(git rev-parse --short HEAD).$(hostname)"
WORKDIR="/tmp/$USER/AMDSEV"

echo "Job started on $(hostname) at $(date)"

if [ ! -f "$SCRIPT" ]; then
    echo "ERROR: Script not found at $SCRIPT"
    exit 1
fi

mkdir -p "$WORKDIR"
mkdir -p "$OUTDIR"

cd "$WORKDIR"
python3 "$SCRIPT"

find $WORKDIR/linux -maxdepth 1 -type f -exec cp "{}" "$OUTDIR" \;

echo "Job finished at $(date)"
