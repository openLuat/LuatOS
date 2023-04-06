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

#define NES_PPU_CPU_CLOCKS		113

int nes_init(nes_t *nes){
    nes_initex(nes);
    nes_cpu_init(nes);
    nes_ppu_init(nes);
    return 0;
}

int nes_deinit(nes_t *nes){
    nes->nes_quit = 1;
    nes_deinitex(nes);
    return 0;
}

extern nes_color_t nes_palette[];

static inline void nes_palette_generate(nes_t* nes){
    for (size_t i = 0; i < 32; i++) {
        nes->nes_ppu.palette[i] = nes_palette[nes->nes_ppu.palette_indexes[i]];
    }
    for (size_t i = 1; i < 8; i++){
        nes->nes_ppu.palette[4 * i] = nes->nes_ppu.palette[0];
    }
}

static void nes_render_background_line(nes_t* nes,uint16_t scanline,nes_color_t* draw_data){
    uint8_t p = 0;
    int8_t m = 7 - nes->nes_ppu.x;
    const uint8_t dx = (const uint8_t)nes->nes_ppu.v.coarse_x;
    const uint8_t dy = (const uint8_t)nes->nes_ppu.v.fine_y;
    const uint8_t tile_y = (const uint8_t)nes->nes_ppu.v.coarse_y;
    uint8_t nametable_id = (uint8_t)nes->nes_ppu.v.nametable;
    for (uint8_t tile_x = dx; tile_x < 32; tile_x++){
        uint32_t pattern_id = nes->nes_ppu.name_table[nametable_id][tile_x + (tile_y << 5)];
        const uint8_t* bit0_p = nes->nes_ppu.pattern_table[nes->nes_ppu.CTRL_B ? 4 : 0] + pattern_id * 16;
        const uint8_t* bit1_p = bit0_p + 8;
        const uint8_t bit0 = bit0_p[dy];
        const uint8_t bit1 = bit1_p[dy];
        uint8_t attribute = nes->nes_ppu.name_table[nametable_id][960 + ((tile_y >> 2) << 3) + (tile_x >> 2)];
        // 1:D4-D5/D6-D7 0:D0-D1/D2-D3
        // 1:D2-D3/D6-D7 0:D0-D1/D4-D5
        const uint8_t high_bit = ((attribute >> (((tile_y & 2) << 1) | (tile_x & 2))) & 3) << 2;
        for (; m >= 0; m--){
            uint8_t low_bit = ((bit0 >> m) & 0x01) | ((bit1 >> m)<<1 & 0x02);
            uint8_t palette_index = (high_bit & 0x0c) | low_bit;
            draw_data[p++] = nes->nes_ppu.background_palette[palette_index];
        }
        m = 7;
    }
    nametable_id ^= nes->nes_rom.mirroring_type ? 1:2;
    for (uint8_t tile_x = 0; tile_x <= dx; tile_x++){
        uint32_t pattern_id = nes->nes_ppu.name_table[nametable_id][tile_x + (tile_y << 5)];
        const uint8_t* bit0_p = nes->nes_ppu.pattern_table[nes->nes_ppu.CTRL_B ? 4 : 0] + pattern_id * 16;
        const uint8_t* bit1_p = bit0_p + 8;
        const uint8_t bit0 = bit0_p[dy];
        const uint8_t bit1 = bit1_p[dy];
        uint8_t attribute = nes->nes_ppu.name_table[nametable_id][960 + ((tile_y >> 2) << 3) + (tile_x >> 2)];
        // 1:D4-D5/D6-D7 0:D0-D1/D2-D3
        // 1:D2-D3/D6-D7 0:D0-D1/D4-D5
        const uint8_t high_bit = ((attribute >> (((tile_y & 2) << 1) | (tile_x & 2))) & 3) << 2;
        uint8_t skew = 0;
        if (tile_x == dx){
            if (nes->nes_ppu.x){
                skew = 8 - nes->nes_ppu.x;
            }else
                break;
        }
        for (; m >= skew; m--){
            uint8_t low_bit = ((bit0 >> m) & 0x01) | ((bit1 >> m)<<1 & 0x02);
            uint8_t palette_index = (high_bit & 0x0c) | low_bit;
            draw_data[p++] = nes->nes_ppu.background_palette[palette_index];
        }
        m = 7;
    }
}

