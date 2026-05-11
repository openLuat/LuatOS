/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "nes.h"

static uint32_t nes_crc32_update(uint32_t crc, const uint8_t* data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int j = 0; j < 8; j++)
            crc = (crc >> 1u) ^ (0xEDB88320u & (uint32_t)(-(int32_t)(crc & 1u)));
    }
    return crc;
}

typedef struct { uint32_t crc32; uint16_t mapper; } nes_romdb_entry_t;

/* PRG+CHR CRC32 table — corrects ROMs with wrong mapper in iNES header */
static const nes_romdb_entry_t romdb[] = {
    /* Arkanoid II (J) [!] — header says mapper 70, actually Taito TC0190FMC (mapper 33) */
    { 0x0F141525u, 33u },
    /* Super Mario Bros.+Tetris+Nintendo World Cup (E) [!] — header says mapper 4, actually PAL-ZZ (mapper 37) */
    { 0x73298C87u, 37u },
    /* Death Race (U) [!] — header says mapper 11, actual hardware is AGCI PCB (mapper 144).
       PRG fixed to last 32KB (bank1); CHR switched via upper nibble of write data.
       mapper11 breaks: PRG-switch at $804C sends CPU to bank0 whose NMI handler
       never enables PPUMASK. mapper3 (CNROM bus-conflict) gives wrong CHR banks.
       mapper144 = fixed PRG last bank + CHR via bits[7:4], which is the correct behavior. */
    { 0x5CAA3E61u, 144u },
};

static void nes_romdb_lookup(nes_t* nes) {
    if (nes->nes_rom.prg_rom == NULL) return;
    size_t prg_len = (size_t)PRG_ROM_UNIT_SIZE * nes->nes_rom.prg_rom_size;
    size_t chr_len = (size_t)CHR_ROM_UNIT_SIZE * nes->nes_rom.chr_rom_size;
    uint32_t c = 0xFFFFFFFFu;
    c = nes_crc32_update(c, nes->nes_rom.prg_rom, prg_len);
    if (chr_len > 0u && nes->nes_rom.chr_rom != NULL)
        c = nes_crc32_update(c, nes->nes_rom.chr_rom, chr_len);
    uint32_t crc = c ^ 0xFFFFFFFFu;
    nes->nes_rom.rom_crc = crc;
    for (size_t i = 0; i < sizeof(romdb) / sizeof(romdb[0]); i++) {
        if (romdb[i].crc32 == crc) {
            NES_LOG_INFO("romdb: CRC32=%08X mapper %d->%d\n",
                         crc, nes->nes_rom.mapper_number, romdb[i].mapper);
            nes->nes_rom.mapper_number = romdb[i].mapper;
            return;
        }
    }
}

