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

//https://www.nesdev.org/pal.txt
#if (NES_COLOR_DEPTH == 32)
// ARGB8888
nes_color_t nes_palette[]={
    0xFF757575, 0xFF271B8F, 0xFF0000AB, 0xFF47009F, 0xFF8F0077, 0xFFB0013, 0xFFA70000, 0xFF7F0B00,0xFF432F00, 0xFF004700, 0xFF005100, 0xFF003F17, 0xFF1B3F5F, 0xFF000000, 0xFF000000, 0xFF000000,
    0xFFBCBCBC, 0xFF0073EF, 0xFF233BEF, 0xFF8300F3, 0xFFBF00BF, 0xFF7005B, 0xFFDB2B00, 0xFFCB4F0F,0xFF8B7300, 0xFF009700, 0xFF00AB00, 0xFF00933B, 0xFF00838B, 0xFF000000, 0xFF000000, 0xFF000000,
    0xFFFFFFFF, 0xFF3FBFFF, 0xFF5F97FF, 0xFFA78BFD, 0xFFF77BFF, 0xFFF77B7, 0xFFFF7763, 0xFFFF9B3B,0xFFF3BF3F, 0xFF83D313, 0xFF4FDF4B, 0xFF58F898, 0xFF00EBDB, 0xFF000000, 0xFF000000, 0xFF000000,
    0xFFFFFFFF, 0xFFABE7FF, 0xFFC7D7FF, 0xFFD7CBFF, 0xFFFFC7FF, 0xFFFC7DB, 0xFFFFBFB3, 0xFFFFDBAB,0xFFFFE7A3, 0xFFE3FFA3, 0xFFABF3BF, 0xFFB3FFCF, 0xFF9FFFF3, 0xFF000000, 0xFF000000, 0xFF000000,
};
#elif (NES_COLOR_DEPTH == 16)
#if (NES_COLOR_SWAP == 0)
// RGB565
nes_color_t nes_palette[]={
    0x73AE, 0x20D1, 0x0015, 0x4013, 0x880E, 0x0802, 0xA000, 0x7840,0x4160, 0x0220, 0x0280, 0x01E2, 0x19EB, 0x0000, 0x0000, 0x0000,
    0xBDF7, 0x039D, 0x21DD, 0x801E, 0xB817, 0x000B, 0xD940, 0xCA61,0x8B80, 0x04A0, 0x0540, 0x0487, 0x0411, 0x0000, 0x0000, 0x0000,
    0xFFFF, 0x3DFF, 0x5CBF, 0xA45F, 0xF3DF, 0x0BB6, 0xFBAC, 0xFCC7,0xF5E7, 0x8682, 0x4EE9, 0x5FD3, 0x075B, 0x0000, 0x0000, 0x0000,
    0xFFFF, 0xAF3F, 0xC6BF, 0xD65F, 0xFE3F, 0x0E3B, 0xFDF6, 0xFED5,0xFF34, 0xE7F4, 0xAF97, 0xB7F9, 0x9FFE, 0x0000, 0x0000, 0x0000,
};
#else
// RGB565_SWAP
nes_color_t nes_palette[]={
    0xAE73, 0xD120, 0x1500, 0x1340, 0x0E88, 0x0208, 0x00A0, 0x4078,0x6041, 0x2002, 0x8002, 0xE201, 0xEB19, 0x0000, 0x0000, 0x0000,
    0xF7BD, 0x9D03, 0xDD21, 0x1E80, 0x17B8, 0x0B00, 0x40D9, 0x61CA,0x808B, 0xA004, 0x4005, 0x8704, 0x1104, 0x0000, 0x0000, 0x0000,
    0xFFFF, 0xFF3D, 0xBF5C, 0x5FA4, 0xDFF3, 0xB60B, 0xACFB, 0xC7FC,0xE7F5, 0x8286, 0xE94E, 0xD35F, 0x5B07, 0x0000, 0x0000, 0x0000,
    0xFFFF, 0x3FAF, 0xBFC6, 0x5FD6, 0x3FFE, 0x3B0E, 0xF6FD, 0xD5FE,0x34FF, 0xF4E7, 0x97AF, 0xF9B7, 0xFE9F, 0x0000, 0x0000, 0x0000,
};
#endif
#endif

static inline uint8_t nes_read_ppu_memory(nes_t* nes){
    const uint16_t address = nes->nes_ppu.v_reg & (uint16_t)0x3FFF;
    const uint16_t index = address >> 10;
    const uint16_t offset = address & (uint16_t)0x3FF;
    if (address < (uint16_t)0x3F00) {
        uint8_t data = nes->nes_ppu.buffer;
        nes->nes_ppu.buffer = nes->nes_ppu.chr_banks[index][offset];
        return data;
    } else {
        nes->nes_ppu.buffer = nes->nes_ppu.chr_banks[index][offset];
        return nes->nes_ppu.palette_indexes[address & (uint16_t)0x1f];
    }
}

static inline void nes_write_ppu_memory(nes_t* nes,uint8_t data){
    const uint16_t address = nes->nes_ppu.v_reg & (uint16_t)0x3FFF;
    if (address < (uint16_t)0x3F00) {
        const uint16_t index = address >> 10;
        const uint16_t offset = address & (uint16_t)0x3FF;
        nes->nes_ppu.chr_banks[index][offset] = data;
    } else {
        if (address & (uint16_t)0x03) {
            nes->nes_ppu.palette_indexes[address & (uint16_t)0x1f] = data;
        } else {
            const uint16_t offset = address & (uint16_t)0x0f;
            nes->nes_ppu.palette_indexes[offset] = data;
            nes->nes_ppu.palette_indexes[offset | (uint16_t)0x10] = data;
        }
    }
}

