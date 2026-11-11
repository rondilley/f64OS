/* Linker script for doom.bin with an ELF toolchain (gcc on Linux).
 * The address must match DOOM_BASE in the Makefile and in doom.f. */
ENTRY(f64_main)
SECTIONS
{
  . = 0x1000000;
  .text : {
    *(.entry)
    *(.text .text.*)
  }
  .rodata : {
    *(.rodata .rodata.*)
  }
  .data : {
    *(.data .data.*)
  }
  .bss : {
    __bss_start = .;
    *(.bss .bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;
  }
  /DISCARD/ : {
    *(.comment) *(.eh_frame*) *(.note*) *(.debug*)
  }
}