#if (NES_USE_FS == 1)
int nes_load_file(nes_t* nes, const char* file_path ){
    nes_header_ines_t nes_header_info = {0};

    void* nes_file = nes_fopen(file_path, "rb");
    if (nes_file == NULL){
        NES_LOG_ERROR("nes_load_file: failed to open file %s\n", file_path);
        goto error;
    }
#if (NES_USE_SRAM == 1)
    nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
    if (nes->nes_rom.sram == NULL) {
        goto error;
    }
    nes_memset(nes->nes_rom.sram, 0x00, SRAM_SIZE);
#endif
    if (nes_fread(&nes_header_info, sizeof(nes_header_info), 1, nes_file)) {
        if (nes_memcmp(nes_header_info.identification, "NES\x1a", 4)){
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
        if (nes_header_info.identifier==2){ //NES 2.0
            nes_header_nes2_t* nes2_header_info = (nes_header_nes2_t*)&nes_header_info;
            nes->nes_rom.prg_rom_size = ((nes2_header_info->prg_rom_size_m << 8) & 0xF00) | nes2_header_info->prg_rom_size_l;
            nes->nes_rom.chr_rom_size = ((nes2_header_info->chr_rom_size_m << 8) & 0xF00) | nes2_header_info->chr_rom_size_l;
            nes->nes_rom.mapper_number = ((nes2_header_info->mapper_number_h << 8) & 0xF00) | ((nes2_header_info->mapper_number_m << 4) & 0xF0) | (nes2_header_info->mapper_number_l & 0x0F);

        }else{  //INES
            nes_header_ines_t* ines_header_info = (nes_header_ines_t*)&nes_header_info;
            nes->nes_rom.prg_rom_size = ines_header_info->prg_rom_size;
            nes->nes_rom.chr_rom_size = ines_header_info->chr_rom_size;
            /* Detect dirty iNES header: if bytes 12-15 are not all zero, ignore upper mapper nibble */
            if (ines_header_info->Reserved[1] | ines_header_info->Reserved[2] | ines_header_info->Reserved[3] | ines_header_info->Reserved[4]) {
                nes->nes_rom.mapper_number = ines_header_info->mapper_number_l;
            } else {
                nes->nes_rom.mapper_number = ines_header_info->mapper_number_l | ines_header_info->mapper_number_h << 4;
            }
        }
        nes->nes_rom.mirroring_type = nes_header_info.mirroring;
        nes->nes_rom.four_screen = nes_header_info.four_screen;
        nes->nes_rom.save_ram = nes_header_info.save;
#if (NES_ROM_STREAM == 1)
        /* Stream mode: only allocate LRU cache buffers, keep file open */
        nes->nes_rom.prg_data_offset = (long)sizeof(nes_header_info) + (nes_header_info.trainer ? TRAINER_SIZE : 0);
        nes->nes_rom.chr_data_offset = nes->nes_rom.prg_data_offset + (long)PRG_ROM_UNIT_SIZE * nes->nes_rom.prg_rom_size;
        /* PRG: NES_PRG_CACHE_SLOTS x 8KB LRU cache */
        nes->nes_rom.prg_rom = (uint8_t*)nes_malloc(8192 * NES_PRG_CACHE_SLOTS);
        if (nes->nes_rom.prg_rom == NULL) {
            goto error;
        }
        nes_memset(nes->nes_rom.prg_rom, 0, 8192 * NES_PRG_CACHE_SLOTS);
        /* CHR: NES_CHR_CACHE_SLOTS x 1KB LRU cache */
        nes->nes_rom.chr_rom = (uint8_t*)nes_malloc(1024 * NES_CHR_CACHE_SLOTS);
        if (nes->nes_rom.chr_rom == NULL) {
            goto error;
        }
        nes_memset(nes->nes_rom.chr_rom, 0, 1024 * NES_CHR_CACHE_SLOTS);
        /* Init LRU cache entries */
        nes->nes_rom.cache_tick = 0;
        for (int i = 0; i < NES_PRG_CACHE_SLOTS; i++) {
            nes->nes_rom.prg_cache[i].tag = 0xFFFF;
            nes->nes_rom.prg_cache[i].last_used = 0;
        }
        for (int i = 0; i < NES_CHR_CACHE_SLOTS; i++) {
            nes->nes_rom.chr_cache[i].tag = 0xFFFF;
            nes->nes_rom.chr_cache[i].last_used = 0;
        }
        /* Keep file handle open for streaming */
        nes->nes_rom.rom_file = nes_file;
        nes_file = NULL;
#else
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
#endif
    }else{
        goto error;
    }
#if (NES_ROM_STREAM != 1)
    nes_fclose(nes_file);
#endif
    nes_cpu_init(nes);
#if (NES_ENABLE_SOUND==1)
    nes_apu_init(nes);
#endif
    nes_ppu_init(nes);
#if (NES_ROM_STREAM != 1)
    nes_romdb_lookup(nes);
#endif
    if(nes_load_mapper(nes)){
        goto error;
    }
    nes->nes_mapper.mapper_init(nes);
    return NES_OK;
error:
    if (nes_file){
        nes_fclose(nes_file);
    }
    if (nes){
        nes_unload_file(nes);
    }
    return NES_ERROR;

}


int nes_unload_file(nes_t* nes){
    if (nes->nes_mapper.mapper_deinit) {
        nes->nes_mapper.mapper_deinit(nes);
    }
#if (NES_ROM_STREAM == 1)
    if (nes->nes_rom.rom_file){
        nes_fclose(nes->nes_rom.rom_file);
        nes->nes_rom.rom_file = NULL;
    }
#endif
    if (nes->nes_rom.prg_rom){
        nes_free(nes->nes_rom.prg_rom);
        nes->nes_rom.prg_rom = NULL;
    }
    if (nes->nes_rom.chr_rom){
        nes_free(nes->nes_rom.chr_rom);
        nes->nes_rom.chr_rom = NULL;
    }
    if (nes->nes_rom.sram){
        nes_free(nes->nes_rom.sram);
        nes->nes_rom.sram = NULL;
    }
    return NES_OK;
}

#endif

int nes_load_rom(nes_t* nes, const uint8_t* nes_rom){
    nes_header_ines_t* nes_header_info = (nes_header_ines_t*)nes_rom;
#if (NES_USE_SRAM == 1)
    nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
    if (nes->nes_rom.sram == NULL) {
        goto error;
    }
    nes_memset(nes->nes_rom.sram, 0x00, SRAM_SIZE);
#endif
    if ( nes_memcmp( nes_header_info->identification, "NES\x1a", 4 )){
        goto error;
    }
    uint8_t* nes_bin = (uint8_t*)nes_rom + sizeof(nes_header_ines_t);
    if (nes_header_info->trainer){
#if (NES_USE_SRAM == 1)
#else
#endif
        nes_bin += TRAINER_SIZE;
    }

    if (nes_header_info->identifier==2){ //NES 2.0
        nes_header_nes2_t* nes2_header_info = (nes_header_nes2_t*)nes_header_info;
        nes->nes_rom.prg_rom_size = ((nes2_header_info->prg_rom_size_m << 8) & 0xF00) | nes2_header_info->prg_rom_size_l;
        nes->nes_rom.chr_rom_size = ((nes2_header_info->chr_rom_size_m << 8) & 0xF00) | nes2_header_info->chr_rom_size_l;
        nes->nes_rom.mapper_number = ((nes2_header_info->mapper_number_h << 8) & 0xF00) | ((nes2_header_info->mapper_number_m << 4) & 0xF0) | (nes2_header_info->mapper_number_l & 0x0F);

    }else{  //INES
        nes_header_ines_t* ines_header_info = (nes_header_ines_t*)nes_header_info;
        nes->nes_rom.prg_rom_size = ines_header_info->prg_rom_size;
        nes->nes_rom.chr_rom_size = ines_header_info->chr_rom_size;
        /* Detect dirty iNES header: if bytes 12-15 are not all zero, ignore upper mapper nibble */
        if (ines_header_info->Reserved[1] | ines_header_info->Reserved[2] | ines_header_info->Reserved[3] | ines_header_info->Reserved[4]) {
            nes->nes_rom.mapper_number = ines_header_info->mapper_number_l;
        } else {
            nes->nes_rom.mapper_number = ines_header_info->mapper_number_l | ines_header_info->mapper_number_h << 4;
        }
    }

    nes->nes_rom.mirroring_type = (nes_header_info->mirroring);
    nes->nes_rom.four_screen = (nes_header_info->four_screen);
    nes->nes_rom.save_ram = (nes_header_info->save);

    nes->nes_rom.prg_rom = nes_bin;
    nes_bin += PRG_ROM_UNIT_SIZE * nes->nes_rom.prg_rom_size;

    if (nes->nes_rom.chr_rom_size){
        nes->nes_rom.chr_rom = nes_bin;
    }
    nes_cpu_init(nes);
#if (NES_ENABLE_SOUND==1)
    nes_apu_init(nes);
#endif
    nes_ppu_init(nes);
    nes_romdb_lookup(nes);
    if(nes_load_mapper(nes)){
        return NES_ERROR;
    }
    nes->nes_mapper.mapper_init(nes);
    return NES_OK;
error:
    if (nes){
        nes_unload_rom(nes);
    }
    return NES_ERROR;
}

int nes_unload_rom(nes_t* nes){
    if (nes->nes_mapper.mapper_deinit) {
        nes->nes_mapper.mapper_deinit(nes);
    }
    if (nes->nes_rom.sram) {
        nes_free(nes->nes_rom.sram);
        nes->nes_rom.sram = NULL;
    }
    return NES_OK;
}