static void nes_render_sprite_line(nes_t* nes,uint16_t scanline,nes_color_t* draw_data){
    nes_color_t background_color = nes->nes_ppu.background_palette[0];
    uint8_t sprite_number = 0;
    uint8_t sprite_size = nes->nes_ppu.CTRL_H?16:8;
    
    for (uint8_t i = 63; i > 0 ; i--){
        if (nes->nes_ppu.sprite_info[i].y >= 0xEF)
            continue;
        uint8_t sprite_y = (uint8_t)(nes->nes_ppu.sprite_info[i].y + 1);
        if (scanline < sprite_y || scanline >= sprite_y + sprite_size)
            continue;
        sprite_number ++;
        if(sprite_number > 8 ){
            nes->nes_ppu.STATUS_O = 1;
            goto sprite0;
        }

        const uint8_t* sprite_bit0_p = nes->nes_ppu.pattern_table[nes->nes_ppu.CTRL_H?((nes->nes_ppu.sprite_info[i].pattern_8x16)?4:0):(nes->nes_ppu.CTRL_S?4:0)] \
                                        + (nes->nes_ppu.CTRL_H?(nes->nes_ppu.sprite_info[i].tile_index_8x16 << 1 ):(nes->nes_ppu.sprite_info[i].tile_index_number)) * 16;
        const uint8_t* sprite_bit1_p = sprite_bit0_p + 8;

        uint8_t dy = scanline - sprite_y;

        if (nes->nes_ppu.CTRL_H){
            if (nes->nes_ppu.sprite_info[i].flip_v){
                if (dy < 8){
                    sprite_bit0_p +=16;
                    sprite_bit1_p +=16;
                    dy = sprite_size - dy - 1 -8;
                }else{
                    dy = sprite_size - dy - 1;
                }
            }else{
                if (dy > 7){
                    sprite_bit0_p +=16;
                    sprite_bit1_p +=16;
                    dy-=8;
                }
            }
        }else{
            if (nes->nes_ppu.sprite_info[i].flip_v){
                dy = sprite_size - dy - 1;
            }
        }

        const uint8_t sprite_bit0 = sprite_bit0_p[dy];
        const uint8_t sprite_bit1 = sprite_bit1_p[dy];

        uint8_t p = nes->nes_ppu.sprite_info[i].x;
        if (nes->nes_ppu.sprite_info[i].flip_h){
            for (int8_t m = 0; m <= 7; m++){
                uint8_t low_bit = ((sprite_bit0 >> m) & 0x01) | ((sprite_bit1 >> m)<<1 & 0x02);
                uint8_t palette_index = (nes->nes_ppu.sprite_info[i].sprite_palette << 2) | low_bit;
                if (palette_index%4 != 0){
                    if (nes->nes_ppu.sprite_info[i].priority){
                        if (draw_data[p] == background_color){
                            draw_data[p] = nes->nes_ppu.sprite_palette[palette_index];
                        }
                    }else{
                        draw_data[p] = nes->nes_ppu.sprite_palette[palette_index];
                    }
                }
                if (p == 255)
                    break;
                p++;
            }
        }else{
            for (int8_t m = 7; m >= 0; m--){
                uint8_t low_bit = ((sprite_bit0 >> m) & 0x01) | ((sprite_bit1 >> m)<<1 & 0x02);
                uint8_t palette_index = (nes->nes_ppu.sprite_info[i].sprite_palette << 2) | low_bit;
                if (palette_index%4 != 0){
                    if (nes->nes_ppu.sprite_info[i].priority){
                        if (draw_data[p] == background_color){
                            draw_data[p] = nes->nes_ppu.sprite_palette[palette_index];
                        }
                    }else{
                        draw_data[p] = nes->nes_ppu.sprite_palette[palette_index];
                    }
                }
                if (p == 255)
                    break;
                p++;
            }
        }
    }
sprite0:
    // sprite 0
    if (nes->nes_ppu.sprite_info[0].y >= 0xEF)
        return;
    uint8_t sprite_y = (uint8_t)(nes->nes_ppu.sprite_info[0].y + 1);
    if (scanline < sprite_y || scanline >= sprite_y + sprite_size)
        return;
    sprite_number ++;
    if(sprite_number > 8 ){
        nes->nes_ppu.STATUS_O = 1;
    }

    const uint8_t* sprite_bit0_p = nes->nes_ppu.pattern_table[nes->nes_ppu.CTRL_H?((nes->nes_ppu.sprite_info[0].pattern_8x16)?4:0):(nes->nes_ppu.CTRL_S?4:0)] \
                                    + (nes->nes_ppu.CTRL_H?(nes->nes_ppu.sprite_info[0].tile_index_8x16 << 1 ):(nes->nes_ppu.sprite_info[0].tile_index_number)) * 16;
    const uint8_t* sprite_bit1_p = sprite_bit0_p + 8;

    uint8_t dy = scanline - sprite_y;

    if (nes->nes_ppu.CTRL_H){
        if (nes->nes_ppu.sprite_info[0].flip_v){
            if (dy < 8){
                sprite_bit0_p +=16;
                sprite_bit1_p +=16;
                dy = sprite_size - dy - 1 -8;
            }else{
                dy = sprite_size - dy - 1;
            }
        }else{
            if (dy > 7){
                sprite_bit0_p +=16;
                sprite_bit1_p +=16;
                dy-=8;
            }
        }
    }else{
        if (nes->nes_ppu.sprite_info[0].flip_v){
            dy = sprite_size - dy - 1;
        }
    }
    
    const uint8_t sprite_bit0 = sprite_bit0_p[dy];
    const uint8_t sprite_bit1 = sprite_bit1_p[dy];

    const uint8_t sprite_date = sprite_bit0 | sprite_bit1;
    if (sprite_date && nes->nes_ppu.MASK_b && nes->nes_ppu.STATUS_S == 0){
        uint8_t nametable_id = (uint8_t)nes->nes_ppu.v.nametable;
        const uint8_t tile_x = (nes->nes_ppu.sprite_info[0].x) >> 3;
        const uint8_t tile_y = scanline >> 3;
        uint32_t pattern_id = nes->nes_ppu.name_table[nametable_id][tile_x + (tile_y << 5)];
        const uint8_t* bit0_p = nes->nes_ppu.pattern_table[nes->nes_ppu.CTRL_B ? 4 : 0] + pattern_id * 16;
        const uint8_t* bit1_p = bit0_p + 8;
        uint8_t background_date = bit0_p[dy] | bit1_p[dy]<<1;
        if (sprite_date == background_date){
            nes->nes_ppu.STATUS_S = 1;
        }
    }
    if (nes->nes_ppu.STATUS_O == 1){
        return;
    }
    
    uint8_t p = nes->nes_ppu.sprite_info[0].x;
    if (nes->nes_ppu.sprite_info[0].flip_h){
        for (int8_t m = 0; m <= 7; m++){
            uint8_t low_bit = ((sprite_bit0 >> m) & 0x01) | ((sprite_bit1 >> m)<<1 & 0x02);
            uint8_t palette_index = (nes->nes_ppu.sprite_info[0].sprite_palette << 2) | low_bit;
            if (palette_index%4 != 0){
                if (nes->nes_ppu.sprite_info[0].priority){
                    if (draw_data[p] == background_color){
                        draw_data[p] = nes->nes_ppu.sprite_palette[palette_index];
                    }
                }else{
                    draw_data[p] = nes->nes_ppu.sprite_palette[palette_index];
                }
            }
            if (p == 255)
                break;
            p++;
        }
    }else{
        for (int8_t m = 7; m >= 0; m--){
            uint8_t low_bit = ((sprite_bit0 >> m) & 0x01) | ((sprite_bit1 >> m)<<1 & 0x02);
            uint8_t palette_index = (nes->nes_ppu.sprite_info[0].sprite_palette << 2) | low_bit;
            if (palette_index%4 != 0){
                if (nes->nes_ppu.sprite_info[0].priority){
                    if (draw_data[p] == background_color){
                        draw_data[p] = nes->nes_ppu.sprite_palette[palette_index];
                    }
                }else{
                    draw_data[p] = nes->nes_ppu.sprite_palette[palette_index];
                }
            }
            if (p == 255)
                break;
            p++;
        }
    }
}


