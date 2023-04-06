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

#ifndef _NES_
#define _NES_

#include "nes_port.h"
#include "nes_rom.h"
#include "nes_cpu.h"
#include "nes_ppu.h"
#include "nes_apu.h"
#include "nes_mapper.h"

#ifdef __cplusplus
    extern "C" {
#endif

#define NES_NAME                "NES"
#define NES_WIDTH               256
#define NES_HEIGHT              240

#define NES_OK                  0 
#define NES_ERROR               -1

typedef struct nes{
    uint8_t nes_quit;
    nes_rom_info_t nes_rom;
    nes_cpu_t nes_cpu;
    nes_ppu_t nes_ppu;
    nes_mapper_t nes_mapper;
    nes_color_t nes_draw_data[NES_DRAW_SIZE];
} nes_t;


int nes_init(nes_t *nes);
int nes_deinit(nes_t *nes);

int nes_initex(nes_t* nes);
int nes_deinitex(nes_t* nes);

void nes_run(nes_t* nes);

#ifdef __cplusplus          
    }
#endif

#endif// _NES_
