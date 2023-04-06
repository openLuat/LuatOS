/*
 * MIT License
 *
 * Copyright (c) 2022 Dozingfiretruck
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */


#include "nes.h"

typedef struct {
    void (*instruction)(nes_t* nes);      //instructions 
    uint16_t (*addressing_mode)(nes_t* nes);  //addressing_mode
    uint8_t	ticks;
} nes_opcode_t;

static nes_opcode_t nes_opcode_table[256];

static inline uint8_t nes_read_joypad(nes_t* nes,uint16_t address){
    uint8_t state = 0;
    if (address == 0x4016){
        state = (nes->nes_cpu.joypad.joypad & (0x8000 >> (nes->nes_cpu.joypad.offset1 & nes->nes_cpu.joypad.mask))) ? 1 : 0;
        nes->nes_cpu.joypad.offset1++;
    }else if(address == 0x4017){
        state = (nes->nes_cpu.joypad.joypad & (0x80 >> (nes->nes_cpu.joypad.offset2 & nes->nes_cpu.joypad.mask))) ? 1 : 0;
        nes->nes_cpu.joypad.offset2++;
    }
    // nes_printf("nes_read joypad %04X %d %02X %d\n",address,nes->nes_cpu.joypad.mask,nes->nes_cpu.joypad.joypad,state);
    return state;
}

static inline void nes_write_joypad(nes_t* nes,uint8_t data){
    nes->nes_cpu.joypad.mask = (data & 1)?0x00:0x07;
    if (data & 1)
        nes->nes_cpu.joypad.offset1 = nes->nes_cpu.joypad.offset2 = 0;
    // nes_printf("nes_write joypad %04X %02X %d\n",address,data,nes->nes_cpu.joypad.mask);
}

static uint8_t nes_read_cpu(nes_t* nes,uint16_t address){
    switch (address >> 13){
        case 0://$0000-$1FFF 2KB internal RAM + Mirrors of $0000-$07FF
            return nes->nes_cpu.cpu_ram[address & (uint16_t)0x07ff];
        case 1://$2000-$3FFF NES PPU registers + Mirrors of $2000-2007 (repeats every 8 bytes)
            return nes_read_ppu_register(nes,address);
        case 2://$4000-$5FFF NES APU and I/O registers
            if (address == 0x4016 || address == 0x4017)
                return nes_read_joypad(nes, address);
            else if (address < 0x4016){
                return nes_read_apu_register(nes, address);
            }else
                nes_printf("nes_read address %04X not sPport\n",address);
            return 0;
        case 3://$6000-$7FFF SRAM
#if (NES_USE_SRAM == 1)
            return nes->nes_rom.sram[address & (uint16_t)0x1fff];
#endif
            return 0;
        case 4: case 5: case 6: case 7:
            return nes->nes_cpu.prg_banks[(address >> 13)-4][address & (uint16_t)0x1fff];
        default :
            nes_printf("nes_read_cpu error %04X\n",address);
            return -1;
    }
    return 0;
}

static inline const uint8_t* nes_get_dma_address(nes_t* nes,uint8_t data) {
    switch (data >> 5)
    {
    default:
    case 1:
        // PPU寄存器
        nes_printf("PPU REG!");
    case 2:
        // 扩展区
        nes_printf("TODO");
    case 0:
        // 系统内存
        return nes->nes_cpu.cpu_ram + ((uint16_t)(data & 0x07) << 8);
    // case 3:
    //     // 存档 SRAM区
    //     return famicom->save_ram + ((uint16_t)(data & 0x1f) << 8);
    case 4: case 5: case 6: case 7:
        // 高一位为1, [$8000, $10000) 程序PRG-ROM区
        return nes->nes_cpu.prg_banks[data >> 4] + ((uint16_t)(data & 0x0f) << 8);
    }
}

static void nes_write_cpu(nes_t* nes,uint16_t address, uint8_t data){
    switch (address >> 13){
        case 0://$0000-$1FFF 2KB internal RAM + Mirrors of $0000-$07FF
            nes->nes_cpu.cpu_ram[address & (uint16_t)0x07ff] = data;
            return;
        case 1://$2000-$3FFF NES PPU registers + Mirrors of $2000-2007 (repeats every 8 bytes)
            nes_write_ppu_register(nes,address, data);
            return;
        case 2://$4000-$5FFF NES APU and I/O registers
            if (address == 0x4016 || address == 0x4017)
                nes_write_joypad(nes,data);
            else if (address == 0x4014){
                // nes_printf("nes_write DMA %04X %02X\n",address,data);
                if (nes->nes_ppu.oam_addr) {
                    uint8_t* dst = nes->nes_ppu.oam_data;
                    const uint8_t len = nes->nes_ppu.oam_addr;
                    const uint8_t* src = nes_get_dma_address(nes,data);
                    memcpy(dst, src + len, len);
                    memcpy(dst + len, src, 256 - len);
                } else 
                    memcpy(nes->nes_ppu.oam_data, nes_get_dma_address(nes,data), 256);
                nes->nes_cpu.cycles += 513;
                nes->nes_cpu.cycles += nes->nes_cpu.cycles & 1;
            }else if (address < 0x4016){
                nes_write_apu_register(nes, address,data);
            }else
                nes_printf("nes_write address %04X not sPport\n",address);
            return;
        case 3://$6000-$7FFF SRAM
#if (NES_USE_SRAM == 1)
            nes->nes_rom.sram[address & (uint16_t)0x1fff] = data;
#endif
            return;
        case 4: case 5: case 6: case 7:
            nes->nes_mapper.mapper_write(nes, address, data);
            // nes->nes_cpu.prg_banks[(address >> 13)-4][address & (uint16_t)0x1fff] = data;
            return;
        default :
            nes_printf("nes_write_ppu_register error %04X %02X\n",address,data);
            return;
    }
}

#define NES_PUSH(nes,a)     nes_write_cpu(nes,0x100 + nes->nes_cpu.SP--,(a))
#define NES_PUSHW(nes,a)    NES_PUSH(nes, (a) >> 8 ); NES_PUSH(nes, (a) & 0xff)

#define NES_POP(nes)        nes_read_cpu(nes, 0x100 + ++(nes->nes_cpu.SP))

#define NES_CHECK_N(x)      nes->nes_cpu.N = ((uint8_t)(x) & 0x80)>>7
#define NES_CHECK_Z(x)      nes->nes_cpu.Z = ((uint8_t)(x) == 0)


/* Adressing modes */

//#Immediate
static uint16_t nes_imm(nes_t* nes){
    return nes->nes_cpu.PC++;
}

static uint16_t nes_rel(nes_t* nes){
    const uint8_t data = nes_read_cpu(nes,nes->nes_cpu.PC++);
    const uint16_t address = nes->nes_cpu.PC + (int8_t)data;
    return address;
}

//ABS
static uint16_t nes_abs(nes_t* nes){
    uint16_t address = nes_read_cpu(nes,nes->nes_cpu.PC)|(uint16_t)nes_read_cpu(nes,nes->nes_cpu.PC + 1) << 8;
    nes->nes_cpu.PC += 2;
    return address;
}

