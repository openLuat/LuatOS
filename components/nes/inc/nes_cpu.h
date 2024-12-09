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

#ifndef _NES_CPU_
#define _NES_CPU_

#ifdef __cplusplus
    extern "C" {
#endif


// https://www.nesdev.org/wiki/Controller_reading
#define NES_CPU_RAM_SIZE        0x800   /*  2KB */

struct nes;
typedef struct nes nes_t;

#define NES_VERCTOR_NMI         0xFFFA  /*  NMI vector (NMI=not maskable interupts) */
#define NES_VERCTOR_RESET       0xFFFC  /*  Reset vector */
#define NES_VERCTOR_IRQBRK      0xFFFE  /*  IRQ vector */

/*
Bit No. 15      14      13      12      11      10      9       8
        A1      B1      Select1 Start1  Up1     Down1   Left1   Right1 
Bit No. 7       6       5       4       3       2       1       0
        A2      B2      Select2 Start2  Up2     Down2   Left2   Right2 
*/
typedef struct nes_joypad{
    uint8_t offset1;
    uint8_t offset2;
    uint8_t mask;
    union {
        struct {
            uint8_t R2:1;   
            uint8_t L2:1;    
            uint8_t D2:1;    
            uint8_t U2:1;  
            uint8_t ST2:1; 
            uint8_t SE2:1;
            uint8_t B2:1;    
            uint8_t A2:1;
            uint8_t R1:1;   
            uint8_t L1:1;    
            uint8_t D1:1;    
            uint8_t U1:1;  
            uint8_t ST1:1; 
            uint8_t SE1:1;
            uint8_t B1:1;    
            uint8_t A1:1;  
        };
        uint16_t joypad;
    };
} nes_joypad_t;

// https://www.nesdev.org/wiki/CPU_registers
typedef struct nes_cpu{
    /*  CPU registers */
    uint8_t A;                          /*  Accumulator */
    uint8_t X;                          /*  Indexes X */
    uint8_t Y;                          /*  Indexes Y */
    uint16_t PC;                        /*  Program Counter */
    uint8_t SP;                         /*  Stack Pointer */
    union {
        struct {
            uint8_t C:1;                /*  carry flag (1 on unsigned overflow) */
            uint8_t Z:1;                /*  zero flag (1 when all bits of a result are 0) */
            uint8_t I:1;                /*  IRQ flag (when 1, no interupts will occur (exceptions are IRQs forced by BRK and NMIs)) */
            uint8_t D:1;                /*  decimal flag (1 when CPU in BCD mode) */
            uint8_t B:1;                /*  break flag (1 when interupt was caused by a BRK) */
            uint8_t U:1;                /*  unused (always 1) */
            uint8_t V:1;                /*  overflow flag (1 on signed overflow) */
            uint8_t N:1;                /*  negative flag (1 when result is negative) */
        };
        uint8_t P;                      /*  Status Register */
    };
    uint32_t cycles;  
    uint8_t opcode;     
    uint8_t cpu_ram[NES_CPU_RAM_SIZE];
    uint8_t* prg_banks[4];              /*  4 bank ( 8Kb * 4 ) = 32KB  */
    nes_joypad_t joypad;
} nes_cpu_t;

void nes_cpu_init(nes_t *nes);
void nes_cpu_reset(nes_t* nes);

void nes_nmi(nes_t* nes);
void nes_opcode(nes_t* nes,uint16_t ticks);

#ifdef __cplusplus          
    }
#endif

#endif// _NES_CPU_
