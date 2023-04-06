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

#if (NES_USE_SRAM == 1)
    #define SRAM_SIZE           (0x2000)
#endif

#if (NES_USE_FS == 1)
nes_t* nes_load_file(const char* file_path ){
    nes_header_info_t nes_header_info = {0};
    nes_t* nes = NULL;

    FILE* nes_file = nes_fopen(file_path, "rb");
    if (!nes_file){
        goto error;
    } 
    nes = (nes_t *)nes_malloc(sizeof(nes_t));
    if (nes == NULL) {
        goto error;
    }
    memset(nes, 0, sizeof(nes_t));

#if (NES_USE_SRAM == 1)
    nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
#endif
    if (nes_fread(&nes_header_info, sizeof(nes_header_info), 1, nes_file)) {
        if ( nes_memcmp( nes_header_info.identification, "NES\x1a", 4 )){
            goto error;
        }
        if (nes_header_info.trainer){
#if (NES_USE_SRAM == 1)
            if (nes_fread(nes->nes_rom.sram, TRAINER_SIZE, 1, nes_file)==0){
                goto error;
            }
#else
            nes_fseek(nes_file, TRAINER_SIZE, SEEK_CUR);
#endif
        }
        nes->nes_rom.prg_rom_size = ((nes_header_info.prg_rom_size_m << 8) & 0xF00) | nes_header_info.prg_rom_size_l;
        nes->nes_rom.chr_rom_size = ((nes_header_info.prg_rom_size_m << 8) & 0xF00) | nes_header_info.chr_rom_size_l;
        nes->nes_rom.mapper_number = ((nes_header_info.mapper_number_h << 8) & 0xF00) | ((nes_header_info.mapper_number_m << 4) & 0xF0) | (nes_header_info.mapper_number_l & 0x0F);
        nes->nes_rom.mirroring_type = (nes_header_info.mirroring);
        nes->nes_rom.four_screen = (nes_header_info.four_screen);
        nes->nes_rom.save_ram = (nes_header_info.save);

        nes->nes_rom.prg_rom = (uint8_t*)nes_malloc(PRG_ROM_UNIT_SIZE * nes->nes_rom.prg_rom_size);
        if (nes->nes_rom.prg_rom == NULL) {
            goto error;
        }
        if (nes_fread(nes->nes_rom.prg_rom, PRG_ROM_UNIT_SIZE, nes->nes_rom.prg_rom_size, nes_file)==0){
            goto error;
        }
        nes->nes_rom.chr_rom = (uint8_t*)nes_malloc(CHR_ROM_UNIT_SIZE * (nes->nes_rom.chr_rom_size ? nes->nes_rom.chr_rom_size : 1));
        if (nes->nes_rom.chr_rom == NULL) {
            goto error;
        }
        if (nes->nes_rom.chr_rom_size){
            if (nes_fread(nes->nes_rom.chr_rom, CHR_ROM_UNIT_SIZE, (nes->nes_rom.chr_rom_size), nes_file)==0){
                goto error;
            }
        }
    }else{
        goto error;
    }
    nes_fclose(nes_file);
    nes_init(nes);
    nes_load_mapper(nes);
    nes->nes_mapper.mapper_init(nes);
    return nes;
error:
    if (nes_file){
        nes_fclose(nes_file);
    }
    if (nes){
        nes_rom_free(nes);
    }
    return NULL;
}
#endif

// release
int nes_rom_free(nes_t* nes){
    if (nes->nes_rom.prg_rom){
        nes_free(nes->nes_rom.prg_rom);
    }
    if (nes->nes_rom.chr_rom){
        nes_free(nes->nes_rom.chr_rom);
    }
    if (nes->nes_rom.sram){
        nes_free(nes->nes_rom.sram);
    }
    if (nes){
        nes_free(nes);
    }
    return NES_OK;
}

nes_t* nes_load_rom(const uint8_t* nes_rom){
    nes_t* nes = (nes_t *)nes_malloc(sizeof(nes_t));
    if (nes == NULL) {
        goto error;
    }
    memset(nes, 0, sizeof(nes_t));

    nes_header_info_t* nes_header_info = (nes_header_info_t*)nes_rom;

#if (NES_USE_SRAM == 1)
    nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
#endif
        if ( nes_memcmp( nes_header_info->identification, "NES\x1a", 4 )){
            goto error;
        }
        uint8_t* nes_bin = nes_rom + sizeof(nes_header_info_t);
        if (nes_header_info->trainer){
#if (NES_USE_SRAM == 1)
#else
#endif
            nes_bin += TRAINER_SIZE;
        }
        nes->nes_rom.prg_rom_size = ((nes_header_info->prg_rom_size_m << 8) & 0xF00) | nes_header_info->prg_rom_size_l;
        nes->nes_rom.chr_rom_size = ((nes_header_info->prg_rom_size_m << 8) & 0xF00) | nes_header_info->chr_rom_size_l;
        nes->nes_rom.mapper_number = ((nes_header_info->mapper_number_h << 8) & 0xF00) | ((nes_header_info->mapper_number_m << 4) & 0xF0) | (nes_header_info->mapper_number_l & 0x0F);
        nes->nes_rom.mirroring_type = (nes_header_info->mirroring);
        nes->nes_rom.four_screen = (nes_header_info->four_screen);
        nes->nes_rom.save_ram = (nes_header_info->save);

        nes->nes_rom.prg_rom = nes_bin;
        nes_bin += PRG_ROM_UNIT_SIZE * nes->nes_rom.prg_rom_size;

        if (nes->nes_rom.chr_rom_size){
            nes->nes_rom.chr_rom = nes_bin;
        }
    nes_init(nes);
    nes_load_mapper(nes);
    nes->nes_mapper.mapper_init(nes);
    return nes;
error:
    if (nes){
        nes_rom_free(nes);
    }
    return NULL;
}