void nes_run(nes_t* nes){
    // nes_printf("mapper:%03d\n",nes->nes_rom.mapper_number);
    // nes_printf("prg_rom_size:%d*16kb\n",nes->nes_rom.prg_rom_size);
    // nes_printf("chr_rom_size:%d*8kb\n",nes->nes_rom.chr_rom_size);
    nes_cpu_reset(nes);
    // nes->nes_cpu.PC = 0xC000;
    // printf("nes->nes_cpu.PC %02X",nes->nes_cpu.PC);
    uint64_t frame_cnt = 0;
    uint16_t scanline = 0;

    while (!nes->nes_quit){
        frame_cnt++;
        nes_palette_generate(nes);

        if (nes->nes_ppu.MASK_b == 0){
#if (NES_RAM_LACK == 1)
            for (size_t i = 0; i < NES_HEIGHT * NES_WIDTH / 2; i++){
                nes->nes_draw_data[i] = nes->nes_ppu.background_palette[0];
            }
#else
            for (size_t i = 0; i < NES_HEIGHT * NES_WIDTH; i++){
                nes->nes_draw_data[i] = nes->nes_ppu.background_palette[0];
            }
#endif
        }
        
        for(scanline = 0; scanline < NES_HEIGHT; scanline++) { // 0-239 Visible frame
            if (nes->nes_ppu.MASK_b){
#if (NES_RAM_LACK == 1)
                nes_render_background_line(nes,scanline,nes->nes_draw_data + scanline%(NES_HEIGHT/2) * NES_WIDTH);
#else
                nes_render_background_line(nes,scanline,nes->nes_draw_data + scanline * NES_WIDTH);
#endif
            }
            if (nes->nes_ppu.MASK_s){
#if (NES_RAM_LACK == 1)
                nes_render_sprite_line(nes,scanline,nes->nes_draw_data + scanline%(NES_HEIGHT/2) * NES_WIDTH);
#else
                nes_render_sprite_line(nes,scanline,nes->nes_draw_data + scanline * NES_WIDTH);
#endif
            }
            nes_opcode(nes,NES_PPU_CPU_CLOCKS);
            if (nes->nes_ppu.MASK_b){
                if ((nes->nes_ppu.v.fine_y) < 7) {
                    nes->nes_ppu.v.fine_y++;
                }else {
                    nes->nes_ppu.v.fine_y = 0;
                    uint8_t y = (uint8_t)(nes->nes_ppu.v.coarse_y);
                    if (y == 29) {
                        y = 0;
                        nes->nes_ppu.v_reg ^= 0x0800;
                    }else if (y == 31) {
                        y = 0;
                    }else {
                        y++;
                    }
                    nes->nes_ppu.v.coarse_y = y;
                }
                // v: ....A.. ...BCDEF <- t: ....A.. ...BCDEF
                nes->nes_ppu.v_reg = (nes->nes_ppu.v_reg & (uint16_t)0xFBE0) | (nes->nes_ppu.t_reg & (uint16_t)0x041F);
            }
            
#if (NES_RAM_LACK == 1)
            if((frame_cnt % (NES_FRAME_SKIP+1))==0){
                if (scanline == NES_HEIGHT/2-1){
                    nes_draw(0, 0, NES_WIDTH-1, NES_HEIGHT/2-1, nes->nes_draw_data);
                }else if(scanline == NES_HEIGHT-1){
                    nes_draw(0, NES_HEIGHT/2, NES_WIDTH-1, NES_HEIGHT-1, nes->nes_draw_data);
                }
            }
#endif
        }
#if (NES_RAM_LACK == 0)
        if((frame_cnt % (NES_FRAME_SKIP+1))==0){
            nes_draw(0, 0, NES_WIDTH-1, NES_HEIGHT-1, nes->nes_draw_data);
        }
#endif
        nes_opcode(nes,NES_PPU_CPU_CLOCKS); //240 Post-render line

        nes->nes_ppu.STATUS_V = 1;// Set VBlank flag
        if (nes->nes_ppu.CTRL_V) {
            nes_nmi(nes);
        }
        for(; scanline < 261; scanline++){ // 241-260行 垂直空白行 x20
            nes_opcode(nes,NES_PPU_CPU_CLOCKS);
        }

        nes->nes_ppu.ppu_status &= 0x10; // Clear:VBlank,Sprite 0,Overflow
        nes_opcode(nes,NES_PPU_CPU_CLOCKS); // 261 Pre-render line
        //do more
        if (nes->nes_ppu.MASK_b){
            // v: GHIA.BC DEF..... <- t: GHIA.BC DEF.....
            nes->nes_ppu.v_reg = (nes->nes_ppu.v_reg & (uint16_t)0x841F) | (nes->nes_ppu.t_reg & (uint16_t)0x7BE0);
        }
        // nes_frame();
    }
}

