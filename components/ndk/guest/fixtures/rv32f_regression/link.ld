/* Linker script for baremetal guest binary
 * Based on mini-rv32ima flatfile.lds
 * Produces flat binary loadable at 0x80000000
 */

__stack_size = 0x1000;

ENTRY(_start)

SECTIONS
{
	. = 0x80000000;

	.text : ALIGN(16) {
		*(.text.init)
		*(.text)
		*(.text.*)
	}

	.rodata : ALIGN(16) {
		*(.rodata)
		*(.rodata.*)
	}

	.data : ALIGN(16) {
		*(.data)
		*(.data.*)
	}

	.bss : ALIGN(16) {
		*(.bss)
		*(.bss.*)
	}

	.stack (NOLOAD) : ALIGN(16) {
		_estack = .;
		. = . + __stack_size;
		_sstack = .;
	}

	/* Control store exit address */
	PROVIDE( SYSCON = 0x11100000 );
}

