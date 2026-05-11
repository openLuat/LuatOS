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

/*
 * iNES Mapper 031 - NSF-like homebrew mapper
 * https://www.nesdev.org/wiki/INES_Mapper_031
 *
 * PRG ROM: up to 1MB, banked in 4KB pages
 * CHR: 8KB RAM
 *
 * Bank select registers at $5FF8-$5FFF:
 *   $5FF8: Select 4KB PRG page at $8000-$8FFF
 *   $5FF9: Select 4KB PRG page at $9000-$9FFF
 *   $5FFA: Select 4KB PRG page at $A000-$AFFF
 *   $5FFB: Select 4KB PRG page at $B000-$BFFF
 *   $5FFC: Select 4KB PRG page at $C000-$CFFF
 *   $5FFD: Select 4KB PRG page at $D000-$DFFF
 *   $5FFE: Select 4KB PRG page at $E000-$EFFF
 *   $5FFF: Select 4KB PRG page at $F000-$FFFF
 *
 * Since the CPU uses 8KB bank pointers (prg_banks[0..3]), a 32KB staging
 * buffer is used. Each 4KB bank switch copies data into the buffer so that
 * two non-contiguous 4KB pages can share one 8KB window.
 */

typedef struct {
    uint8_t  regs[8];           /* 4KB bank registers */
    uint8_t  prg_buf[32768];    /* 32KB PRG staging buffer */
} mapper31_state_t;

static mapper31_state_t* mapper31_get(nes_t* nes) {
    return (mapper31_state_t*)nes->nes_mapper.mapper_register;
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper31_load_4k(nes_t* nes, uint8_t slot, uint8_t page) {
    mapper31_state_t* state = mapper31_get(nes);
    uint32_t prg_4k_count = (uint32_t)nes->nes_rom.prg_rom_size * 4;
    uint32_t idx = page % prg_4k_count;
    state->regs[slot] = page;
#if (NES_ROM_STREAM == 1)
    nes_fseek(nes->nes_rom.rom_file,
              nes->nes_rom.prg_data_offset + (long)4096 * idx, SEEK_SET);
    nes_fread(state->prg_buf + (uint32_t)slot * 4096, 4096, 1,
              nes->nes_rom.rom_file);
#else
    nes_memcpy(state->prg_buf + (uint32_t)slot * 4096,
               nes->nes_rom.prg_rom + (uint32_t)idx * 4096, 4096);
#endif
}

static void mapper31_sync_banks(nes_t* nes) {
    mapper31_state_t* state = mapper31_get(nes);
    nes->nes_cpu.prg_banks[0] = state->prg_buf;
    nes->nes_cpu.prg_banks[1] = state->prg_buf + 8192;
    nes->nes_cpu.prg_banks[2] = state->prg_buf + 16384;
    nes->nes_cpu.prg_banks[3] = state->prg_buf + 24576;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper31_state_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_memset(nes->nes_mapper.mapper_register, 0, sizeof(mapper31_state_t));
    uint32_t prg_4k_count = (uint32_t)nes->nes_rom.prg_rom_size * 4;

    /* Init: map last 32KB of PRG (wraps for small ROMs) */
    for (int i = 0; i < 8; i++) {
        uint32_t page = (prg_4k_count - 8 + i) % prg_4k_count;
        mapper31_load_4k(nes, (uint8_t)i, (uint8_t)page);
    }

    mapper31_sync_banks(nes);

    /* CHR: 8KB RAM */
    nes_load_chrrom_8k(nes, 0, 0);
}

/* $5FF8-$5FFF: bank select registers, mirrored throughout $5000-$5FFF */
static void nes_mapper_apu_write(nes_t* nes, uint16_t address, uint8_t data) {
    if (address >= 0x5000 && address <= 0x5FFF) {
        uint8_t slot = (uint8_t)(address & 0x07);
        mapper31_load_4k(nes, slot, data);
        mapper31_sync_banks(nes);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)nes;
    (void)address;
    (void)data;
}

int nes_mapper31_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    nes->nes_mapper.mapper_apu = nes_mapper_apu_write;
    return 0;
}
