/* Linker script for doom.bin with a PE toolchain (MSYS2 gcc on Windows).
 * The address must match DOOM_BASE in the Makefile and in doom.f. */
ENTRY(f64_main)
SECTIONS
{
  .text 0x1000000 : {
    *(.entry)
    *(.text) *(.text$*) *(.text.*)
  }
  .rdata : {
    *(.rdata) *(.rdata$*) *(.rodata) *(.rodata.*)
  }
  .data : {
    *(.data) *(.data$*) *(.data.*)
  }
  .bss : {
    __bss_start = .;
    *(.bss) *(.bss$*) *(.bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;
  }
  /DISCARD/ : {
    *(.pdata*) *(.xdata*) *(.comment) *(.drectve) *(.rdata$zzz)
    *(.eh_frame*) *(.debug*) *(.reloc) *(.idata*) *(.edata)
  }
}