//ABX
static uint16_t nes_abx(nes_t* nes){
    uint16_t address = nes_read_cpu(nes,nes->nes_cpu.PC)|(uint16_t)nes_read_cpu(nes,nes->nes_cpu.PC + 1) << 8;
    nes->nes_cpu.PC += 2;
    if (nes_opcode_table[nes->nes_cpu.opcode].ticks==4){
        if ((address>>8) != ((address+nes->nes_cpu.X)>>8))nes->nes_cpu.cycles++;
    }
    return address + nes->nes_cpu.X;
}

//ABY
static uint16_t nes_aby(nes_t* nes){
    uint16_t address = nes_read_cpu(nes,nes->nes_cpu.PC)|(uint16_t)nes_read_cpu(nes,nes->nes_cpu.PC + 1) << 8;
    nes->nes_cpu.PC += 2;
    if (nes_opcode_table[nes->nes_cpu.opcode].ticks==4){
        if ((address>>8) != ((address+nes->nes_cpu.Y)>>8))nes->nes_cpu.cycles++;
    }
    return address + nes->nes_cpu.Y;
}

static uint16_t nes_zp(nes_t* nes){
    return (uint16_t)nes_read_cpu(nes,nes->nes_cpu.PC++);
}

static uint16_t nes_zpx(nes_t* nes){
    uint16_t address = (uint16_t)nes_read_cpu(nes,nes->nes_cpu.PC++) + nes->nes_cpu.X;
    return address & 0xFF;
}

static uint16_t nes_zpy(nes_t* nes){
    uint16_t address = nes_read_cpu(nes,nes->nes_cpu.PC++) + nes->nes_cpu.Y;
    return address & 0xFF;
}

static uint16_t nes_izx(nes_t* nes){
    uint8_t address = nes_read_cpu(nes,nes->nes_cpu.PC++);
    address += nes->nes_cpu.X;
    return nes_read_cpu(nes,address)|(uint16_t)nes_read_cpu(nes,(uint8_t)(address + 1)) << 8;
}

static uint16_t nes_izy(nes_t* nes){
    uint8_t value = nes_read_cpu(nes,nes->nes_cpu.PC++);
    uint16_t address = nes_read_cpu(nes,value)|(uint16_t)nes_read_cpu(nes,(uint8_t)(value + 1)) << 8;
    if (nes_opcode_table[nes->nes_cpu.opcode].ticks==5){
        if ((address>>8) != ((address+nes->nes_cpu.Y)>>8))nes->nes_cpu.cycles++;
    }
    return address + nes->nes_cpu.Y;
}

static uint16_t nes_ind(nes_t* nes){
    uint16_t value1 = nes_read_cpu(nes,nes->nes_cpu.PC)|(uint16_t)nes_read_cpu(nes,(nes->nes_cpu.PC + 1)) << 8;
    // 6502 BUG
    const uint16_t value2 = (value1 & (uint16_t)0xFF00)| ((value1 + 1) & (uint16_t)0x00FF);

    uint16_t address = nes_read_cpu(nes,value1)|(uint16_t)nes_read_cpu(nes,value2) << 8;
    nes->nes_cpu.PC+=2;
    return address;
}


/* Logical and arithmetic commands: */

/* 
    and accumulator A<--A&M NZ
    A := A & {adr}
    N  V  U  B  D  I  Z  C
    *                 *
*/
static void nes_and(nes_t* nes){
    nes->nes_cpu.A &= nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

/* 
    or accumulator A<--A|M NZ
    A :=A or {adr}
    N  V  U  B  D  I  Z  C
    *                 *
*/
static void nes_ora(nes_t* nes){
    nes->nes_cpu.A |= nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

/* 
    exclusive-or accumulator A<--A^M NZ
    A := A exor {adr}
    N  V  U  B  D  I  Z  C
    *                 *
*/
static void nes_eor(nes_t* nes){
    nes->nes_cpu.A ^= nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// A:=A+{adr}
// N  V  U  B  D  I  Z  C
// *  *              *  *
static void nes_adc(nes_t* nes){
    const uint8_t src = nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    const uint16_t result16 = nes->nes_cpu.A + src + nes->nes_cpu.C;
    if (result16 >> 8)nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;
    const uint8_t result8 = (uint8_t)result16;
    if (!((nes->nes_cpu.A ^ src) & 0x80) && ((nes->nes_cpu.A ^ result8) & 0x80)) nes->nes_cpu.V = 1;
    else nes->nes_cpu.V = 0;
    nes->nes_cpu.A = result8;
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// A:=A-{adr}

// EB
// SBC (SBC) [SBC]
// The same as the legal opcode $E9 (SBC #byte)
// Status flags: N,V,Z,C

// N  V  U  B  D  I  Z  C
// *  *              *  *
static void nes_sbc(nes_t* nes){
    const uint8_t src = nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    const uint16_t result16 = nes->nes_cpu.A - src - !nes->nes_cpu.C;
    if (!(result16 >> 8))nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;
    const uint8_t result8 = (uint8_t)result16;
    if (((nes->nes_cpu.A ^ src) & 0x80) && ((nes->nes_cpu.A ^ result8) & 0x80)) nes->nes_cpu.V = 1;
    else nes->nes_cpu.V = 0;
    nes->nes_cpu.A = result8;
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// A-{adr}
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_cmp(nes_t* nes){
    const uint16_t value = (uint16_t)nes->nes_cpu.A - (uint16_t)nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    if (!(value & 0x8000))nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;
    NES_CHECK_N((uint8_t)value);
    NES_CHECK_Z((uint8_t)value);
}

// X-{adr}
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_cpx(nes_t* nes){
    const uint16_t value = (uint16_t)nes->nes_cpu.X - (uint16_t)nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    if (!(value & 0x8000))nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;
    NES_CHECK_N((uint8_t)value);
    NES_CHECK_Z((uint8_t)value);
}

// Y-{adr}
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_cpy(nes_t* nes){
    const uint16_t value = (uint16_t)nes->nes_cpu.Y - (uint16_t)nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    if (!(value & 0x8000))nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;
    NES_CHECK_N((uint8_t)value);
    NES_CHECK_Z((uint8_t)value);
}

// {adr}:={adr}-1
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_dec(nes_t* nes){
    uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    uint8_t data = nes_read_cpu(nes,address);
    data--;
    nes_write_cpu(nes,address, data);
    NES_CHECK_N(data);
    NES_CHECK_Z(data);
}

// X:=X-1
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_dex(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    NES_CHECK_N(--nes->nes_cpu.X);
    NES_CHECK_Z(nes->nes_cpu.X);
}

// Y:=Y-1
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_dey(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    NES_CHECK_N(--nes->nes_cpu.Y);
    NES_CHECK_Z(nes->nes_cpu.Y);
}

// {adr}:={adr}+1
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_inc(nes_t* nes){
    uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    uint8_t data = nes_read_cpu(nes,address);
    nes_write_cpu(nes,address,++data);
    NES_CHECK_N(data);
    NES_CHECK_Z(data);
}

// X:=X+1
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_inx(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    NES_CHECK_N(++nes->nes_cpu.X);
    NES_CHECK_Z(nes->nes_cpu.X);
}

// Y:=Y+1
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_iny(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    NES_CHECK_N(++nes->nes_cpu.Y);
    NES_CHECK_Z(nes->nes_cpu.Y);
}

// {adr}:={adr}*2
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_asl(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode){
        uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
        uint8_t value = nes_read_cpu(nes,address);
        if (value & 0x80)nes->nes_cpu.C = 1;
        else nes->nes_cpu.C = 0;
        value <<= 1;
        nes_write_cpu(nes,address,value);
        NES_CHECK_N(value);
        NES_CHECK_Z(value);
    }else{
        if (nes->nes_cpu.A&0x80)nes->nes_cpu.C = 1;
        else nes->nes_cpu.C = 0;
        nes->nes_cpu.A <<= 1;
        NES_CHECK_N(nes->nes_cpu.A);
        NES_CHECK_Z(nes->nes_cpu.A);
    }
}

// {adr}:={adr}*2+C
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_rol(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode){
        uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
        uint8_t saveflags=nes->nes_cpu.C;
        uint8_t value = nes_read_cpu(nes,address);
        nes->nes_cpu.P= (nes->nes_cpu.P & 0xfe) | ((value>>7) & 0x01);
        value <<= 1;
        value |= saveflags;
        nes_write_cpu(nes,address,value);
        NES_CHECK_N(value);
        NES_CHECK_Z(value);
    }else{
        uint8_t saveflags=nes->nes_cpu.C;
        nes->nes_cpu.P= (nes->nes_cpu.P & 0xfe) | ((nes->nes_cpu.A>>7) & 0x01);
        nes->nes_cpu.A <<= 1;
        nes->nes_cpu.A |= saveflags;
        NES_CHECK_N(nes->nes_cpu.A);
        NES_CHECK_Z(nes->nes_cpu.A);
    }
}

// {adr}:={adr}/2
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_lsr(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode){
        uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
        uint8_t value = nes_read_cpu(nes,address);
        if (value & 1)nes->nes_cpu.C = 1;
        else nes->nes_cpu.C = 0;
        value >>= 1;
        nes_write_cpu(nes,address,value);
        NES_CHECK_N(value);
        NES_CHECK_Z(value);
    }else{
        if (nes->nes_cpu.A & 1)nes->nes_cpu.C = 1;
        else nes->nes_cpu.C = 0;
        nes->nes_cpu.A >>= 1;
        NES_CHECK_N(nes->nes_cpu.A);
        NES_CHECK_Z(nes->nes_cpu.A);
    }
}

// {adr}:={adr}/2+C*128
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_ror(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) {
        uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
        uint8_t saveflags=nes->nes_cpu.C;
        uint8_t value = nes_read_cpu(nes,address);
        nes->nes_cpu.P= (nes->nes_cpu.P & 0xfe) | (value & 0x01);
        value >>= 1;
        if (saveflags) value |= 0x80;
        nes_write_cpu(nes,address,value);
        NES_CHECK_N(value);
        NES_CHECK_Z(value);  
    }else{
        uint8_t saveflags=nes->nes_cpu.C;
        nes->nes_cpu.P= (nes->nes_cpu.P & 0xfe) | (nes->nes_cpu.A & 0x01);
        nes->nes_cpu.A >>= 1;
        if (saveflags) nes->nes_cpu.A |= 0x80;
        NES_CHECK_N(nes->nes_cpu.A);
        NES_CHECK_Z(nes->nes_cpu.A);
    }
}

/* Move commands: */

// A:={adr}
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_lda(nes_t* nes){
    nes->nes_cpu.A = nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// {adr}:=A
static void nes_sta(nes_t* nes){
    nes_write_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes),nes->nes_cpu.A);
}

