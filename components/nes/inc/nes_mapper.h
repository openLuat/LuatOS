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

#ifndef _NES_MAPPER_
#define _NES_MAPPER_

#ifdef __cplusplus
    extern "C" {
#endif

struct nes;
typedef struct nes nes_t;

typedef struct {
    /* Initialize Mapper */
    void (*mapper_init)(nes_t* nes);
    /* Write to Mapper */
    void (*mapper_write)(nes_t* nes,uint16_t write_addr, uint8_t data );
    /* Write to SRAM */
    void (*mapper_sram)( uint16_t write_addr, uint8_t data );
    /* Write to Apu */
    void (*mapper_apu)( uint16_t write_addr, uint8_t data );
    /* Read from Apu */
    uint8_t (*mapper_read_apu)( uint16_t write_addr );
    /* Callback at VSync */
    void (*mapper_vsync)(void);
    /* Callback at HSync */
    void (*mapper_hsync)(void);
    /* Callback at PPU read/write */
    void (*mapper_ppu)( uint16_t write_addr );
    /* Callback at Rendering Screen 1:BG, 0:Sprite */
    void (*mapper_render_screen)( uint8_t mode );
} nes_mapper_t;

/* mapper */
int nes_load_mapper(nes_t* nes);
void nes_load_prgrom_8k(nes_t* nes,int des, int src);
void nes_load_chrrom_1k(nes_t* nes,int des, int src);
int nes_mapper0_init(nes_t* nes);
int nes_mapper1_init(nes_t* nes);
int nes_mapper2_init(nes_t* nes);

#ifdef __cplusplus          
    }
#endif

#endif// _NES_MAPPER_
