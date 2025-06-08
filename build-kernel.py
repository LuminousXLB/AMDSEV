#!/usr/bin/env python3
import os
from argparse import ArgumentParser
from enum import Enum
from multiprocessing import cpu_count
from pathlib import Path
from shutil import rmtree
from subprocess import CalledProcessError, check_call


class KernelType(Enum):
    HOST = "host"
    GUEST = "guest"


KERNEL_GIT_URL = "https://github.com/AMDESE/linux.git"
KERNEL_BRANCH = {
    KernelType.HOST: "snp-host-latest",
    KernelType.GUEST: "snp-guest-latest",
}


def prepare_source(kernel_type: KernelType):
    srctree = Path("linux") / kernel_type.value

    if srctree.exists():
        try:
            check_call(
                ["git", "fetch", "--depth=1", "origin", KERNEL_BRANCH[kernel_type]],
                cwd=srctree,
            )
            check_call(
                ["git", "checkout", "origin/{}".format(KERNEL_BRANCH[kernel_type])],
                cwd=srctree,
            )
            return srctree
        except CalledProcessError:
            print("Failed to fetch or checkout the kernel source tree.")
            rmtree(srctree)

    assert not srctree.exists(), "Source tree already exists"

    check_call(
        (
            "git",
            "clone",
            "--branch={}".format(KERNEL_BRANCH[kernel_type]),
            "--depth=1",
            "--",
            KERNEL_GIT_URL,
            srctree,
        )
    )

    return srctree


def build_kernel(kernel_type: KernelType):
    srctree = prepare_source(kernel_type)
    version = "-snp-{}".format(kernel_type.value)

    for file in srctree.parent.glob("*{}*".format(version)):
        print("Removing old kernel package: {}".format(file))
        file.unlink()

    def run_make(*args):
        check_call(
            ("make", "--jobs={}".format(cpu_count()), *args),
            cwd=srctree,
            env={
                "CC": "ccache gcc",
                **os.environ,
            },
        )

    def kconfig(*args):
        check_call(("./scripts/config", *args), cwd=srctree)

    run_make("distclean")
    run_make("defconfig")

    kconfig("--set-str", "LOCALVERSION", version)
    kconfig("--disable", "SYSTEM_TRUSTED_KEYS")
    kconfig("--disable", "SYSTEM_REVOCATION_KEYS")
    kconfig("--disable", "MODULE_SIG_KEY")

    kconfig("--disable", "IOMMU_DEFAULT_PASSTHROUGH")
    kconfig("--disable", "PREEMPT_COUNT")
    kconfig("--disable", "PREEMPTION")
    kconfig("--disable", "PREEMPT_DYNAMIC")
    kconfig("--disable", "DEBUG_PREEMPT")
    kconfig("--enable", "CGROUP_MISC")
    kconfig("--module", "X86_CPUID")
    kconfig("--disable", "UBSAN")
    kconfig("--set-val", "RCU_EXP_CPU_STALL_TIMEOUT", "1000")

    if kernel_type == KernelType.HOST:
        kconfig("--disable", "KVM_GUEST")
        kconfig("--enable", "KVM")
        kconfig("--enable", "KVM_AMD")
        kconfig("--enable", "CRYPTO_DEV_CCP")
        kconfig("--enable", "CRYPTO_DEV_CCP_DD")
        kconfig("--enable", "CRYPTO_DEV_SP_PSP")
        kconfig("--enable", "KVM_AMD_SEV")
    else:
        kconfig("--enable", "KVM_GUEST")
        kconfig("--enable", "VIRT_DRIVERS")
        kconfig("--enable", "SEV_GUEST")

    kconfig("--enable", "AMD_MEM_ENCRYPT")
    kconfig("--disable", "AMD_MEM_ENCRYPT_ACTIVE_BY_DEFAULT")

    kconfig("--enable", "EXPERT")
    kconfig("--enable", "DEBUG_INFO")
    kconfig("--enable", "DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT")
    kconfig("--enable", "DEBUG_INFO_REDUCED")

    # kconfig("--disable", "WLAN")
    # kconfig("--disable", "SOUND")
    # kconfig("--enable", "PROCESSOR_SELECT")
    # kconfig("--disable", "CPU_SUP_CENTAUR")
    # kconfig("--disable", "CPU_SUP_HYGON")
    # kconfig("--disable", "CPU_SUP_INTEL")
    # kconfig("--disable", "CPU_SUP_ZHAOXIN")
    # kconfig("--disable", "INTEL_IOMMU")
    # kconfig("--disable", "INTEL_MEI")
    # kconfig("--disable", "AGP_INTEL")
    # kconfig("--disable", "X86_MCE_INTEL")

    run_make("olddefconfig")

    if kernel_type == KernelType.HOST:
        assert "CONFIG_KVM_AMD_SEV=y" in (srctree / ".config").read_text()
        assert "CONFIG_AMD_MEM_ENCRYPT=y" in (srctree / ".config").read_text()
    else:
        assert "CONFIG_KVM_GUEST=y" in (srctree / ".config").read_text()
        assert "CONFIG_SEV_GUEST=y" in (srctree / ".config").read_text()

    assert "CONFIG_DEBUG_INFO=y" in (srctree / ".config").read_text()

    run_make("bindeb-pkg")


def parse_args():
    parser = ArgumentParser(description="Build the kernel for SEV-SNP")
    parser.add_argument("--guest", action="store_true", help="Build the guest kernel")
    parser.add_argument("--host", action="store_true", help="Build the host kernel")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    if not args.guest and not args.host:
        args.guest = True
        args.host = True

    if args.guest:
        print("Building guest kernel")
        build_kernel(KernelType.GUEST)

    if args.host:
        print("Building host kernel")
        build_kernel(KernelType.HOST)