// X:={adr}
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_ldx(nes_t* nes){
    nes->nes_cpu.X = nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    NES_CHECK_N(nes->nes_cpu.X);
    NES_CHECK_Z(nes->nes_cpu.X);
}

// {adr}:=X
static void nes_stx(nes_t* nes){
    nes_write_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes),nes->nes_cpu.X);
}

// Y:={adr}
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_ldy(nes_t* nes){
    nes->nes_cpu.Y = nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    NES_CHECK_N(nes->nes_cpu.Y);
    NES_CHECK_Z(nes->nes_cpu.Y);
}

// {adr}:=Y
static void nes_sty(nes_t* nes){
    nes_write_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes),nes->nes_cpu.Y);
}

// X:=A
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_tax(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.X=nes->nes_cpu.A;
    NES_CHECK_N(nes->nes_cpu.X);
    NES_CHECK_Z(nes->nes_cpu.X);
}

// A:=X
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_txa(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.A=nes->nes_cpu.X;
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// Y:=A
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_tay(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.Y=nes->nes_cpu.A;
    NES_CHECK_N(nes->nes_cpu.Y);
    NES_CHECK_Z(nes->nes_cpu.Y);
}

// A:=Y
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_tya(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.A=nes->nes_cpu.Y;
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// X:=S
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_tsx(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.X=nes->nes_cpu.SP;
    NES_CHECK_N(nes->nes_cpu.X);
    NES_CHECK_Z(nes->nes_cpu.X);
}

// S:=X
static void nes_txs(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.SP=nes->nes_cpu.X;
}

// A:=+(S)
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_pla(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.A = NES_POP(nes);
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// (S)-:=A
static void nes_pha(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    NES_PUSH(nes,nes->nes_cpu.A);
}

// P:=+(S)
// N  V  U  B  D  I  Z  C
// *  *        *  *  *  *
static void nes_plp(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.P = NES_POP(nes);
    // nes->nes_cpu.B=0;
}

// (S)-:=P
static void nes_php(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    NES_PUSH(nes,nes->nes_cpu.P);
}

// Jump/Flag commands:
static inline void nes_branch(nes_t* nes) {
    const uint16_t pc_old = nes->nes_cpu.PC;
    nes->nes_cpu.PC = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.cycles++;
    nes->nes_cpu.cycles += (nes->nes_cpu.PC ^ pc_old) >> 8 & 1;
}

// branch on N=0
static void nes_bpl(nes_t* nes){
    if (nes->nes_cpu.N==0){
        nes_branch(nes);
    } else nes->nes_cpu.PC++;
}

// branch on N=1
static void nes_bmi(nes_t* nes){
    if (nes->nes_cpu.N){
        nes_branch(nes);
    } else nes->nes_cpu.PC++;
}

// branch on V=0
static void nes_bvc(nes_t* nes){
    if (nes->nes_cpu.V==0){
        nes_branch(nes);
    } else nes->nes_cpu.PC++;
}

// branch on V=1
static void nes_bvs(nes_t* nes){
    if (nes->nes_cpu.V){
        nes_branch(nes);
    } else nes->nes_cpu.PC++;
}

// branch on C=0
static void nes_bcc(nes_t* nes){
    if (nes->nes_cpu.C==0){
        nes_branch(nes);
    } else nes->nes_cpu.PC++;
}

// branch on C=1
static void nes_bcs(nes_t* nes){
    if (nes->nes_cpu.C){
        nes_branch(nes);
    } else nes->nes_cpu.PC++;
}

// branch on Z=0
static void nes_bne(nes_t* nes){
    if (nes->nes_cpu.Z==0){
        nes_branch(nes);
    } else nes->nes_cpu.PC++;
}

// branch on Z=1
static void nes_beq(nes_t* nes){
    if (nes->nes_cpu.Z){
        nes_branch(nes);
    } else nes->nes_cpu.PC++;
}

// (S)-:=PC,P PC:=($FFFE)
// N  V  U  B  D  I  Z  C
//          1     1
static void nes_brk(nes_t* nes){
    nes->nes_cpu.PC ++;
    if (nes->nes_cpu.I==0){
        NES_PUSHW(nes,nes->nes_cpu.PC-1);
        NES_PUSH(nes,nes->nes_cpu.P);
        // nes->nes_cpu.B = 1;
        nes->nes_cpu.I = 1;
        nes->nes_cpu.PC = nes_read_cpu(nes,NES_VERCTOR_IRQBRK)|(uint16_t)nes_read_cpu(nes,NES_VERCTOR_IRQBRK + 1) << 8;
    }
}

// P,PC:=+(S)
// N  V  U  B  D  I  Z  C
// *  *        *  *  *  *
static void nes_rti(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.P = NES_POP(nes);
    nes->nes_cpu.U = 1;
    nes->nes_cpu.B = 0;
    nes->nes_cpu.PC = (uint16_t)NES_POP(nes);
    nes->nes_cpu.PC |= (uint16_t)NES_POP(nes) << 8;
}

// (S)-:=PC PC:={adr}
static void nes_jsr(nes_t* nes){
    uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    NES_PUSHW(nes,nes->nes_cpu.PC-1);
    nes->nes_cpu.PC = address;
}

// PC:=+(S)
static void nes_rts(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.PC = (uint16_t)NES_POP(nes);
    nes->nes_cpu.PC |= (uint16_t)NES_POP(nes) << 8;
    nes->nes_cpu.PC++;
}

// PC:={adr}
static void nes_jmp(nes_t* nes){
    nes->nes_cpu.PC=nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// N:=b7 V:=b6 Z:=A&{adr}
// N  V  U  B  D  I  Z  C
// *  *              *  
static void nes_bit(nes_t* nes){
    const uint8_t value = nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    NES_CHECK_Z(value & nes->nes_cpu.A);
    if (value & (uint8_t)(1 << 6)) nes->nes_cpu.V = 1;
    else nes->nes_cpu.V = 0;
    NES_CHECK_N(value);
}

// C:=0
// N  V  U  B  D  I  Z  C
//                      0
static void nes_clc(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.C=0;
}

// C:=1
// N  V  U  B  D  I  Z  C
//                      1
static void nes_sec(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.C=1;
}

// D:=0
// N  V  U  B  D  I  Z  C
//             0         
static void nes_cld(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.D=0;
}

// D:=1
// N  V  U  B  D  I  Z  C
//             1         
static void nes_sed(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.D=1;
}

// I:=0
// N  V  U  B  D  I  Z  C
//                0      
static void nes_cli(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.I=0;
}

// I:=1
// N  V  U  B  D  I  Z  C
//                1      
static void nes_sei(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.I=1;
}

// V:=0
// N  V  U  B  D  I  Z  C
//    0                  
static void nes_clv(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    nes->nes_cpu.V=0;
}

// DOP (NOP) [SKB] TOP (NOP) [SKW]
// No operation . The argument has no signifi-cance. Status
// flags: -
static void nes_nop(nes_t* nes){
    if (nes_opcode_table[nes->nes_cpu.opcode].addressing_mode) nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}


// Illegal opcodes:

// {adr}:={adr}*2 A:=A or {adr}	
// SLO (SLO) [ASO]
// Shift left one bit in memory, then OR accumulator with memory. =
// Status flags: N,Z,C
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_slo(nes_t* nes){
    uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    uint8_t data = nes_read_cpu(nes,address);
    if (data & 0x80)nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;
    data <<= 1;
    nes_write_cpu(nes,address,data);

    nes->nes_cpu.A |= data;
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// {adr}:={adr}rol A:=A and {adr}
// RLA (RLA) [RLA]
// Rotate one bit left in memory, then AND accumulator with memory. Status
// flags: N,Z,C
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_rla(nes_t* nes){
    uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    uint8_t saveflags=nes->nes_cpu.C;
    uint8_t value = nes_read_cpu(nes,address);
    nes->nes_cpu.P= (nes->nes_cpu.P & 0xfe) | ((value>>7) & 0x01);
    value <<= 1;
    value |= saveflags;
    nes_write_cpu(nes,address,value);

    nes->nes_cpu.A &= value;
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// {adr}:={adr}/2 A:=A exor {adr}
// SRE (SRE) [LSE]
// Shift right one bit in memory, then EOR accumulator with memory. Status
// flags: N,Z,C
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_sre(nes_t* nes){
    uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    uint8_t data = nes_read_cpu(nes,address);
    if (data & 1)nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;
    data >>= 1;
    nes_write_cpu(nes,address,data);

    nes->nes_cpu.A ^= data;
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// {adr}:={adr}ror A:=A adc {adr}
// RRA (RRA) [RRA]
// Rotate one bit right in memory, then add memory to accumulator (with
// carry).
// Status flags: N,V,Z,C
// N  V  U  B  D  I  Z  C
// *  *              *  *
static void nes_rra(nes_t* nes){
    uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    uint8_t saveflags=nes->nes_cpu.C;
    uint8_t value = nes_read_cpu(nes,address);
    nes->nes_cpu.P= (nes->nes_cpu.P & 0xfe) | (value & 0x01);
    value >>= 1;
    if (saveflags) value |= 0x80;
    nes_write_cpu(nes,address,value);

    const uint16_t result16 = nes->nes_cpu.A + value + nes->nes_cpu.C;
    if (result16 >> 8)nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;
    const uint8_t result8 = (uint8_t)result16;
    if (!((nes->nes_cpu.A ^ value) & 0x80) && ((nes->nes_cpu.A ^ result8) & 0x80)) nes->nes_cpu.V = 1;
    else nes->nes_cpu.V = 0;
    nes->nes_cpu.A = result8;
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// {adr}:=A&X
// AAX (SAX) [AXS]
// AND X register with accumulator and store result in memory. Status
// flags: N,Z

static void nes_sax(nes_t* nes){
    nes_write_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes),nes->nes_cpu.A & nes->nes_cpu.X);
}

// A,X:={adr}

// AB
// ATX (LXA) [OAL]
// AND byte with accumulator, then transfer accumulator to X register.
// Status flags: N,Z

// A7
// LAX (LAX) [LAX]
// Load accumulator and X register with memory.
// Status flags: N,Z
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_lax(nes_t* nes){
    nes->nes_cpu.A = nes_read_cpu(nes,nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes));
    nes->nes_cpu.X = nes->nes_cpu.A;
    NES_CHECK_N(nes->nes_cpu.A);
    NES_CHECK_Z(nes->nes_cpu.A);
}

// {adr}:={adr}-1 A-{adr}
// DCP (DCP) [DCM]
// Subtract 1 from memory (without borrow).
// Status flags: C
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_dcp(nes_t* nes){
    uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    uint8_t data = nes_read_cpu(nes,address);
    data--;
    nes_write_cpu(nes,address,data);
    const uint16_t result16 = (uint16_t)nes->nes_cpu.A - (uint16_t)data;

    if (!(result16 & (uint16_t)0x8000))nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;

    NES_CHECK_N((uint8_t)result16);
    NES_CHECK_Z((uint8_t)result16);
}

// {adr}:={adr}+1 A:=A-{adr}
// ISC (ISB) [INS]
// Increase memory by one, then subtract memory from accu-mulator (with
// borrow). Status flags: N,V,Z,C
// N  V  U  B  D  I  Z  C
// *  *              *  *
static void nes_isc(nes_t* nes){
    uint16_t address = nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
    uint8_t data = nes_read_cpu(nes,address);
    data++;
    nes_write_cpu(nes,address,data);

    const uint16_t result16 = nes->nes_cpu.A - data - !nes->nes_cpu.C;
    if (!(result16 >> 8))nes->nes_cpu.C = 1;
    else nes->nes_cpu.C = 0;
    const uint8_t result8 = (uint8_t)result16;
    if (((nes->nes_cpu.A ^ data) & 0x80) && ((nes->nes_cpu.A ^ result8) & 0x80)) nes->nes_cpu.V = 1;
    else nes->nes_cpu.V = 0;
    nes->nes_cpu.A = result8;
    NES_CHECK_Z(nes->nes_cpu.A);
    NES_CHECK_N(nes->nes_cpu.A);
}

// A:=A&#{imm}
// AAC (ANC) [ANC]
// AND byte with accumulator. If result is negative then carry is set.
// Status flags: N,Z,C
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_anc(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// A:=(A&#{imm})/2
// ASR (ASR) [ALR]
// AND byte with accumulator, then shift right one bit in accumu-lator.
// Status flags: N,Z,C
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_alr(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// A:=(A&#{imm})/2
// ARR (ARR) [ARR]
// AND byte with accumulator, then rotate one bit right in accu-mulator and
// check bit 5 and 6:
// If both bits are 1: set C, clear V.
// If both bits are 0: clear C and V.
// If only bit 5 is 1: set V, clear C.
// If only bit 6 is 1: set C and V.
// Status flags: N,V,Z,C
// alr
// N  V  U  B  D  I  Z  C
// *                 *  *
// arr
// N  V  U  B  D  I  Z  C
// *  *              *  *
static void nes_arr(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// A:=X&#{imm}
// XAA (ANE) [XAA]
// Exact operation unknown. Read the referenced documents for more
// information and observations.
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_xaa(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// X:=A&X-#{imm}
// AXS (SBX) [SAX]
// AND X register with accumulator and store result in X regis-ter, then
// subtract byte from X register (without borrow).
// Status flags: N,Z,C
// N  V  U  B  D  I  Z  C
// *                 *  *
static void nes_axs(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}


// {adr}:=A&X&H
// AXA (SHA) [AXA]
// AND X register with accumulator then AND result with 7 and store in
// memory. Status flags: -
static void nes_ahx(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// {adr}:=Y&H
// SYA (SHY) [SAY]
// AND Y register with the high byte of the target address of the argument
// + 1. Store the result in memory.
// M =3D Y AND HIGH(arg) + 1
// Status flags: -
static void nes_shy(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// {adr}:=X&H
// SXA (SHX) [XAS]
// AND X register with the high byte of the target address of the argument
// + 1. Store the result in memory.
// M =3D X AND HIGH(arg) + 1
// Status flags: -
static void nes_shx(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// S:=A&X {adr}:=S&H
// XAS (SHS) [TAS]
// AND X register with accumulator and store result in stack pointer, then
// AND stack pointer with the high byte of the target address of the
// argument + 1. Store result in memory.
// S =3D X AND A, M =3D S AND HIGH(arg) + 1
// Status flags: -
static void nes_tas(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// A,X,S:={adr}&S
// LAR (LAE) [LAS]
// AND memory with stack pointer, transfer result to accu-mulator, X
// register and stack pointer.
// Status flags: N,Z
// N  V  U  B  D  I  Z  C
// *                 *  
static void nes_las(nes_t* nes){
    nes_opcode_table[nes->nes_cpu.opcode].addressing_mode(nes);
}

// KIL (JAM) [HLT]
// Stop program counter (processor lock P).
// Status flags: -

void nes_nmi(nes_t* nes){
    NES_PUSHW(nes,nes->nes_cpu.PC);
    NES_PUSH(nes,nes->nes_cpu.P);
    nes->nes_cpu.I = 1;
    nes->nes_cpu.PC = nes_read_cpu(nes,NES_VERCTOR_NMI)|(uint16_t)nes_read_cpu(nes,NES_VERCTOR_NMI + 1) << 8;
    nes->nes_cpu.cycles += 7;
}

void nes_cpu_reset(nes_t* nes){
    nes->nes_cpu.A = nes->nes_cpu.X = nes->nes_cpu.Y = nes->nes_cpu.P = 0;
    nes->nes_cpu.U = 1;
    // nes->nes_cpu.B = 1;
    
    nes->nes_cpu.P = 0x34;

    nes->nes_cpu.SP = 0xFD;
    nes->nes_cpu.PC = nes_read_cpu(nes,NES_VERCTOR_RESET)|(uint16_t)nes_read_cpu(nes,NES_VERCTOR_RESET + 1) << 8;
    nes->nes_cpu.cycles = 7;
}

void nes_cpu_init(nes_t* nes){

}

static nes_opcode_t nes_opcode_table[] = {
    {nes_brk,	NULL,	    7   },      // 0x00     BRK             7
    {nes_ora,   nes_izx,    6   },      // 0x01     ORA     izx     6
    {NULL,	    NULL,	    0   },      // 0x02     KIL
    {nes_slo,	nes_izx,	8   },      // 0x03     SLO     izx     8
    {nes_nop,	nes_zp,	    3   },      // 0x04     NOP     zp      3
    {nes_ora,	nes_zp,	    3   },      // 0x05     ORA     zp      3
    {nes_asl,	nes_zp,	    5   },      // 0x06     ASL     zp      5
    {nes_slo,	nes_zp,	    5   },      // 0x07     SLO     zp      5
    {nes_php,	NULL,	    3   },      // 0x08     PHP             3
    {nes_ora,	nes_imm,	2   },      // 0x09     ORA     imm     2
    {nes_asl,	NULL,	    2   },      // 0x0A     ASL             2
    {nes_anc,	nes_imm,	2   },      // 0x0B     ANC     imm     2
    {nes_nop,	nes_abs,	4   },      // 0x0C     NOP     abs     4
    {nes_ora,	nes_abs,	4   },      // 0x0D     ORA     abs     4
    {nes_asl,	nes_abs,	6   },      // 0x0E     ASL     abs     6
    {nes_slo,	nes_abs,	6   },      // 0x0F     SLO     abs     6
    {nes_bpl,	nes_rel,	2   },      // 0x10     BPL     rel     2*
    {nes_ora,   nes_izy,    5   },      // 0x11     ORA     izy     5*
    {NULL,      NULL,	    0   },      // 0x12     KIL
    {nes_slo,	nes_izy,	8   },      // 0x13     SLO     izy     8
    {nes_nop,	nes_zpx,	4   },      // 0x14     NOP     zpx     4
    {nes_ora,	nes_zpx,	4   },      // 0x15     ORA     zpx     4
    {nes_asl,	nes_zpx,	6   },      // 0x16     ASL     zpx     6
    {nes_slo,	nes_zpx,	6   },      // 0x17     SLO     zpx     6
    {nes_clc,	NULL,	    2   },      // 0x18     CLC             2
    {nes_ora,	nes_aby,	4   },      // 0x19     ORA     aby     4*
    {nes_nop,	NULL,	    2   },      // 0x1A     NOP             2
    {nes_slo,	nes_aby,	7   },      // 0x1B     SLO     aby     7
    {nes_nop,	nes_abx,	4   },      // 0x1C     NOP     abx     4*
    {nes_ora,	nes_abx,	4   },      // 0x1D     ORA     abx     4*
    {nes_asl,	nes_abx,	7   },      // 0x1E     ASL     abx     7
    {nes_slo,	nes_abx,	7   },      // 0x1F     SLO     abx     7
    {nes_jsr,	nes_abs,	6   },      // 0x20     JSR     abs     6
    {nes_and,   nes_izx,    6   },      // 0x21     AND     izx     6
    {NULL,      NULL,	    0   },      // 0x22     KIL
    {nes_rla,	nes_izx,	8   },      // 0x23     RLA     izx     8
    {nes_bit,	nes_zp,	    3   },      // 0x24     BIT     zp      3
    {nes_and,	nes_zp,     3   },      // 0x25     AND     zp      3
    {nes_rol,	nes_zp,     5   },      // 0x26     ROL     zp      5
    {nes_rla,	nes_zp,     5   },      // 0x27     RLA     zp      5
    {nes_plp,	NULL,	    4   },      // 0x28     PLP             4
    {nes_and,	nes_imm,	2   },      // 0x29     AND     imm     2
    {nes_rol,	NULL,	    2   },      // 0x2A     ROL             2
    {nes_anc,	nes_imm,	2   },      // 0x2B     ANC     imm     2
    {nes_bit,	nes_abs,	4   },      // 0x2C     BIT     abs     4
    {nes_and,	nes_abs,	4   },      // 0x2D     AND     abs     4
    {nes_rol,	nes_abs,	6   },      // 0x2E     ROL     abs     6
    {nes_rla,	nes_abs,	6   },      // 0x2F     RLA     abs     6
    {nes_bmi,	nes_rel,	2   },      // 0x30     BMI     rel     2*
    {nes_and,   nes_izy,    5   },      // 0x31     AND     izy     5*
    {NULL,      NULL,	    0   },      // 0x32     KIL
    {nes_rla,	nes_izy,	8   },      // 0x33     RLA     izy     8
    {nes_nop,	nes_zpx,	4   },      // 0x34     NOP     zpx     4
    {nes_and,	nes_zpx,    4   },      // 0x35     AND     zpx     4
    {nes_rol,	nes_zpx,    6   },      // 0x36     ROL     zpx     6
    {nes_rla,	nes_zpx,    6   },      // 0x37     RLA     zpx     6
    {nes_sec,	NULL,	    2   },      // 0x38     SEC             2
    {nes_and,	nes_aby,	4   },      // 0x39     AND     aby     4*
    {nes_nop,	NULL,	    2   },      // 0x3A     NOP             2
    {nes_rla,	nes_aby,	7   },      // 0x3B     RLA     aby     7
    {nes_nop,	nes_abx,	4   },      // 0x3C     NOP     abx     4*
    {nes_and,	nes_abx,	4   },      // 0x3D     AND     abx     4*
    {nes_rol,	nes_abx,	7   },      // 0x3E     ROL     abx     7
    {nes_rla,	nes_abx,	7   },      // 0x3F     RLA     abx     7
    {nes_rti,	NULL,	    6   },      // 0x40     RTI             6
    {nes_eor,   nes_izx,    6   },      // 0x41     EOR     izx     6
    {NULL,      NULL,	    0   },      // 0x42     KIL
    {nes_sre,	nes_izx,	8   },      // 0x43     SRE     izx     8
    {nes_nop,	nes_zp,	    3   },      // 0x44     NOP     zp      3
    {nes_eor,	nes_zp,     3   },      // 0x45     EOR     zp      3
    {nes_lsr,	nes_zp,     5   },      // 0x46     LSR     zp      5
    {nes_sre,	nes_zp,     5   },      // 0x47     SRE     zp      5
    {nes_pha,	NULL,	    3   },      // 0x48     PHA             3
    {nes_eor,	nes_imm,	2   },      // 0x49     EOR     imm     2
    {nes_lsr,	NULL,	    2   },      // 0x4A     LSR             2
    {nes_alr,	nes_imm,	2   },      // 0x4B     ALR     imm     2
    {nes_jmp,	nes_abs,	3   },      // 0x4C     JMP     abs     3
    {nes_eor,	nes_abs,	4   },      // 0x4D     EOR     abs     4
    {nes_lsr,	nes_abs,	6   },      // 0x4E     LSR     abs     6
    {nes_sre,	nes_abs,	6   },      // 0x4F     SRE     abs     6
    {nes_bvc,	nes_rel,	2   },      // 0x50     BVC     rel     2*
    {nes_eor,   nes_izy,    5   },      // 0x51     EOR     izy     5*
    {NULL,      NULL,	    0   },      // 0x52     KIL
    {nes_sre,	nes_izy,	8   },      // 0x53     SRE     izy     8
    {nes_nop,	nes_zpx,	4   },      // 0x54     NOP     zpx     4
    {nes_eor,	nes_zpx,    4   },      // 0x55     EOR     zpx     4
    {nes_lsr,	nes_zpx,    6   },      // 0x56     LSR     zpx     6
    {nes_sre,	nes_zpx,    6   },      // 0x57     SRE     zpx     6
    {nes_cli,	NULL,	    2   },      // 0x58     CLI             2
    {nes_eor,	nes_aby,	4   },      // 0x59     EOR     aby     4*
    {nes_nop,	NULL,	    2   },      // 0x5A     NOP             2
    {nes_sre,	nes_aby,	7   },      // 0x5B     SRE     aby     7
    {nes_nop,	nes_abx,	4   },      // 0x5C     NOP     abx     4*
    {nes_eor,	nes_abx,	4   },      // 0x5D     EOR     abx     4*
    {nes_lsr,	nes_abx,	7   },      // 0x5E     LSR     abx     7
    {nes_sre,	nes_abx,	7   },      // 0x5F     SRE     abx     7
    {nes_rts,	NULL,   	6   },      // 0x60     RTS             6
    {nes_adc,   nes_izx,    6   },      // 0x61     ADC     izx     6
    {NULL,      NULL,	    0   },      // 0x62     KIL
    {nes_rra,	nes_izx,	8   },      // 0x63     RRA     izx     8
    {nes_nop,	nes_zp,	    3   },      // 0x64     NOP     zp      3
    {nes_adc,	nes_zp,     3   },      // 0x65     ADC     zp      3
    {nes_ror,	nes_zp,     5   },      // 0x66     ROR     zp      5
    {nes_rra,	nes_zp,     5   },      // 0x67     RRA     zp      5
    {nes_pla,	NULL,	    4   },      // 0x68     PLA             4
    {nes_adc,	nes_imm,	2   },      // 0x69     ADC     imm     2
    {nes_ror,	NULL,	    2   },      // 0x6A     ROR             2
    {nes_arr,	nes_imm,	2   },      // 0x6B     ARR     imm     2
    {nes_jmp,	nes_ind,	5   },      // 0x6C     JMP     ind     5
    {nes_adc,	nes_abs,	4   },      // 0x6D     ADC     abs     4
    {nes_ror,	nes_abs,	6   },      // 0x6E     ROR     abs     6
    {nes_rra,	nes_abs,	6   },      // 0x6F     RRA     abs     6
    {nes_bvs,	nes_rel,   	2   },      // 0x70     BVS     rel     2*
    {nes_adc,   nes_izy,    5   },      // 0x71     ADC     izy     5*
    {NULL,      NULL,	    0   },      // 0x72     KIL
    {nes_rra,	nes_izy,	8   },      // 0x73     RRA     izy     8
    {nes_nop,	nes_zpx,	4   },      // 0x74     NOP     zpx     4
    {nes_adc,	nes_zpx,    4   },      // 0x75     ADC     zpx     4
    {nes_ror,	nes_zpx,    6   },      // 0x76     ROR     zpx     6
    {nes_rra,	nes_zpx,    6   },      // 0x77     RRA     zpx     6
    {nes_sei,	NULL,	    2   },      // 0x78     SEI             2
    {nes_adc,	nes_aby,	4   },      // 0x79     ADC     aby     4*
    {nes_nop,	NULL,	    2   },      // 0x7A     NOP             2
    {nes_rra,	nes_aby,	7   },      // 0x7B     RRA     aby     7
    {nes_nop,	nes_abx,	4   },      // 0x7C     NOP     abx     4*
    {nes_adc,	nes_abx,	4   },      // 0x7D     ADC     abx     4*
    {nes_ror,	nes_abx,	7   },      // 0x7E     ROR     abx     7
    {nes_rra,	nes_abx,	7   },      // 0x7F     RRA     abx     7
    {nes_nop,	nes_imm,   	2   },      // 0x80     NOP     imm     2
    {nes_sta,   nes_izx,    6   },      // 0x81     STA     izx     6
    {nes_nop,   nes_imm,	2   },      // 0x82     NOP     imm     2
    {nes_sax,	nes_izx,	6   },      // 0x83     SAX     izx     6
    {nes_sty,	nes_zp,	    3   },      // 0x84     STY     zp      3
    {nes_sta,	nes_zp,     3   },      // 0x85     STA     zp      3
    {nes_stx,	nes_zp,     3   },      // 0x86     STX     zp      3
    {nes_sax,	nes_zp,     3   },      // 0x87     SAX     zp      3
    {nes_dey,	NULL,	    2   },      // 0x88     DEY             2
    {nes_nop,	nes_imm,	2   },      // 0x89     NOP     imm     2
    {nes_txa,	NULL,	    2   },      // 0x8A     TXA             2
    {nes_xaa,	nes_imm,	2   },      // 0x8B     XAA     imm     2
    {nes_sty,	nes_abs,	4   },      // 0x8C     STY     abs     4
    {nes_sta,	nes_abs,	4   },      // 0x8D     STA     abs     4
    {nes_stx,	nes_abs,	4   },      // 0x8E     STX     abs     4
    {nes_sax,	nes_abs,	4   },      // 0x8F     SAX     abs     4
    {nes_bcc,	nes_rel,   	2   },      // 0x90     BCC     rel     2*
    {nes_sta,   nes_izy,    6   },      // 0x91     STA     izy     6
    {NULL,      NULL,	    0   },      // 0x92     KIL
    {nes_ahx,	nes_izy,	6   },      // 0x93     AHX     izy     6
    {nes_sty,	nes_zpx,	4   },      // 0x94     STY     zpx     4
    {nes_sta,	nes_zpx,    4   },      // 0x95     STA     zpx     4
    {nes_stx,	nes_zpy,    4   },      // 0x96     STX     zpy     4
    {nes_sax,	nes_zpy,    4   },      // 0x97     SAX     zpy     4
    {nes_tya,	NULL,	    2   },      // 0x98     TYA             2
    {nes_sta,	nes_aby,	5   },      // 0x99     STA     aby     5
    {nes_txs,	NULL,	    2   },      // 0x9A     TXS             2
    {nes_tas,	nes_aby,	5   },      // 0x9B     TAS     aby     5
    {nes_shy,	nes_abx,	5   },      // 0x9C     SHY     abx     5
    {nes_sta,	nes_abx,	5   },      // 0x9D     STA     abx     5
    {nes_shx,	nes_aby,	5   },      // 0x9E     SHX     aby     5
    {nes_ahx,	nes_aby,	5   },      // 0x9F     AHX     aby     5
    {nes_ldy,	nes_imm,   	2   },      // 0xA0     LDY     imm     2
    {nes_lda,   nes_izx,    6   },      // 0xA1     LDA     izx     6
    {nes_ldx,   nes_imm,	2   },      // 0xA2     LDX     imm     2
    {nes_lax,	nes_izx,	6   },      // 0xA3     LAX     izx     6
    {nes_ldy,	nes_zp,	    3   },      // 0xA4     LDY     zp      3
    {nes_lda,	nes_zp,     3   },      // 0xA5     LDA     zp      3
    {nes_ldx,	nes_zp,     3   },      // 0xA6     LDX     zp      3
    {nes_lax,	nes_zp,     3   },      // 0xA7     LAX     zp      3
    {nes_tay,	NULL,	    2   },      // 0xA8     TAY             2
    {nes_lda,	nes_imm,	2   },      // 0xA9     LDA     imm     2
    {nes_tax,	NULL,	    2   },      // 0xAA     TAX             2
    {nes_lax,	nes_imm,	2   },      // 0xAB     LAX     imm     2
    {nes_ldy,	nes_abs,	4   },      // 0xAC     LDY     abs     4
    {nes_lda,	nes_abs,	4   },      // 0xAD     LDA     abs     4
    {nes_ldx,	nes_abs,	4   },      // 0xAE     LDX     abs     4
    {nes_lax,	nes_abs,	4   },      // 0xAF     LAX     abs     4
    {nes_bcs,	nes_rel,   	2   },      // 0xB0     BCS     rel     2*
    {nes_lda,   nes_izy,    5   },      // 0xB1     LDA     izy     5*
    {NULL,      NULL,	    0   },      // 0xB2     KIL
    {nes_lax,	nes_izy,	5   },      // 0xB3     LAX     izy     5*
    {nes_ldy,	nes_zpx,	4   },      // 0xB4     LDY     zpx     4
    {nes_lda,	nes_zpx,    4   },      // 0xB5     LDA     zpx     4
    {nes_ldx,	nes_zpy,    4   },      // 0xB6     LDX     zpy     4
    {nes_lax,	nes_zpy,    4   },      // 0xB7     LAX     zpy     4
    {nes_clv,	NULL,	    2   },      // 0xB8     CLV             2
    {nes_lda,	nes_aby,	4   },      // 0xB9     LDA     aby     4*
    {nes_tsx,	NULL,	    2   },      // 0xBA     TSX             2
    {nes_las,	nes_aby,	4   },      // 0xBB     LAS     aby     4*
    {nes_ldy,	nes_abx,	4   },      // 0xBC     LDY     abx     4*
    {nes_lda,	nes_abx,	4   },      // 0xBD     LDA     abx     4*
    {nes_ldx,	nes_aby,	4   },      // 0xBE     LDX     aby     4*
    {nes_lax,	nes_aby,	4   },      // 0xBF     LAX     aby     4*
    {nes_cpy,	nes_imm,   	2   },      // 0xC0     CPY     imm     2
    {nes_cmp,   nes_izx,    6   },      // 0xC1     CMP     izx     6
    {nes_nop,   nes_imm,	2   },      // 0xC2     NOP     imm     2
    {nes_dcp,	nes_izx,	8   },      // 0xC3     DCP     izx     8
    {nes_cpy,	nes_zp,  	3   },      // 0xC4     CPY     zp      3
    {nes_cmp,	nes_zp,     3   },      // 0xC5     CMP     zp      3
    {nes_dec,	nes_zp,     5   },      // 0xC6     DEC     zp      5
    {nes_dcp,	nes_zp,     5   },      // 0xC7     DCP     zp      5
    {nes_iny,	NULL,	    2   },      // 0xC8     INY             2
    {nes_cmp,	nes_imm,	2   },      // 0xC9     CMP     imm     2
    {nes_dex,	NULL,	    2   },      // 0xCA     DEX             2
    {nes_axs,	nes_imm,	2   },      // 0xCB     AXS     imm     2
    {nes_cpy,	nes_abs,	4   },      // 0xCC     CPY     abs     4
    {nes_cmp,	nes_abs,	4   },      // 0xCD     CMP     abs     4
    {nes_dec,	nes_abs,	6   },      // 0xCE     DEC     abs     6
    {nes_dcp,	nes_abs,	6   },      // 0xCF     DCP     abs     6
    {nes_bne,	nes_rel,   	2   },      // 0xD0     BNE     rel     2*
    {nes_cmp,   nes_izy,    5   },      // 0xD1     CMP     izy     5*
    {NULL,      NULL,	    0   },      // 0xD2     KIL
    {nes_dcp,	nes_izy,	8   },      // 0xD3     DCP     izy     8
    {nes_nop,	nes_zpx,  	4   },      // 0xD4     NOP     zpx     4
    {nes_cmp,	nes_zpx,    4   },      // 0xD5     CMP     zpx     4
    {nes_dec,	nes_zpx,    6   },      // 0xD6     DEC     zpx     6
    {nes_dcp,	nes_zpx,    6   },      // 0xD7     DCP     zpx     6
    {nes_cld,	NULL,	    2   },      // 0xD8     CLD             2
    {nes_cmp,	nes_aby,	4   },      // 0xD9     CMP     aby     4*
    {nes_nop,	NULL,	    2   },      // 0xDA     NOP             2
    {nes_dcp,	nes_aby,	7   },      // 0xDB     DCP     aby     7
    {nes_nop,	nes_abx,	4   },      // 0xDC     NOP     abx     4*
    {nes_cmp,	nes_abx,	4   },      // 0xDD     CMP     abx     4*
    {nes_dec,	nes_abx,	7   },      // 0xDE     DEC     abx     7
    {nes_dcp,	nes_abx,	7   },      // 0xDF     DCP     abx     7
    {nes_cpx,	nes_imm,   	2   },      // 0xE0     CPX     imm     2
    {nes_sbc,   nes_izx,    6   },      // 0xE1     SBC     izx     6
    {nes_nop,   nes_imm,	2   },      // 0xE2     NOP     imm     2
    {nes_isc,	nes_izx,	8   },      // 0xE3     ISC     izx     8
    {nes_cpx,	nes_zp,  	3   },      // 0xE4     CPX     zp      3
    {nes_sbc,	nes_zp,     3   },      // 0xE5     SBC     zp      3
    {nes_inc,	nes_zp,     5   },      // 0xE6     INC     zp      5
    {nes_isc,	nes_zp,     5   },      // 0xE7     ISC     zp      5
    {nes_inx,	NULL,	    2   },      // 0xE8     INX             2
    {nes_sbc,	nes_imm,	2   },      // 0xE9     SBC     imm     2
    {nes_nop,	NULL,	    2   },      // 0xEA     NOP             2
    {nes_sbc,	nes_imm,	2   },      // 0xEB     SBC     imm     2
    {nes_cpx,	nes_abs,	4   },      // 0xEC     CPX     abs     4
    {nes_sbc,	nes_abs,	4   },      // 0xED     SBC     abs     4
    {nes_inc,	nes_abs,	6   },      // 0xEE     INC     abs     6
    {nes_isc,	nes_abs,	6   },      // 0xEF     ISC     abs     6
    {nes_beq,	nes_rel,   	2   },      // 0xF0     BEQ     rel     2*
    {nes_sbc,   nes_izy,    5   },      // 0xF1     SBC     izy     5*
    {NULL,      NULL,	    0   },      // 0xF2     KIL
    {nes_isc,	nes_izy,	8   },      // 0xF3     ISC     izy     8
    {nes_nop,	nes_zpx,  	4   },      // 0xF4     NOP     zpx     4
    {nes_sbc,	nes_zpx,    4   },      // 0xF5     SBC     zpx     4
    {nes_inc,	nes_zpx,    6   },      // 0xF6     INC     zpx     6
    {nes_isc,	nes_zpx,    6   },      // 0xF7     ISC     zpx     6
    {nes_sed,	NULL,	    2   },      // 0xF8     SED             2
    {nes_sbc,	nes_aby,	4   },      // 0xF9     SBC     aby     4*
    {nes_nop,	NULL,	    2   },      // 0xFA     NOP             2
    {nes_isc,	nes_aby,	7   },      // 0xFB     ISC     aby     7
    {nes_nop,	nes_abx,	4   },      // 0xFC     NOP     abx     4*
    {nes_sbc,	nes_abx,	4   },      // 0xFD     SBC     abx     4*
    {nes_inc,	nes_abx,	7   },      // 0xFE     INC     abx     7
    {nes_isc,	nes_abx,	7   },      // 0xFF     ISC     abx     7
};


void nes_opcode(nes_t* nes,uint16_t ticks){
    while (ticks > nes->nes_cpu.cycles){
        nes->nes_cpu.opcode = nes_read_cpu(nes,nes->nes_cpu.PC++);
        nes_opcode_table[nes->nes_cpu.opcode].instruction(nes);
        nes->nes_cpu.cycles += nes_opcode_table[nes->nes_cpu.opcode].ticks;
    }
    nes->nes_cpu.cycles -= ticks;
}


