#!/bin/bash

set -euox pipefail

for f in $(find /sys/module/kvm_amd/parameters/ -maxdepth 1 -type f -name "sev*" | sort); do
    printf "%s = %s\n" "$(basename $f)" "$(cat $f)"
done

(dmesg | grep -i sev) || true
