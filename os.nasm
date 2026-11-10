stage1_start:
    times 90 db 0 ; BPB (BIOS Parameter Block) will go here
    %include "stage1/bootstage1.nasm"
stage1_end:

stage2_start:
    %include "stage2/bootstage2.nasm"
    align 512, db 0
stage2_end:

kernel_start:
    %include "kernel/kernel.nasm"
    align 512, db 0
kernel_end:
