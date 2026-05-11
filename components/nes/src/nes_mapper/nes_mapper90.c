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

// https://www.nesdev.org/wiki/INES_Mapper_090

#include "nes.h"

typedef struct {
    uint8_t prg[4];
    uint8_t chr[8];
    uint8_t prg_mode;
    uint8_t chr_mode;
    uint8_t mirror;
    uint8_t misc;
    uint8_t irq_enable;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper90_register_t;

static void mapper90_update_prg(nes_t* nes) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    uint8_t last  = r->prg_bank_count - 1u;
    uint8_t slast = r->prg_bank_count - 2u;
    switch (r->prg_mode & 0x03u) {
    case 0u: /* 4x8KB */
        nes_load_prgrom_8k(nes, 0, r->prg[0] % r->prg_bank_count);
        nes_load_prgrom_8k(nes, 1, r->prg[1] % r->prg_bank_count);
        nes_load_prgrom_8k(nes, 2, r->prg[2] % r->prg_bank_count);
        nes_load_prgrom_8k(nes, 3, r->prg[3] % r->prg_bank_count);
        break;
    case 1u: { /* 2x16KB */
        uint16_t banks16 = (uint16_t)(r->prg_bank_count / 2u);
        if (banks16 == 0u) banks16 = 1u;
        nes_load_prgrom_16k(nes, 0, (uint16_t)(r->prg[0] % banks16));
        nes_load_prgrom_16k(nes, 1, (uint16_t)(r->prg[2] % banks16));
        break;
    }
    case 2u: { /* 1x32KB */
        uint16_t banks32 = (uint16_t)(r->prg_bank_count / 4u);
        if (banks32 == 0u) banks32 = 1u;
        nes_load_prgrom_32k(nes, 0, (uint16_t)(r->prg[0] % banks32));
        break;
    }
    case 3u: /* 1x16KB at $8000 + fixed last at $C000 */
    default: {
        uint16_t banks16 = (uint16_t)(r->prg_bank_count / 2u);
        if (banks16 == 0u) banks16 = 1u;
        nes_load_prgrom_16k(nes, 0, (uint16_t)(r->prg[1] % banks16));
        nes_load_prgrom_8k(nes, 2, slast);
        nes_load_prgrom_8k(nes, 3, last);
        break;
    }
    }
}

static void mapper90_update_chr(nes_t* nes) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    if (r->chr_bank_count == 0u) return;
    uint8_t i;
    switch (r->chr_mode & 0x03u) {
    case 0u: /* 8x1KB */
        for (i = 0u; i < 8u; i++)
            nes_load_chrrom_1k(nes, i, (uint8_t)(r->chr[i] % r->chr_bank_count));
        break;
    case 1u: /* 4x2KB */
        for (i = 0u; i < 4u; i++) {
            uint8_t b = (uint8_t)((r->chr[i * 2u] & 0xFEu) % r->chr_bank_count);
            nes_load_chrrom_1k(nes, (uint8_t)(i * 2u),       b);
            nes_load_chrrom_1k(nes, (uint8_t)(i * 2u + 1u), (uint8_t)((b + 1u) % r->chr_bank_count));
        }
        break;
    case 2u: /* 2x4KB */
        for (i = 0u; i < 4u; i++) {
            nes_load_chrrom_1k(nes, i,              (uint8_t)((r->chr[0] * 4u + i) % r->chr_bank_count));
            nes_load_chrrom_1k(nes, (uint8_t)(i + 4u), (uint8_t)((r->chr[4] * 4u + i) % r->chr_bank_count));
        }
        break;
    case 3u: /* 1x8KB */
    default:
        for (i = 0u; i < 8u; i++)
            nes_load_chrrom_1k(nes, i, (uint8_t)((r->chr[0] * 8u + i) % r->chr_bank_count));
        break;
    }
}

static const nes_mirror_type_t jy_mirror_table[4] = {
    NES_MIRROR_VERTICAL,
    NES_MIRROR_HORIZONTAL,
    NES_MIRROR_ONE_SCREEN0,
    NES_MIRROR_ONE_SCREEN1,
};

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000u) {
    case 0x8000u:
        r->prg[address & 0x03u] = data & 0x1Fu;
        mapper90_update_prg(nes);
        break;
    case 0x9000u:
        r->chr[address & 0x07u] = data;
        mapper90_update_chr(nes);
        break;
    case 0xA000u:
        switch (address & 0x03u) {
        case 0u:
            r->irq_enable = data & 0x01u;
            if (r->irq_enable) r->irq_counter = r->irq_latch;
            if (!r->irq_enable) nes->nes_cpu.irq_pending = 0;
            break;
        case 1u: r->irq_latch = data; break;
        case 2u: break; /* prescaler — ignored */
        case 3u:
            r->irq_enable = 0u;
            nes->nes_cpu.irq_pending = 0;
            break;
        }
        break;
    case 0xF000u:
        switch (address & 0x03u) {
        case 0u:
            r->prg_mode = data & 0x03u;
            mapper90_update_prg(nes);
            break;
        case 1u:
            r->chr_mode = data & 0x03u;
            mapper90_update_chr(nes);
            break;
        case 2u:
            r->mirror = data & 0x03u;
            if (nes->nes_rom.four_screen == 0)
                nes_ppu_screen_mirrors(nes, jy_mirror_table[r->mirror]);
            break;
        case 3u: r->misc = data; break;
        }
        break;
    default: break;
    }
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;
    if (r->irq_counter == 0u) {
        r->irq_counter = r->irq_latch;
        nes_cpu_irq(nes);
    } else {
        r->irq_counter--;
    }
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper90_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper90_register_t));

    r->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    r->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);

    /* Default: 4x8KB PRG mode */
    r->prg[0] = 0u;
    r->prg[1] = 1u;
    r->prg[2] = r->prg_bank_count >= 2u ? r->prg_bank_count - 2u : 0u;
    r->prg[3] = r->prg_bank_count >= 1u ? r->prg_bank_count - 1u : 0u;

    mapper90_update_prg(nes);

    if (r->chr_bank_count == 0u) {
        nes_load_chrrom_8k(nes, 0, 0);
    } else {
        mapper90_update_chr(nes);
    }
}

int nes_mapper90_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}
