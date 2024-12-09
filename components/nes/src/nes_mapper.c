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

void nes_load_prgrom_8k(nes_t* nes,int des, int src) {
    nes->nes_cpu.prg_banks[des] = nes->nes_rom.prg_rom + 8 * 1024 * src;
}

void nes_load_chrrom_1k(nes_t* nes,int des, int src) {
    nes->nes_ppu.pattern_table[des] = nes->nes_rom.chr_rom + 1024 * src;
}

int nes_load_mapper(nes_t* nes){
    switch (nes->nes_rom.mapper_number){
        case 0 :
            return nes_mapper0_init(nes);
        case 2 :
            return nes_mapper2_init(nes);
        default :
            nes_printf("mapper:%03d is unsupported\n",nes->nes_rom.mapper_number);
            return NES_ERROR;
    }
}
