// Copyright 2022 Charles Lohr, you may use this file or any portions herein under any of the BSD, MIT, or CC0 licenses.

#ifndef _MINI_RV32IMAH_H
#define _MINI_RV32IMAH_H

/**
    To use mini-rv32ima.h for the bare minimum, the following:

	#define MINI_RV32_RAM_SIZE ram_amt
	#define MINIRV32_IMPLEMENTATION

	#include "mini-rv32ima.h"

	Though, that's not _that_ interesting. You probably want I/O!


	Notes:
		* There is a dedicated CLNT at 0x10000000.
		* There is free MMIO from there to 0x12000000.
		* You can put things like a UART, or whatever there.
		* Feel free to override any of the functionality with macros.
*/

#ifndef MINIRV32WARN
	#define MINIRV32WARN(... );
#endif

#ifndef MINIRV32_DECORATE
	#define MINIRV32_DECORATE static
#endif

#ifndef MINIRV32_RAM_IMAGE_OFFSET
	#define MINIRV32_RAM_IMAGE_OFFSET  0x80000000
#endif

#ifndef MINIRV32_MMIO_RANGE
	#define MINIRV32_MMIO_RANGE(n)  (0x10000000 <= (n) && (n) < 0x12000000)
#endif

#ifndef MINIRV32_POSTEXEC
	#define MINIRV32_POSTEXEC(...);
#endif

#ifndef MINIRV32_HANDLE_MEM_STORE_CONTROL
	#define MINIRV32_HANDLE_MEM_STORE_CONTROL(...);
#endif

#ifndef MINIRV32_HANDLE_MEM_LOAD_CONTROL
	#define MINIRV32_HANDLE_MEM_LOAD_CONTROL(...);
#endif

#ifndef MINIRV32_OTHERCSR_WRITE
	#define MINIRV32_OTHERCSR_WRITE(...);
#endif

#ifndef MINIRV32_OTHERCSR_READ
	#define MINIRV32_OTHERCSR_READ(...);
#endif

#ifndef MINIRV32_CUSTOM_MEMORY_BUS
	#define MINIRV32_STORE4( ofs, val ) *(uint32_t*)(image + ofs) = val
	#define MINIRV32_STORE2( ofs, val ) *(uint16_t*)(image + ofs) = val
	#define MINIRV32_STORE1( ofs, val ) *(uint8_t*)(image + ofs) = val
	#define MINIRV32_LOAD4( ofs ) *(uint32_t*)(image + ofs)
	#define MINIRV32_LOAD2( ofs ) *(uint16_t*)(image + ofs)
	#define MINIRV32_LOAD1( ofs ) *(uint8_t*)(image + ofs)
	#define MINIRV32_LOAD2_SIGNED( ofs ) *(int16_t*)(image + ofs)
	#define MINIRV32_LOAD1_SIGNED( ofs ) *(int8_t*)(image + ofs)
#endif

// As a note: We quouple-ify these, because in HLSL, we will be operating with
// uint4's.  We are going to uint4 data to/from system RAM.
//
// We're going to try to keep the full processor state to 12 x uint4.
struct MiniRV32IMAState
{
	uint32_t regs[32];
	uint32_t fregs[32];

	uint32_t pc;
	uint32_t mstatus;
	uint32_t cyclel;
	uint32_t cycleh;

	uint32_t timerl;
	uint32_t timerh;
	uint32_t timermatchl;
	uint32_t timermatchh;

	uint32_t mscratch;
	uint32_t mtvec;
	uint32_t mie;
	uint32_t mip;

	uint32_t mepc;
	uint32_t mtval;
	uint32_t mcause;

	// Note: only a few bits are used.  (Machine = 3, User = 0)
	// Bits 0..1 = privilege.
	// Bit 2 = WFI (Wait for interrupt)
	// Bit 3+ = Load/Store reservation LSBs.
	uint32_t extraflags;
};

#ifndef MINIRV32_STEPPROTO
MINIRV32_DECORATE int32_t MiniRV32IMAStep( struct MiniRV32IMAState * state, uint8_t * image, uint32_t vProcAddress, uint32_t elapsedUs, int count );
#endif

#ifdef MINIRV32_IMPLEMENTATION

#ifndef MINIRV32_CUSTOM_INTERNALS
#define CSR( x ) state->x
#define SETCSR( x, val ) { state->x = val; }
#define REG( x ) state->regs[x]
#define REGSET( x, val ) { state->regs[x] = val; }
#define FREG( x ) state->fregs[x]
#define FREGSET( x, val ) { state->fregs[x] = val; }
#endif

#ifdef MINIRV32_LUATOS_RV32C_PATCH
// === LuatOS local patch begin: RV32C fetch/alignment/decompression support ===
static inline int32_t MiniRV32_SignExtend(uint32_t value, uint32_t bits)
{
	return ((int32_t)(value << (32 - bits))) >> (32 - bits);
}

static inline uint32_t MiniRV32_RType(uint32_t funct7, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode)
{
	return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}

