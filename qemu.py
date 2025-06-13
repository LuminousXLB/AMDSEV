#!/usr/bin/env python3
import argparse
import os
import re
import shlex
import sys
from pathlib import Path
from shutil import which

PREFIX = Path("/home/jiamin/AMDSEV/usr")


def parse_args():
    parser = argparse.ArgumentParser(
        description="QEMU VM Launcher with optional cloud-init and SNP support",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--smp", type=int, default=4, help="Number of CPUs")
    parser.add_argument("--mem", type=int, default=2048, help="Memory size in MB")
    parser.add_argument(
        "--uefi",
        type=Path,
        default=PREFIX / "share/qemu/OVMF.fd",
        help="Path to the UEFI firmware binary",
    )
    parser.add_argument("--seed", type=Path, help="Path to the cloud-init seed image")
    parser.add_argument("--disk", type=Path, help="Path to the hard disk image (qcow2)")
    parser.add_argument(
        "--monitor-socket", type=Path, help="Path to the QEMU monitor socket"
    )

    parser.add_argument(
        "--enable-net",
        action="store_true",
        default=True,
        help="Enable user-mode networking",
    )
    parser.add_argument(
        "--disable-net",
        action="store_false",
        dest="enable_net",
        help="Disable user-mode networking",
    )
    parser.add_argument(
        "--ssh-port",
        type=int,
        default=2222,
        help="Host port to forward to guest port 22",
    )

    parser.add_argument(
        "--enable-snp",
        action="store_true",
        default=False,
        help="Enable AMD SEV-SNP support",
    )
    parser.add_argument(
        "--disable-snp",
        action="store_false",
        dest="enable_snp",
        help="Disable AMD SEV-SNP support",
    )
    parser.add_argument("--debug-vmcb", action="store_true", help="Add debug VMCB")

    parser.add_argument(
        "-n", "--dry-run", action="store_true", help="Print command without executing"
    )

    return parser.parse_args()


def get_cbitpos():
    """
    Determine C-bit position based on AMD EPYC processor family/model.

    EPYC 7xx1 (Naples)  fam17h_model01h     C-bit position = 47
    EPYC 7xx2 (Rome)    fam17h_model3xh     C-bit position = 47
    EPYC 7xx3 (Milan)   fam19h_model0xh     C-bit position = 51
    EPYC 9xx4 (Genoa)   fam19h_model1xh     C-bit position = 51
    EPYC 9xx5 (Turin)   fam1ah_model0xh     C-bit position = 51
    """

    try:
        with open("/proc/cpuinfo", "r") as f:
            cpuinfo = f.read()
    except IOError as e:
        print(f"Failed to read /proc/cpuinfo: {e}", file=sys.stderr)
        sys.exit(1)

    family_match = re.search(r"cpu family\s+:\s+(\d+)", cpuinfo)
    model_match = re.search(r"model\s+:\s+(\d+)", cpuinfo)

    if not family_match or not model_match:
        print("Could not extract CPU family/model from /proc/cpuinfo", file=sys.stderr)
        sys.exit(1)

    fam = int(family_match.group(1))
    model = int(model_match.group(1))

    if fam == 0x17:
        if model == 0x01:  # fam17h_model01h
            return 47

        if model & 0xF0 == 0x30:  # fam17h_model3xh
            return 47

    if fam == 0x19:
        if model & 0xF0 == 0x00:  # fam19h_model0xh
            return 51

        if model & 0xF0 == 0x10:  # fam19h_model1xh
            return 51

    if fam == 0x1A:
        if model & 0xF0 == 0x00:  # fam1ah_model0xh
            return 51

    raise RuntimeError(
        "Unsupported CPU family/model combination: fam {}, model {}".format(fam, model)
    )


def args_common(smp=4, mem=2048, mon=None):
    args = [
        "-nographic",
        "-enable-kvm",
        "-cpu",
        "EPYC",
        "-machine",
        "q35",
        "-smp",
        f"{smp},maxcpus=255",
        "-m",
        f"{mem}M,slots=5,maxmem={mem+8192}M",
        "-no-reboot",
    ]

    if mon:
        args += ["-monitor", f"unix:{mon},server,nowait"]
    else:
        args += ["-monitor", "none"]

    return args


def args_cloud_init(seed_img: Path):
    if not seed_img.exists():
        raise ValueError("Cloud-init enabled but seed image does not exist.")

    return ["-drive", f"file={seed_img},index=1,media=cdrom"]


def args_network(ssh_port=-1):
    if ssh_port > 0:
        netdev = f"user,id=vmnic,hostfwd=tcp::{ssh_port}-:22"
    else:
        netdev = "user,id=vmnic"

    return [
        "-netdev",
        netdev,
        "-device",
        "virtio-net-pci,disable-legacy=on,iommu_platform=true,netdev=vmnic,romfile=",
    ]


def args_harddisk(image: Path, format="qcow2"):
    if not image.exists():
        raise ValueError("Hard disk image does not exist: {}".format(image))

    return [
        "-drive",
        f"file={image},if=none,id=disk0,format={format}",
        "-device",
        "virtio-scsi-pci,id=scsi0,disable-legacy=on,iommu_platform=true",
        "-device",
        "scsi-hd,drive=disk0",
    ]


def args_uefi(uefi_code: Path):
    if not uefi_code.exists():
        raise ValueError("UEFI firmware binary does not exist: {}".format(uefi_code))

    return ["-bios", str(uefi_code)]


def args_snp(mem=2048, debug=True):
    policy = 0x30000
    cbitpos = get_cbitpos()

    if debug:
        policy |= 0x80000

    return [
        "-machine",
        "confidential-guest-support=sev0,vmport=off",
        "-object",
        f"memory-backend-memfd,id=ram1,size={mem}M,share=true,prealloc=false",
        "-machine",
        "memory-backend=ram1",
        "-object",
        f"sev-snp-guest,id=sev0,policy={hex(policy)},cbitpos={cbitpos},reduced-phys-bits=1",
    ]


def build_qemu_command(args):
    qemu_args = []

    qemu_args += args_common(smp=args.smp, mem=args.mem, mon=args.monitor_socket)
    qemu_args += args_uefi(args.uefi)

    if args.seed:
        qemu_args += args_cloud_init(args.seed)

    if args.disk:
        qemu_args += args_harddisk(args.disk)

    if args.enable_net:
        qemu_args += args_network(ssh_port=args.ssh_port)

    if args.enable_snp:
        qemu_args += args_snp(mem=args.mem, debug=args.debug_vmcb)

    return qemu_args


if __name__ == "__main__":
    args = parse_args()
    qemu_args = build_qemu_command(args)

    path = PREFIX / "bin"
    qemu_exec = which("qemu-system-x86_64", path=path)

    if not qemu_exec:
        raise RuntimeError("QEMU executable not found in {}.".format(path))

    cmd = ["sudo", qemu_exec, *qemu_args]
    print(shlex.join(cmd))

    if not args.dry_run:
        os.execvp(cmd[0], cmd)
