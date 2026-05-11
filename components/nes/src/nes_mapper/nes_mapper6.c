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

/* https://www.nesdev.org/wiki/INES_Mapper_006 */

typedef struct {
    uint8_t latch;
    uint8_t mirroring;
    uint8_t irq_enabled;
    uint8_t ffe_alt_mode;
    uint16_t irq_counter;
} mapper6_register_t;


static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper6_update_mirroring(nes_t* nes) {
    mapper6_register_t* mapper_reg = (mapper6_register_t*)nes->nes_mapper.mapper_register;
    switch (mapper_reg->mirroring) {
        case 0:
            nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0);
            break;
        case 1:
            nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1);
            break;
        case 2:
            nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);
            break;
        default:
            nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);
            break;
    }
}

static int mapper6_ensure_chr_ram(nes_t* nes) {
    if (nes->nes_rom.chr_rom_size != 0) {
        return NES_OK;
    }

    if (nes->nes_rom.chr_rom) {
        nes_free(nes->nes_rom.chr_rom);
        nes->nes_rom.chr_rom = NULL;
    }

    nes->nes_rom.chr_rom = (uint8_t*)nes_malloc(0x8000);
    if (nes->nes_rom.chr_rom == NULL) {
        NES_LOG_ERROR("mapper:006 failed to allocate CHR-RAM\n");
        return NES_ERROR;
    }

    nes_memset(nes->nes_rom.chr_rom, 0, 0x8000);
    return NES_OK;
}

static void mapper6_update_prg(nes_t* nes) {
    mapper6_register_t* mapper_reg = (mapper6_register_t*)nes->nes_mapper.mapper_register;
    uint16_t prg_bank_count = nes->nes_rom.prg_rom_size ? nes->nes_rom.prg_rom_size : 1;
    uint16_t switch_bank = (uint16_t)((mapper_reg->latch >> 2) % prg_bank_count);
    uint16_t fixed_bank = (uint16_t)(prg_bank_count - 1);

    nes_load_prgrom_16k(nes, 0, switch_bank);
    nes_load_prgrom_16k(nes, 1, fixed_bank);
}

static void mapper6_update_chr(nes_t* nes) {
    mapper6_register_t* mapper_reg = (mapper6_register_t*)nes->nes_mapper.mapper_register;
    uint8_t chr_bank = mapper_reg->latch & 0x03;

    if (nes->nes_rom.chr_rom_size) {
        nes_load_chrrom_8k(nes, 0, chr_bank % nes->nes_rom.chr_rom_size);
        return;
    }

    for (int i = 0; i < 8; i++) {
        nes->nes_ppu.pattern_table[i] = nes->nes_rom.chr_rom + ((uint32_t)chr_bank * 0x2000) + ((uint32_t)i * 1024);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper6_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper6_register_t* mapper_reg = (mapper6_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(mapper_reg, 0, sizeof(*mapper_reg));

    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        }
    }

    if (mapper6_ensure_chr_ram(nes) != NES_OK) {
        return;
    }

    mapper_reg->ffe_alt_mode = 1;
    mapper_reg->mirroring = nes->nes_rom.mirroring_type ? 2 : 3;
    mapper_reg->latch = 0;

    mapper6_update_prg(nes);
    mapper6_update_chr(nes);
    mapper6_update_mirroring(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper6_register_t* mapper_reg = (mapper6_register_t*)nes->nes_mapper.mapper_register;
    (void)address;

    mapper_reg->latch = data;
    mapper6_update_prg(nes);
    mapper6_update_chr(nes);
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper6_register_t* mapper_reg = (mapper6_register_t*)nes->nes_mapper.mapper_register;
    switch (address) {
        case 0x42FE:
            mapper_reg->ffe_alt_mode = (data & 0x80) == 0;
            mapper_reg->mirroring = (data & 0x10) ? 1 : 0;
            mapper6_update_mirroring(nes);
            break;
        case 0x42FF:
            mapper_reg->mirroring = (data & 0x10) ? 3 : 2;
            mapper6_update_mirroring(nes);
            break;
        case 0x4501:
            mapper_reg->irq_enabled = 0;
            nes->nes_cpu.irq_pending = 0;
            break;
        case 0x4502:
            mapper_reg->irq_counter = (mapper_reg->irq_counter & 0xFF00) | data;
            nes->nes_cpu.irq_pending = 0;
            break;
        case 0x4503:
            mapper_reg->irq_counter = (mapper_reg->irq_counter & 0x00FF) | ((uint16_t)data << 8);
            mapper_reg->irq_enabled = 1;
            nes->nes_cpu.irq_pending = 0;
            break;
        default:
            break;
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper6_register_t* mapper_reg = (mapper6_register_t*)nes->nes_mapper.mapper_register;
    if (!mapper_reg->irq_enabled) {
        return;
    }

    if ((uint32_t)mapper_reg->irq_counter + cycles >= 0x10000UL) {
        mapper_reg->irq_counter = (uint16_t)(mapper_reg->irq_counter + cycles);
        mapper_reg->irq_enabled = 0;
        nes_cpu_irq(nes);
        return;
    }

    mapper_reg->irq_counter = (uint16_t)(mapper_reg->irq_counter + cycles);
}

int nes_mapper6_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    nes->nes_mapper.mapper_apu = nes_mapper_apu;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return 0;
}