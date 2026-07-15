// Reconstructed source for testcase/ndk/ndk_basic/scripts/baremetal.bin
// 
// Based on mini-rv32ima upstream (https://github.com/cnlohr/mini-rv32ima)
// but simplified to match observed LuatOS NDK test behavior only.

#include <stdint.h>
#include <stddef.h>

/* RVC smoke test - only present in compressed variant */
#ifdef __riscv_compressed
extern unsigned int rvc_smoke_test(void);
#endif

// Control store address - linker provides as symbol
extern volatile uint32_t SYSCON;

// CSR-based logging functions (observed in LuatOS runtime)
static void lprint( const char * s )
{
	asm volatile( "csrrw x0, 0x138, %0" : : "r" (s));
}

static void pprint( intptr_t ptr )
{
	asm volatile( "csrrw x0, 0x137, %0" : : "r" (ptr));
}

static void nprint( intptr_t num )
{
	asm volatile( "csrrw x0, 0x136, %0" : : "r" (num));
}

static uint32_t ndk_exchange_base(void)
{
	uint32_t v = 0;
	asm volatile( ".option norvc\ncsrr %0, 0x139" : "=r"(v) );
	return v;
}

static uint32_t ndk_read_misa(void)
{
	uint32_t v = 0;
	asm volatile( ".option norvc\ncsrr %0, 0x301" : "=r"(v) );
	return v;
}

int main()
{
#ifdef __riscv_compressed
	/* Execute RVC smoke test in compressed variant */
	volatile unsigned int rvc_result = rvc_smoke_test();
	volatile uint32_t *exchange = (volatile uint32_t *)ndk_exchange_base();
	exchange[0] = rvc_result;
	exchange[1] = ndk_read_misa();
#endif

	// Debug logging block - matches observed test output
	lprint("\n");
	lprint("main is at: ");
	pprint( (intptr_t)main );
	
	char buffer[32];
	lprint("\nBuffer is at: ");
	pprint( (intptr_t)buffer );
	lprint("\nStack top is at: ");
	pprint( (intptr_t)&buffer[sizeof(buffer)-1] );

	// String length test - matches observed log messages
	lprint("\nTesting strlen optimization:");
	const char * teststr1 = "Hello, world!";
	const char * teststr2 = "This is a longer test string to check the strlen function optimization.";
	size_t len1 = __builtin_strlen(teststr1);
	size_t len2 = __builtin_strlen(teststr2);
	lprint("Length of teststr1: ");
	nprint(len1);
	lprint("\nLength of teststr2: ");
	nprint(len2);
	lprint("\n");

	// Exit via control store
	// Observed runtime log: "Control Store: set val to 00005555"
	SYSCON = 0x5555;
	
	return 0;
}

// Assembly entry point - simplified for observed behavior
__asm__(
".section .text.init\n"
".global _start\n"
".align 4\n"
"_start:\n"
"	lui	sp, %hi(_sstack)\n"
"	addi	sp, sp, %lo(_sstack)\n"
"	# BSS zeroing omitted: no globals in current reconstruction\n"
"	call	main\n"
"	j	.\n"  // Should not return
);