// https://www.nesdev.org/wiki/PPU_registers
uint8_t nes_read_ppu_register(nes_t* nes,uint16_t address){
    uint8_t data = 0;
    switch (address & (uint16_t)0x07){
        case 2://Status ($2002) < read
            // w:                  <- 0
            data = nes->nes_ppu.ppu_status;
            nes->nes_ppu.STATUS_V = 0;
            nes->nes_ppu.w = 0;
            break;
        case 4://OAM data ($2004) <> read/write
            data = nes->nes_ppu.oam_data[nes->nes_ppu.oam_addr];
            break;
        case 7://Data ($2007) <> read/write
            data = nes_read_ppu_memory(nes);
            nes->nes_ppu.v_reg += (uint16_t)((nes->nes_ppu.CTRL_I) ? 32 : 1);
            break;
        default :
            nes_printf("nes_read_ppu_register error %04X\n",address);
            return -1;
    }
    // nes_printf("nes_read_ppu_register %04X %02X\n",address,data);
    return data;
}

void nes_write_ppu_register(nes_t* nes,uint16_t address, uint8_t data){
    // nes_printf("nes_write_ppu_register %04X %02X\n",address,data);
    switch (address & (uint16_t)0x07){
        case 0://Controller ($2000) > write
            // t: ...GH.. ........ <- d: ......GH
            //    <used elsewhere> <- d: ABCDEF..
            nes->nes_ppu.ppu_ctrl = data;
            nes->nes_ppu.t.nametable = (data & 0x03);
            break;
        case 1://Mask ($2001) > write
            nes->nes_ppu.ppu_mask = data;
            break;
        case 3://OAM address ($2003) > write
            nes->nes_ppu.oam_addr = data;
            break;
        case 4://OAM data ($2004) <> read/write
            nes->nes_ppu.oam_data[nes->nes_ppu.oam_addr++] = data;
            break;
        case 5://Scroll ($2005) >> write x2
            if (nes->nes_ppu.w) {   // w is 1
                // t: FGH..AB CDE..... <- d: ABCDEFGH
                // w:                  <- 0
                nes->nes_ppu.t.fine_y = (data & 0x07);
                nes->nes_ppu.t.coarse_y = (data & 0xF8)>>3;
                nes->nes_ppu.w = 0;
            } else {                // w is 0
                // t: ....... ...ABCDE <- d: ABCDE...
                // x:              FGH <- d: .....FGH
                // w:                  <- 1
                nes->nes_ppu.t.coarse_x = (data & 0xF8)>>3;
                nes->nes_ppu.x = (data & 0x07);
                nes->nes_ppu.w = 1;
            }
            break;
        case 6://Address ($2006) >> write x2
            if (nes->nes_ppu.w) {   // w is 1
                // t: ....... ABCDEFGH <- d: ABCDEFGH
                // v: <...all bits...> <- t: <...all bits...>
                // w:                  <- 0
                nes->nes_ppu.t_reg = (nes->nes_ppu.t_reg & (uint16_t)0xFF00) | (uint16_t)data;
                nes->nes_ppu.v_reg = nes->nes_ppu.t_reg;
                nes->nes_ppu.w = 0;
            } else {                // w is 0
                // t: .CDEFGH ........ <- d: ..CDEFGH
                //        <unused>     <- d: AB......
                // t: Z...... ........ <- 0 (bit Z is cleared)
                // w:                  <- 1
                nes->nes_ppu.t_reg = (nes->nes_ppu.t_reg & (uint16_t)0xFF) | (((uint16_t)data & 0x3F) << 8);
                nes->nes_ppu.w = 1;
            }
            break;
        case 7://Data ($2007) <> read/write
            nes_write_ppu_memory(nes,data);
            nes->nes_ppu.v_reg += (uint16_t)((nes->nes_ppu.CTRL_I) ? 32 : 1);
            break;
        default :
            nes_printf("nes_write_ppu_register error %04X %02X\n",address,data);
            return;
    }
}

void nes_ppu_init(nes_t *nes){
    // four_screen
    if (nes->nes_rom.four_screen) { 
        nes->nes_ppu.name_table[0] = nes->nes_ppu.ppu_vram0;
        nes->nes_ppu.name_table[1] = nes->nes_ppu.ppu_vram1;
        nes->nes_ppu.name_table[2] = nes->nes_ppu.ppu_vram2;
        nes->nes_ppu.name_table[3] = nes->nes_ppu.ppu_vram3;
    }
    // Vertical
    else if (nes->nes_rom.mirroring_type) {
        nes->nes_ppu.name_table[0] = nes->nes_ppu.ppu_vram0;
        nes->nes_ppu.name_table[1] = nes->nes_ppu.ppu_vram1;
        nes->nes_ppu.name_table[2] = nes->nes_ppu.ppu_vram0;
        nes->nes_ppu.name_table[3] = nes->nes_ppu.ppu_vram1;
    }
    // Horizontal or mapper-controlled
    else {
        nes->nes_ppu.name_table[0] = nes->nes_ppu.ppu_vram0;
        nes->nes_ppu.name_table[1] = nes->nes_ppu.ppu_vram0;
        nes->nes_ppu.name_table[2] = nes->nes_ppu.ppu_vram1;
        nes->nes_ppu.name_table[3] = nes->nes_ppu.ppu_vram1;
    }
    // mirrors
    nes->nes_ppu.chr_banks[12] = nes->nes_ppu.name_table[0];
    nes->nes_ppu.chr_banks[13] = nes->nes_ppu.name_table[1];
    nes->nes_ppu.chr_banks[14] = nes->nes_ppu.name_table[2];
    nes->nes_ppu.chr_banks[15] = nes->nes_ppu.name_table[3];
}

