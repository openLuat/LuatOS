ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  /* host starts execution at the image base, so _start MUST be first:
   * lld lays sections out in object order and ignores ENTRY(). */
  .text : { KEEP(*(.text._start)) *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.* COMMON) }
}