static inline uint32_t MiniRV32_IType(int32_t imm, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode)
{
	return (((uint32_t)imm & 0xfff) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}

static inline uint32_t MiniRV32_SType(int32_t imm, uint32_t rs1, uint32_t rs2, uint32_t funct3, uint32_t opcode)
{
	uint32_t uimm = (uint32_t)imm;
	return (((uimm >> 5) & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((uimm & 0x1f) << 7) | opcode;
}

static inline uint32_t MiniRV32_BType(int32_t imm, uint32_t rs1, uint32_t rs2, uint32_t funct3, uint32_t opcode)
{
	uint32_t uimm = (uint32_t)imm;
	return (((uimm >> 12) & 0x1) << 31) | (((uimm >> 5) & 0x3f) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) |
		(((uimm >> 1) & 0xf) << 8) | (((uimm >> 11) & 0x1) << 7) | opcode;
}

static inline uint32_t MiniRV32_UType(int32_t imm, uint32_t rd, uint32_t opcode)
{
	return ((uint32_t)imm & 0xfffff000) | (rd << 7) | opcode;
}

static inline uint32_t MiniRV32_JType(int32_t imm, uint32_t rd, uint32_t opcode)
{
	uint32_t uimm = (uint32_t)imm;
	return (((uimm >> 20) & 0x1) << 31) | (((uimm >> 1) & 0x3ff) << 21) | (((uimm >> 11) & 0x1) << 20) |
		(((uimm >> 12) & 0xff) << 12) | (rd << 7) | opcode;
}

static inline int MiniRV32_DecompressC(uint16_t ir, uint32_t *out_ir)
{
	uint32_t quadrant = ir & 0x3;
	uint32_t funct3 = ir >> 13;
	uint32_t rd = (ir >> 7) & 0x1f;
	uint32_t rs2 = (ir >> 2) & 0x1f;
	uint32_t rdp = 8 + ((ir >> 2) & 0x7);
	uint32_t rs1p = 8 + ((ir >> 7) & 0x7);
	int32_t imm = 0;

	if( ir == 0 )
		return 0;

	switch( quadrant )
	{
		case 0:
			switch( funct3 )
			{
				case 0: // C.ADDI4SPN
					imm = (((ir >> 6) & 0x1) << 2) | (((ir >> 5) & 0x1) << 3) | (((ir >> 11) & 0x3) << 4) | (((ir >> 7) & 0xf) << 6);
					if( imm == 0 ) return 0;
					*out_ir = MiniRV32_IType( imm, 2, 0, rdp, 0x13 );
					return 1;
				case 2: // C.LW
					imm = (((ir >> 6) & 0x1) << 2) | (((ir >> 10) & 0x7) << 3) | (((ir >> 5) & 0x1) << 6);
					*out_ir = MiniRV32_IType( imm, rs1p, 2, rdp, 0x03 );
					return 1;
				case 6: // C.SW
					imm = (((ir >> 6) & 0x1) << 2) | (((ir >> 10) & 0x7) << 3) | (((ir >> 5) & 0x1) << 6);
					*out_ir = MiniRV32_SType( imm, rs1p, rdp, 2, 0x23 );
					return 1;
				default:
					return 0;
			}
		case 1:
			switch( funct3 )
			{
				case 0: // C.ADDI / C.NOP
					imm = MiniRV32_SignExtend( ((ir >> 2) & 0x1f) | (((ir >> 12) & 0x1) << 5), 6 );
					if( rd == 0 )
					{
						if( imm != 0 ) return 0;
						*out_ir = MiniRV32_IType( 0, 0, 0, 0, 0x13 );
					}
					else
						*out_ir = MiniRV32_IType( imm, rd, 0, rd, 0x13 );
					return 1;
				case 1: // C.JAL (RV32C only)
				case 5: // C.J
					imm = (((ir >> 3) & 0x7) << 1) | (((ir >> 11) & 0x1) << 4) | (((ir >> 2) & 0x1) << 5) |
						(((ir >> 7) & 0x1) << 6) | (((ir >> 6) & 0x1) << 7) | (((ir >> 9) & 0x3) << 8) |
						(((ir >> 8) & 0x1) << 10) | (((ir >> 12) & 0x1) << 11);
					imm = MiniRV32_SignExtend( imm, 12 );
					*out_ir = MiniRV32_JType( imm, (funct3 == 1) ? 1 : 0, 0x6f );
					return 1;
				case 2: // C.LI
					if( rd == 0 ) return 0;
					imm = MiniRV32_SignExtend( ((ir >> 2) & 0x1f) | (((ir >> 12) & 0x1) << 5), 6 );
					*out_ir = MiniRV32_IType( imm, 0, 0, rd, 0x13 );
					return 1;
				case 3: // C.ADDI16SP / C.LUI
					imm = MiniRV32_SignExtend( ((ir >> 2) & 0x1f) | (((ir >> 12) & 0x1) << 5), 6 );
					if( rd == 2 )
					{
						imm = (((ir >> 6) & 0x1) << 4) | (((ir >> 2) & 0x1) << 5) | (((ir >> 5) & 0x1) << 6) |
							(((ir >> 3) & 0x3) << 7) | (((ir >> 12) & 0x1) << 9);
						imm = MiniRV32_SignExtend( imm, 10 );
						if( imm == 0 ) return 0;
						*out_ir = MiniRV32_IType( imm, 2, 0, 2, 0x13 );
					}
					else
					{
						if( rd == 0 || imm == 0 ) return 0;
						*out_ir = MiniRV32_UType( imm << 12, rd, 0x37 );
					}
					return 1;
				case 4:
				{
					uint32_t subop = (ir >> 10) & 0x3;
					uint32_t rs1 = rs1p;
					if( subop == 0 ) // C.SRLI
					{
						imm = ((ir >> 2) & 0x1f) | (((ir >> 12) & 0x1) << 5);
						if( imm == 0 ) return 0;
						*out_ir = MiniRV32_IType( imm, rs1, 5, rs1, 0x13 );
						return 1;
					}
					if( subop == 1 ) // C.SRAI
					{
						imm = ((ir >> 2) & 0x1f) | (((ir >> 12) & 0x1) << 5);
						if( imm == 0 ) return 0;
						*out_ir = MiniRV32_IType( imm | (1 << 10), rs1, 5, rs1, 0x13 );
						return 1;
					}
					if( subop == 2 ) // C.ANDI
					{
						imm = MiniRV32_SignExtend( ((ir >> 2) & 0x1f) | (((ir >> 12) & 0x1) << 5), 6 );
						*out_ir = MiniRV32_IType( imm, rs1, 7, rs1, 0x13 );
						return 1;
					}
					{
						uint32_t funct2 = (ir >> 5) & 0x3;
						uint32_t rs2p = 8 + ((ir >> 2) & 0x7);
						uint32_t funct6 = (ir >> 10) & 0x3f;
						if( funct6 == 0x23 )
						{
							switch( funct2 )
							{
								case 0: *out_ir = MiniRV32_RType( 0x20, rs2p, rs1, 0, rs1, 0x33 ); return 1; // C.SUB
								case 1: *out_ir = MiniRV32_RType( 0x00, rs2p, rs1, 4, rs1, 0x33 ); return 1; // C.XOR
								case 2: *out_ir = MiniRV32_RType( 0x00, rs2p, rs1, 6, rs1, 0x33 ); return 1; // C.OR
								case 3: *out_ir = MiniRV32_RType( 0x00, rs2p, rs1, 7, rs1, 0x33 ); return 1; // C.AND
							}
						}
					}
					return 0;
				}
				case 6: // C.BEQZ
				case 7: // C.BNEZ
					imm = (((ir >> 3) & 0x3) << 1) | (((ir >> 10) & 0x3) << 3) | (((ir >> 2) & 0x1) << 5) |
						(((ir >> 5) & 0x3) << 6) | (((ir >> 12) & 0x1) << 8);
					imm = MiniRV32_SignExtend( imm, 9 );
					*out_ir = MiniRV32_BType( imm, rs1p, 0, (funct3 == 6) ? 0 : 1, 0x63 );
					return 1;
				default:
					return 0;
			}
		case 2:
			switch( funct3 )
			{
				case 0: // C.SLLI
					imm = ((ir >> 2) & 0x1f) | (((ir >> 12) & 0x1) << 5);
					if( rd == 0 || imm == 0 ) return 0;
					*out_ir = MiniRV32_IType( imm, rd, 1, rd, 0x13 );
					return 1;
				case 2: // C.LWSP
					if( rd == 0 ) return 0;
					imm = (((ir >> 4) & 0x7) << 2) | (((ir >> 12) & 0x1) << 5) | (((ir >> 2) & 0x3) << 6);
					*out_ir = MiniRV32_IType( imm, 2, 2, rd, 0x03 );
					return 1;
				case 4:
					if( ((ir >> 12) & 1) == 0 )
					{
						if( rs2 == 0 )
						{
							if( rd == 0 ) return 0;
							*out_ir = MiniRV32_IType( 0, rd, 0, 0, 0x67 );
						}
						else
						{
							if( rd == 0 ) return 0;
							*out_ir = MiniRV32_RType( 0x00, rs2, 0, 0, rd, 0x33 );
						}
					}
					else
					{
						if( rs2 == 0 )
						{
							if( rd == 0 )
								*out_ir = 0x00100073; // EBREAK
							else
								*out_ir = MiniRV32_IType( 0, rd, 0, 1, 0x67 );
						}
						else
						{
							if( rd == 0 ) return 0;
							*out_ir = MiniRV32_RType( 0x00, rs2, rd, 0, rd, 0x33 );
						}
					}
					return 1;
				case 6: // C.SWSP
					imm = (((ir >> 9) & 0xf) << 2) | (((ir >> 7) & 0x3) << 6);
					*out_ir = MiniRV32_SType( imm, 2, rs2, 2, 0x23 );
					return 1;
				default:
					return 0;
			}
		default:
			return 0;
	}
}
// === LuatOS local patch end: RV32C fetch/alignment/decompression support ===
#endif

#ifndef MINIRV32_HAS_F_EXTENSION
#define MINIRV32_HAS_F_EXTENSION() 0
#endif

#ifndef MINIRV32_FADD_S
#define MINIRV32_FADD_S(rs1_bits, rs2_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FSUB_S
#define MINIRV32_FSUB_S(rs1_bits, rs2_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FMUL_S
#define MINIRV32_FMUL_S(rs1_bits, rs2_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FDIV_S
#define MINIRV32_FDIV_S(rs1_bits, rs2_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FMADD_S
#define MINIRV32_FMADD_S(rs1_bits, rs2_bits, rs3_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FMSUB_S
#define MINIRV32_FMSUB_S(rs1_bits, rs2_bits, rs3_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FNMSUB_S
#define MINIRV32_FNMSUB_S(rs1_bits, rs2_bits, rs3_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FNMADD_S
#define MINIRV32_FNMADD_S(rs1_bits, rs2_bits, rs3_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FSQRT_S
#define MINIRV32_FSQRT_S(rs1_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FEQ_S
#define MINIRV32_FEQ_S(rs1_bits, rs2_bits, out_bits) 0
#endif

#ifndef MINIRV32_FLT_S
#define MINIRV32_FLT_S(rs1_bits, rs2_bits, out_bits) 0
#endif

#ifndef MINIRV32_FLE_S
#define MINIRV32_FLE_S(rs1_bits, rs2_bits, out_bits) 0
#endif

#ifndef MINIRV32_FCLASS_S
#define MINIRV32_FCLASS_S(rs1_bits, out_bits) 0
#endif

#ifndef MINIRV32_FSGNJ_S
#define MINIRV32_FSGNJ_S(rs1_bits, rs2_bits, out_bits) 0
#endif

#ifndef MINIRV32_FSGNJN_S
#define MINIRV32_FSGNJN_S(rs1_bits, rs2_bits, out_bits) 0
#endif

#ifndef MINIRV32_FSGNJX_S
#define MINIRV32_FSGNJX_S(rs1_bits, rs2_bits, out_bits) 0
#endif

#ifndef MINIRV32_FMIN_S
#define MINIRV32_FMIN_S(rs1_bits, rs2_bits, out_bits) 0
#endif

#ifndef MINIRV32_FMAX_S
#define MINIRV32_FMAX_S(rs1_bits, rs2_bits, out_bits) 0
#endif

#ifndef MINIRV32_FCVT_S_W
#define MINIRV32_FCVT_S_W(rs1_value, rm, out_bits) 0
#endif

#ifndef MINIRV32_FCVT_S_WU
#define MINIRV32_FCVT_S_WU(rs1_value, rm, out_bits) 0
#endif

#ifndef MINIRV32_FCVT_W_S
#define MINIRV32_FCVT_W_S(rs1_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_FCVT_WU_S
#define MINIRV32_FCVT_WU_S(rs1_bits, rm, out_bits) 0
#endif

#ifndef MINIRV32_GET_MISA
#define MINIRV32_GET_MISA() 0x40401101u
#endif

#ifndef MINIRV32_STEPPROTO
MINIRV32_DECORATE int32_t MiniRV32IMAStep( struct MiniRV32IMAState * state, uint8_t * image, uint32_t vProcAddress, uint32_t elapsedUs, int count )
#else
MINIRV32_STEPPROTO
#endif
{
	uint32_t new_timer = CSR( timerl ) + elapsedUs;
	if( new_timer < CSR( timerl ) ) CSR( timerh )++;
	CSR( timerl ) = new_timer;

	// Handle Timer interrupt.
	if( ( CSR( timerh ) > CSR( timermatchh ) || ( CSR( timerh ) == CSR( timermatchh ) && CSR( timerl ) > CSR( timermatchl ) ) ) && ( CSR( timermatchh ) || CSR( timermatchl ) ) )
	{
		CSR( extraflags ) &= ~4; // Clear WFI
		CSR( mip ) |= 1<<7; //MTIP of MIP // https://stackoverflow.com/a/61916199/2926815  Fire interrupt.
	}
	else
		CSR( mip ) &= ~(1<<7);

	// If WFI, don't run processor.
	if( CSR( extraflags ) & 4 )
		return 1;

	uint32_t trap = 0;
	uint32_t rval = 0;
	uint32_t pc = CSR( pc );
	uint32_t cycle = CSR( cyclel );
	uint32_t inst_len = 4;

	if( ( CSR( mip ) & (1<<7) ) && ( CSR( mie ) & (1<<7) /*mtie*/ ) && ( CSR( mstatus ) & 0x8 /*mie*/) )
	{
		// Timer interrupt.
		trap = 0x80000007;
		pc -= inst_len;
	}
	else // No timer interrupt?  Execute a bunch of instructions.
	for( int icount = 0; icount < count; icount++ )
	{
		uint32_t ir = 0;
		rval = 0;
		cycle++;
		uint32_t ofs_pc = pc - MINIRV32_RAM_IMAGE_OFFSET;

		if( ofs_pc >= MINI_RV32_RAM_SIZE || ( MINI_RV32_RAM_SIZE - ofs_pc ) < 2 )
		{
			trap = 1 + 1;  // Handle access violation on instruction read.
			break;
		}
		else if( ofs_pc & 1 )
		{
			trap = 1 + 0;  //Handle PC-misaligned access
			break;
		}
		else
		{
			uint16_t ir16 = MINIRV32_LOAD2( ofs_pc );
#ifdef MINIRV32_LUATOS_RV32C_PATCH
			if( ( ir16 & 0x3 ) == 0x3 )
			{
				if( ( MINI_RV32_RAM_SIZE - ofs_pc ) < 4 )
				{
					trap = 1 + 1;
					break;
				}
				ir = ir16 | ( MINIRV32_LOAD2( ofs_pc + 2 ) << 16 );
				inst_len = 4;
			}
			else
			{
				inst_len = 2;
				ir = ir16;
				if( !MiniRV32_DecompressC( ir16, &ir ) )
				{
					trap = (2+1);
					break;
				}
			}
#else
			if( ( MINI_RV32_RAM_SIZE - ofs_pc ) < 4 )
			{
				trap = 1 + 1;
				break;
			}
			ir = ir16 | ( MINIRV32_LOAD2( ofs_pc + 2 ) << 16 );
			inst_len = 4;
#endif
			uint32_t rdid = (ir >> 7) & 0x1f;

			switch( ir & 0x7f )
			{
				case 0x37: // LUI (0b0110111)
					rval = ( ir & 0xfffff000 );
					break;
				case 0x17: // AUIPC (0b0010111)
					rval = pc + ( ir & 0xfffff000 );
					break;
				case 0x6F: // JAL (0b1101111)
				{
					int32_t reladdy = ((ir & 0x80000000)>>11) | ((ir & 0x7fe00000)>>20) | ((ir & 0x00100000)>>9) | ((ir&0x000ff000));
					if( reladdy & 0x00100000 ) reladdy |= 0xffe00000; // Sign extension.
					rval = pc + inst_len;
					pc = pc + reladdy - inst_len;
					break;
				}
				case 0x67: // JALR (0b1100111)
				{
					uint32_t imm = ir >> 20;
					int32_t imm_se = imm | (( imm & 0x800 )?0xfffff000:0);
					rval = pc + inst_len;
					pc = ( (REG( (ir >> 15) & 0x1f ) + imm_se) & ~1) - inst_len;
					break;
				}
				case 0x63: // Branch (0b1100011)
				{
					uint32_t immm4 = ((ir & 0xf00)>>7) | ((ir & 0x7e000000)>>20) | ((ir & 0x80) << 4) | ((ir >> 31)<<12);
					if( immm4 & 0x1000 ) immm4 |= 0xffffe000;
					int32_t rs1 = REG((ir >> 15) & 0x1f);
					int32_t rs2 = REG((ir >> 20) & 0x1f);
					immm4 = pc + immm4 - inst_len;
					rdid = 0;
					switch( ( ir >> 12 ) & 0x7 )
					{
						// BEQ, BNE, BLT, BGE, BLTU, BGEU
						case 0: if( rs1 == rs2 ) pc = immm4; break;
						case 1: if( rs1 != rs2 ) pc = immm4; break;
						case 4: if( rs1 < rs2 ) pc = immm4; break;
						case 5: if( rs1 >= rs2 ) pc = immm4; break; //BGE
						case 6: if( (uint32_t)rs1 < (uint32_t)rs2 ) pc = immm4; break;   //BLTU
						case 7: if( (uint32_t)rs1 >= (uint32_t)rs2 ) pc = immm4; break;  //BGEU
						default: trap = (2+1);
					}
					break;
				}
				case 0x03: // Load (0b0000011)
				{
					uint32_t rs1 = REG((ir >> 15) & 0x1f);
					uint32_t imm = ir >> 20;
					int32_t imm_se = imm | (( imm & 0x800 )?0xfffff000:0);
					uint32_t rsval = rs1 + imm_se;

					rsval -= MINIRV32_RAM_IMAGE_OFFSET;
					if( rsval >= MINI_RV32_RAM_SIZE-3 )
					{
						rsval += MINIRV32_RAM_IMAGE_OFFSET;
						if( MINIRV32_MMIO_RANGE( rsval ) )  // UART, CLNT
						{
							MINIRV32_HANDLE_MEM_LOAD_CONTROL( rsval, rval );
						}
						else
						{
							trap = (5+1);
							rval = rsval;
						}
					}
					else
					{
						switch( ( ir >> 12 ) & 0x7 )
						{
							//LB, LH, LW, LBU, LHU
							case 0: rval = MINIRV32_LOAD1_SIGNED( rsval ); break;
							case 1: rval = MINIRV32_LOAD2_SIGNED( rsval ); break;
							case 2: rval = MINIRV32_LOAD4( rsval ); break;
							case 4: rval = MINIRV32_LOAD1( rsval ); break;
							case 5: rval = MINIRV32_LOAD2( rsval ); break;
							default: trap = (2+1);
						}
					}
					break;
				}
				case 0x07: // Load-FP (0b0000111)
				{
					uint32_t rs1 = REG((ir >> 15) & 0x1f);
					uint32_t imm = ir >> 20;
					int32_t imm_se = imm | (( imm & 0x800 )?0xfffff000:0);
					uint32_t rsval = rs1 + imm_se;

					if( !MINIRV32_HAS_F_EXTENSION() )
					{
						trap = (2+1);
						break;
					}

					rsval -= MINIRV32_RAM_IMAGE_OFFSET;
					if( rsval >= MINI_RV32_RAM_SIZE-3 )
					{
						rsval += MINIRV32_RAM_IMAGE_OFFSET;
						if( MINIRV32_MMIO_RANGE( rsval ) )
						{
							trap = (5+1);
							rval = rsval;
						}
						else
						{
							trap = (5+1);
							rval = rsval;
						}
					}
					else
					{
						switch( ( ir >> 12 ) & 0x7 )
						{
							case 2: FREGSET( rdid, MINIRV32_LOAD4( rsval ) ); rdid = 0; break;
							default: trap = (2+1); break;
						}
					}
					break;
				}
				case 0x23: // Store 0b0100011
				{
					uint32_t rs1 = REG((ir >> 15) & 0x1f);
					uint32_t rs2 = REG((ir >> 20) & 0x1f);
					uint32_t addy = ( ( ir >> 7 ) & 0x1f ) | ( ( ir & 0xfe000000 ) >> 20 );
					if( addy & 0x800 ) addy |= 0xfffff000;
					addy += rs1 - MINIRV32_RAM_IMAGE_OFFSET;
					rdid = 0;

					if( addy >= MINI_RV32_RAM_SIZE-3 )
					{
						addy += MINIRV32_RAM_IMAGE_OFFSET;
						if( MINIRV32_MMIO_RANGE( addy ) )
						{
							MINIRV32_HANDLE_MEM_STORE_CONTROL( addy, rs2 );
						}
						else
						{
							trap = (7+1); // Store access fault.
							rval = addy;
						}
					}
					else
					{
						switch( ( ir >> 12 ) & 0x7 )
						{
							//SB, SH, SW
							case 0: MINIRV32_STORE1( addy, rs2 ); break;
							case 1: MINIRV32_STORE2( addy, rs2 ); break;
							case 2: MINIRV32_STORE4( addy, rs2 ); break;
							default: trap = (2+1);
						}
					}
					break;
				}
				case 0x27: // Store-FP (0b0100111)
				{
					uint32_t rs1 = REG((ir >> 15) & 0x1f);
					uint32_t addy = ( ( ir >> 7 ) & 0x1f ) | ( ( ir & 0xfe000000 ) >> 20 );
					uint32_t rs2 = FREG((ir >> 20) & 0x1f);
					if( addy & 0x800 ) addy |= 0xfffff000;
					addy += rs1 - MINIRV32_RAM_IMAGE_OFFSET;
					rdid = 0;

					if( !MINIRV32_HAS_F_EXTENSION() )
					{
						trap = (2+1);
						break;
					}

					if( addy >= MINI_RV32_RAM_SIZE-3 )
					{
						addy += MINIRV32_RAM_IMAGE_OFFSET;
						if( MINIRV32_MMIO_RANGE( addy ) )
						{
							trap = (7+1);
							rval = addy;
						}
						else
						{
							trap = (7+1);
							rval = addy;
						}
					}
					else
					{
						switch( ( ir >> 12 ) & 0x7 )
						{
							case 2: MINIRV32_STORE4( addy, rs2 ); break;
							default: trap = (2+1); break;
						}
					}
					break;
				}
				case 0x13: // Op-immediate 0b0010011
				case 0x33: // Op           0b0110011
				{
					uint32_t imm = ir >> 20;
					imm = imm | (( imm & 0x800 )?0xfffff000:0);
					uint32_t rs1 = REG((ir >> 15) & 0x1f);
					uint32_t is_reg = !!( ir & 0x20 );
					uint32_t rs2 = is_reg ? REG(imm & 0x1f) : imm;

					if( is_reg && ( ir & 0x02000000 ) )
					{
						switch( (ir>>12)&7 ) //0x02000000 = RV32M
						{
							case 0: rval = rs1 * rs2; break; // MUL
#ifndef CUSTOM_MULH // If compiling on a system that doesn't natively, or via libgcc support 64-bit math.
							case 1: rval = ((int64_t)((int32_t)rs1) * (int64_t)((int32_t)rs2)) >> 32; break; // MULH
							case 2: rval = ((int64_t)((int32_t)rs1) * (uint64_t)rs2) >> 32; break; // MULHSU
							case 3: rval = ((uint64_t)rs1 * (uint64_t)rs2) >> 32; break; // MULHU
#else
							CUSTOM_MULH
#endif
							case 4: if( rs2 == 0 ) rval = -1; else rval = ((int32_t)rs1 == INT32_MIN && (int32_t)rs2 == -1) ? rs1 : ((int32_t)rs1 / (int32_t)rs2); break; // DIV
							case 5: if( rs2 == 0 ) rval = 0xffffffff; else rval = rs1 / rs2; break; // DIVU
							case 6: if( rs2 == 0 ) rval = rs1; else rval = ((int32_t)rs1 == INT32_MIN && (int32_t)rs2 == -1) ? 0 : ((uint32_t)((int32_t)rs1 % (int32_t)rs2)); break; // REM
							case 7: if( rs2 == 0 ) rval = rs1; else rval = rs1 % rs2; break; // REMU
						}
					}
					else
					{
						switch( (ir>>12)&7 ) // These could be either op-immediate or op commands.  Be careful.
						{
							case 0: rval = (is_reg && (ir & 0x40000000) ) ? ( rs1 - rs2 ) : ( rs1 + rs2 ); break; 
							case 1: rval = rs1 << (rs2 & 0x1F); break;
							case 2: rval = (int32_t)rs1 < (int32_t)rs2; break;
							case 3: rval = rs1 < rs2; break;
							case 4: rval = rs1 ^ rs2; break;
							case 5: rval = (ir & 0x40000000 ) ? ( ((int32_t)rs1) >> (rs2 & 0x1F) ) : ( rs1 >> (rs2 & 0x1F) ); break;
							case 6: rval = rs1 | rs2; break;
							case 7: rval = rs1 & rs2; break;
						}
					}
					break;
				}
				case 0x0f: // 0b0001111
					rdid = 0;   // fencetype = (ir >> 12) & 0b111; We ignore fences in this impl.
					break;
				case 0x73: // Zifencei+Zicsr  (0b1110011)
				{
					uint32_t csrno = ir >> 20;
					uint32_t microop = ( ir >> 12 ) & 0x7;
					if( (microop & 3) ) // It's a Zicsr function.
					{
						int rs1imm = (ir >> 15) & 0x1f;
						uint32_t rs1 = REG(rs1imm);
						uint32_t writeval = rs1;

						// https://raw.githubusercontent.com/riscv/virtual-memory/main/specs/663-Svpbmt.pdf
						// Generally, support for Zicsr
						switch( csrno )
						{
						case 0x340: rval = CSR( mscratch ); break;
						case 0x305: rval = CSR( mtvec ); break;
						case 0x304: rval = CSR( mie ); break;
						case 0xC00: rval = cycle; break;
						case 0x344: rval = CSR( mip ); break;
						case 0x341: rval = CSR( mepc ); break;
						case 0x300: rval = CSR( mstatus ); break; //mstatus
						case 0x342: rval = CSR( mcause ); break;
						case 0x343: rval = CSR( mtval ); break;
						case 0xf11: rval = 0xff0ff0ff; break; //mvendorid
						case 0x301: rval = MINIRV32_GET_MISA(); break; //misa (XLEN=32, IMA+X[+F])
						//case 0x3B0: rval = 0; break; //pmpaddr0
						//case 0x3a0: rval = 0; break; //pmpcfg0
						//case 0xf12: rval = 0x00000000; break; //marchid
						//case 0xf13: rval = 0x00000000; break; //mimpid
						//case 0xf14: rval = 0x00000000; break; //mhartid
						default:
							MINIRV32_OTHERCSR_READ( csrno, rval );
							break;
						}

						switch( microop )
						{
							case 1: writeval = rs1; break;  			//CSRRW
							case 2: writeval = rval | rs1; break;		//CSRRS
							case 3: writeval = rval & ~rs1; break;		//CSRRC
							case 5: writeval = rs1imm; break;			//CSRRWI
							case 6: writeval = rval | rs1imm; break;	//CSRRSI
							case 7: writeval = rval & ~rs1imm; break;	//CSRRCI
						}

						switch( csrno )
						{
						case 0x340: SETCSR( mscratch, writeval ); break;
						case 0x305: SETCSR( mtvec, writeval ); break;
						case 0x304: SETCSR( mie, writeval ); break;
						case 0x344: SETCSR( mip, writeval ); break;
						case 0x341: SETCSR( mepc, writeval ); break;
						case 0x300: SETCSR( mstatus, writeval ); break; //mstatus
						case 0x342: SETCSR( mcause, writeval ); break;
						case 0x343: SETCSR( mtval, writeval ); break;
						//case 0x3a0: break; //pmpcfg0
						//case 0x3B0: break; //pmpaddr0
						//case 0xf11: break; //mvendorid
						//case 0xf12: break; //marchid
						//case 0xf13: break; //mimpid
						//case 0xf14: break; //mhartid
						//case 0x301: break; //misa
						default:
							MINIRV32_OTHERCSR_WRITE( csrno, writeval );
							break;
						}
					}
					else if( microop == 0x0 ) // "SYSTEM" 0b000
					{
						rdid = 0;
						if( ( ( csrno & 0xff ) == 0x02 ) )  // MRET
						{
							//https://raw.githubusercontent.com/riscv/virtual-memory/main/specs/663-Svpbmt.pdf
							//Table 7.6. MRET then in mstatus/mstatush sets MPV=0, MPP=0, MIE=MPIE, and MPIE=1. La
							// Should also update mstatus to reflect correct mode.
							uint32_t startmstatus = CSR( mstatus );
							uint32_t startextraflags = CSR( extraflags );
							SETCSR( mstatus , (( startmstatus & 0x80) >> 4) | ((startextraflags&3) << 11) | 0x80 );
							SETCSR( extraflags, (startextraflags & ~3) | ((startmstatus >> 11) & 3) );
							pc = CSR( mepc ) -4;
						} else {
							switch (csrno) {
							case 0:
								trap = ( CSR( extraflags ) & 3) ? (11+1) : (8+1); // ECALL; 8 = "Environment call from U-mode"; 11 = "Environment call from M-mode"
								break;
							case 1:
								trap = (3+1); break; // EBREAK 3 = "Breakpoint"
							case 0x105: //WFI (Wait for interrupts)
								CSR( mstatus ) |= 8;    //Enable interrupts
								CSR( extraflags ) |= 4; //Infor environment we want to go to sleep.
								SETCSR( pc, pc + inst_len );
								return 1;
							default:
								trap = (2+1); break; // Illegal opcode.
							}
						}
					}
					else
						trap = (2+1); 				// Note micrrop 0b100 == undefined.
					break;
				}
				case 0x43: // FMADD.S (0b1000011)
				{
					uint32_t rs1 = (ir >> 15) & 0x1f;
					uint32_t rs2 = (ir >> 20) & 0x1f;
					uint32_t rs3 = (ir >> 27) & 0x1f;
					uint32_t rm = (ir >> 12) & 0x7;
					uint32_t fmt = (ir >> 25) & 0x3;
					uint32_t fmadd_bits = 0;
					if( !MINIRV32_HAS_F_EXTENSION() || fmt != 0x0 )
					{
						trap = (2+1);
						break;
					}
					if( !MINIRV32_FMADD_S( FREG( rs1 ), FREG( rs2 ), FREG( rs3 ), rm, fmadd_bits ) )
					{
						trap = (2+1);
						break;
					}
					FREGSET( rdid, fmadd_bits );
					rdid = 0;
					break;
				}
				case 0x47: // FMSUB.S (0b1000111)
				{
					uint32_t rs1 = (ir >> 15) & 0x1f;
					uint32_t rs2 = (ir >> 20) & 0x1f;
					uint32_t rs3 = (ir >> 27) & 0x1f;
					uint32_t rm = (ir >> 12) & 0x7;
					uint32_t fmt = (ir >> 25) & 0x3;
					uint32_t fmsub_bits = 0;
					if( !MINIRV32_HAS_F_EXTENSION() || fmt != 0x0 )
					{
						trap = (2+1);
						break;
					}
					if( !MINIRV32_FMSUB_S( FREG( rs1 ), FREG( rs2 ), FREG( rs3 ), rm, fmsub_bits ) )
					{
						trap = (2+1);
						break;
					}
					FREGSET( rdid, fmsub_bits );
					rdid = 0;
					break;
				}
				case 0x4b: // FNMSUB.S (0b1001011)
				{
					uint32_t rs1 = (ir >> 15) & 0x1f;
					uint32_t rs2 = (ir >> 20) & 0x1f;
					uint32_t rs3 = (ir >> 27) & 0x1f;
					uint32_t rm = (ir >> 12) & 0x7;
					uint32_t fmt = (ir >> 25) & 0x3;
					uint32_t fnmsub_bits = 0;
					if( !MINIRV32_HAS_F_EXTENSION() || fmt != 0x0 )
					{
						trap = (2+1);
						break;
					}
					if( !MINIRV32_FNMSUB_S( FREG( rs1 ), FREG( rs2 ), FREG( rs3 ), rm, fnmsub_bits ) )
					{
						trap = (2+1);
						break;
					}
					FREGSET( rdid, fnmsub_bits );
					rdid = 0;
					break;
				}
				case 0x4f: // FNMADD.S (0b1001111)
				{
					uint32_t rs1 = (ir >> 15) & 0x1f;
					uint32_t rs2 = (ir >> 20) & 0x1f;
					uint32_t rs3 = (ir >> 27) & 0x1f;
					uint32_t rm = (ir >> 12) & 0x7;
					uint32_t fmt = (ir >> 25) & 0x3;
					uint32_t fnmadd_bits = 0;
					if( !MINIRV32_HAS_F_EXTENSION() || fmt != 0x0 )
					{
						trap = (2+1);
						break;
					}
					if( !MINIRV32_FNMADD_S( FREG( rs1 ), FREG( rs2 ), FREG( rs3 ), rm, fnmadd_bits ) )
					{
						trap = (2+1);
						break;
					}
					FREGSET( rdid, fnmadd_bits );
					rdid = 0;
					break;
				}
				case 0x53: // OP-FP (0b1010011)
				{
					uint32_t funct7 = ir >> 25;
					uint32_t rs1 = (ir >> 15) & 0x1f;
					uint32_t rs2 = (ir >> 20) & 0x1f;
					uint32_t rm = (ir >> 12) & 0x7;
					if( !MINIRV32_HAS_F_EXTENSION() )
					{
						trap = (2+1);
						break;
					}
					switch( funct7 )
					{
						case 0x00: // FADD.S
						{
							uint32_t fadd_bits = 0;
							if( !MINIRV32_FADD_S( FREG( rs1 ), FREG( rs2 ), rm, fadd_bits ) )
							{
								trap = (2+1);
								break;
							}
							FREGSET( rdid, fadd_bits );
							rdid = 0;
							break;
						}
						case 0x04: // FSUB.S
						{
							uint32_t fsub_bits = 0;
							if( !MINIRV32_FSUB_S( FREG( rs1 ), FREG( rs2 ), rm, fsub_bits ) )
							{
								trap = (2+1);
								break;
							}
							FREGSET( rdid, fsub_bits );
							rdid = 0;
							break;
						}
						case 0x08: // FMUL.S
						{
							uint32_t fmul_bits = 0;
							if( !MINIRV32_FMUL_S( FREG( rs1 ), FREG( rs2 ), rm, fmul_bits ) )
							{
								trap = (2+1);
								break;
							}
							FREGSET( rdid, fmul_bits );
							rdid = 0;
							break;
						}
						case 0x0c: // FDIV.S
						{
							uint32_t fdiv_bits = 0;
							if( !MINIRV32_FDIV_S( FREG( rs1 ), FREG( rs2 ), rm, fdiv_bits ) )
							{
								trap = (2+1);
								break;
							}
							FREGSET( rdid, fdiv_bits );
							rdid = 0;
							break;
						}
						case 0x14: // FMIN.S / FMAX.S
						{
							uint32_t fminmax_bits = 0;
							switch( rm )
							{
								case 0x0:
									if( !MINIRV32_FMIN_S( FREG( rs1 ), FREG( rs2 ), fminmax_bits ) )
									{
										trap = (2+1);
										break;
									}
									break;
								case 0x1:
									if( !MINIRV32_FMAX_S( FREG( rs1 ), FREG( rs2 ), fminmax_bits ) )
									{
										trap = (2+1);
										break;
									}
									break;
								default:
									trap = (2+1);
									break;
							}
							if( trap ) break;
							FREGSET( rdid, fminmax_bits );
							rdid = 0;
							break;
						}
						case 0x2c: // FSQRT.S
						{
							uint32_t fsqrt_bits = 0;
							if( rs2 != 0x0 )
							{
								trap = (2+1);
								break;
							}
							if( !MINIRV32_FSQRT_S( FREG( rs1 ), rm, fsqrt_bits ) )
							{
								trap = (2+1);
								break;
							}
							FREGSET( rdid, fsqrt_bits );
							rdid = 0;
							break;
						}
						case 0x10: // FSGNJ.S / FSGNJN.S / FSGNJX.S
						{
							uint32_t fsgnj_bits = 0;
							switch( rm )
							{
								case 0x0:
									if( !MINIRV32_FSGNJ_S( FREG( rs1 ), FREG( rs2 ), fsgnj_bits ) )
									{
										trap = (2+1);
										break;
									}
									break;
								case 0x1:
									if( !MINIRV32_FSGNJN_S( FREG( rs1 ), FREG( rs2 ), fsgnj_bits ) )
									{
										trap = (2+1);
										break;
									}
									break;
								case 0x2:
									if( !MINIRV32_FSGNJX_S( FREG( rs1 ), FREG( rs2 ), fsgnj_bits ) )
									{
										trap = (2+1);
										break;
									}
									break;
								default:
									trap = (2+1);
									break;
							}
							if( trap ) break;
							FREGSET( rdid, fsgnj_bits );
							rdid = 0;
							break;
						}
						case 0x50: // FEQ.S / FLT.S / FLE.S
						{
							uint32_t fcmp_result = 0;
							switch( rm )
							{
								case 0x2:
									if( !MINIRV32_FEQ_S( FREG( rs1 ), FREG( rs2 ), fcmp_result ) )
									{
										trap = (2+1);
										break;
									}
									rval = fcmp_result;
									break;
								case 0x1:
									if( !MINIRV32_FLT_S( FREG( rs1 ), FREG( rs2 ), fcmp_result ) )
									{
										trap = (2+1);
										break;
									}
									rval = fcmp_result;
									break;
								case 0x0:
									if( !MINIRV32_FLE_S( FREG( rs1 ), FREG( rs2 ), fcmp_result ) )
									{
										trap = (2+1);
										break;
									}
									rval = fcmp_result;
									break;
								default:
									trap = (2+1);
									break;
							}
							break;
						}
						case 0x60: // FCVT.W.S / FCVT.WU.S
						{
							uint32_t fcvt_result = 0;
							if( rs2 == 0 )
							{
								if( !MINIRV32_FCVT_W_S( FREG( rs1 ), rm, fcvt_result ) )
								{
									trap = (2+1);
									break;
								}
							}
							else if( rs2 == 1 )
							{
								if( !MINIRV32_FCVT_WU_S( FREG( rs1 ), rm, fcvt_result ) )
								{
									trap = (2+1);
									break;
								}
							}
							else
							{
								trap = (2+1);
								break;
							}
							rval = fcvt_result;
							break;
						}
						case 0x68: // FCVT.S.W / FCVT.S.WU
						{
							uint32_t fcvt_bits = 0;
							if( rs2 == 0 )
							{
								if( !MINIRV32_FCVT_S_W( REG( rs1 ), rm, fcvt_bits ) )
								{
									trap = (2+1);
									break;
								}
							}
							else if( rs2 == 1 )
							{
								if( !MINIRV32_FCVT_S_WU( REG( rs1 ), rm, fcvt_bits ) )
								{
									trap = (2+1);
									break;
								}
							}
							else
							{
								trap = (2+1);
								break;
							}
							FREGSET( rdid, fcvt_bits );
							rdid = 0;
							break;
						}
						case 0x78: // FMV.W.X
							if( rs2 || rm )
							{
								trap = (2+1);
								break;
							}
							FREGSET( rdid, REG( rs1 ) );
							rdid = 0;
							break;
						case 0x70: // FMV.X.W
							if( !rs2 && rm == 0 )
							{
								rval = FREG( rs1 );
								break;
							}
							if( !rs2 && rm == 1 )
							{
								uint32_t fclass_bits = 0;
								if( !MINIRV32_FCLASS_S( FREG( rs1 ), fclass_bits ) )
								{
									trap = (2+1);
									break;
								}
								rval = fclass_bits;
								break;
							}
							if( rs2 || rm )
							{
								trap = (2+1);
								break;
							}
							rval = FREG( rs1 );
							break;
						default:
							trap = (2+1);
							break;
					}
					break;
				}
				case 0x2f: // RV32A (0b00101111)
				{
					uint32_t rs1 = REG((ir >> 15) & 0x1f);
					uint32_t rs2 = REG((ir >> 20) & 0x1f);
					uint32_t irmid = ( ir>>27 ) & 0x1f;

					rs1 -= MINIRV32_RAM_IMAGE_OFFSET;

					// We don't implement load/store from UART or CLNT with RV32A here.

					if( rs1 >= MINI_RV32_RAM_SIZE-3 )
					{
						trap = (7+1); //Store/AMO access fault
						rval = rs1 + MINIRV32_RAM_IMAGE_OFFSET;
					}
					else
					{
						rval = MINIRV32_LOAD4( rs1 );

						// Referenced a little bit of https://github.com/franzflasch/riscv_em/blob/master/src/core/core.c
						uint32_t dowrite = 1;
						switch( irmid )
						{
							case 2: //LR.W (0b00010)
								dowrite = 0;
								CSR( extraflags ) = (CSR( extraflags ) & 0x07) | (rs1<<3);
								break;
							case 3:  //SC.W (0b00011) (Make sure we have a slot, and, it's valid)
								rval = ( CSR( extraflags ) >> 3 != ( rs1 & 0x1fffffff ) );  // Validate that our reservation slot is OK.
								dowrite = !rval; // Only write if slot is valid.
								break;
							case 1: break; //AMOSWAP.W (0b00001)
							case 0: rs2 += rval; break; //AMOADD.W (0b00000)
							case 4: rs2 ^= rval; break; //AMOXOR.W (0b00100)
							case 12: rs2 &= rval; break; //AMOAND.W (0b01100)
							case 8: rs2 |= rval; break; //AMOOR.W (0b01000)
							case 16: rs2 = ((int32_t)rs2<(int32_t)rval)?rs2:rval; break; //AMOMIN.W (0b10000)
							case 20: rs2 = ((int32_t)rs2>(int32_t)rval)?rs2:rval; break; //AMOMAX.W (0b10100)
							case 24: rs2 = (rs2<rval)?rs2:rval; break; //AMOMINU.W (0b11000)
							case 28: rs2 = (rs2>rval)?rs2:rval; break; //AMOMAXU.W (0b11100)
							default: trap = (2+1); dowrite = 0; break; //Not supported.
						}
						if( dowrite ) MINIRV32_STORE4( rs1, rs2 );
					}
					break;
				}
				default: trap = (2+1); // Fault: Invalid opcode.
			}

			// If there was a trap, do NOT allow register writeback.
			if( trap ) {
				SETCSR( pc, pc );
				MINIRV32_POSTEXEC( pc, ir, trap );
				break;
			}

			if( rdid )
			{
				REGSET( rdid, rval ); // Write back register.
			}
		}

		MINIRV32_POSTEXEC( pc, ir, trap );

		pc += inst_len;
	}

	// Handle traps and interrupts.
	if( trap )
	{
		if( trap & 0x80000000 ) // If prefixed with 1 in MSB, it's an interrupt, not a trap.
		{
			SETCSR( mcause, trap );
			SETCSR( mtval, 0 );
			pc += inst_len; // PC needs to point to where the PC will return to.
		}
		else
		{
			SETCSR( mcause,  trap - 1 );
			SETCSR( mtval, (trap > 5 && trap <= 8)? rval : pc );
		}
		SETCSR( mepc, pc ); //TRICKY: The kernel advances mepc automatically.
		//CSR( mstatus ) & 8 = MIE, & 0x80 = MPIE
		// On an interrupt, the system moves current MIE into MPIE
		SETCSR( mstatus, (( CSR( mstatus ) & 0x08) << 4) | (( CSR( extraflags ) & 3 ) << 11) );
		pc = (CSR( mtvec ) - inst_len);

		// If trapping, always enter machine mode.
		CSR( extraflags ) |= 3;

		trap = 0;
		pc += inst_len;
	}

	if( CSR( cyclel ) > cycle ) CSR( cycleh )++;
	SETCSR( cyclel, cycle );
	SETCSR( pc, pc );
	return 0;
}

#endif

#endif
