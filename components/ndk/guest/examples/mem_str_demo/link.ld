ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  /* The host starts execution at the image base, so _start MUST be the
   * first bytes of .text. External-linkage functions (e.g. the libc
   * symbols from NDK_GUEST_PROVIDE_LIBC) would otherwise be placed
   * before it — lld emits sections in object order, not by ENTRY(). */
  .text : { KEEP(*(.text._start)) *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.* COMMON) }
}
