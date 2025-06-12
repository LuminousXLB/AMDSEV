/**
 * get_cbitpos.c
 *
 * This program retrieves the number of C-bit positions supported by the CPU
 * using the CPUID instruction and prints it to standard output.
 * The C-bit positions are indicated by the lower 6 bits of EBX register
 * when CPUID is called with EAX set to 0x8000001F and ECX set to 0.
 */

#include <stdint.h>
#include <stdio.h>

int main()
{
    uint32_t eax, ebx, ecx, edx;
    eax = 0x8000001f; // CPUID leaf for extended feature flags
    ecx = 0;          // Sub-leaf is 0 for this CPUID leaf

    asm volatile("cpuid"
                 : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
                 : "0"(eax), "2"(ecx));

#if DEBUG
    printf("eax: 0x%08x\n", eax);
    printf("ebx: 0x%08x\n", ebx);
    printf("ecx: 0x%08x\n", ecx);
    printf("edx: 0x%08x\n", edx);
#endif

    printf("%u\n", ebx & 0x3f);
}
