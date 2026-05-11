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
 * https://www.nesdev.org/wiki/INES_Mapper_115
 * Waixing mapper 115 — MMC3 variant where CHR bank values 66 and 67
 * redirect to 1KB pages within an embedded 2KB CHR-RAM buffer instead
 * of CHR-ROM.  All other behaviour is identical to MMC3 (mapper 4).
 */

#define MAPPER115_CHR_RAM_SIZE 2048u

typedef struct {
    uint8_t bank_select;
    uint8_t bank_values[8]; /* R0-R7 */
    uint8_t mirroring;
    uint8_t prg_ram_protect;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_reload;
    uint8_t irq_enabled;
    uint8_t prg_bank_count; /* number of 8KB PRG banks */
    uint8_t chr_bank_count; /* number of 1KB CHR-ROM banks */
    uint8_t chr_ram[MAPPER115_CHR_RAM_SIZE]; /* 2KB CHR-RAM for bank values 66 and 67 */
} nes_mapper115_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

/*
 * Load a single 1KB CHR slot.  Bank values 66 and 67 map to the first and
 * second 1KB page of the embedded chr_ram; all other values use CHR-ROM.
 */
static void mapper115_load_chr1k(nes_t* nes, nes_mapper115_t* m, uint8_t slot, uint8_t bank) {
    if (bank == 66u || bank == 67u) {
        nes->nes_ppu.pattern_table[slot] = m->chr_ram + (bank - 66u) * 1024u;
    } else if (m->chr_bank_count > 0) {
        nes_load_chrrom_1k(nes, slot, bank % m->chr_bank_count);
    }
}

static void mapper115_update_banks(nes_t* nes) {
    nes_mapper115_t* m = (nes_mapper115_t*)nes->nes_mapper.mapper_register;
    uint8_t prg_mode = (m->bank_select >> 6) & 1u;
    uint8_t chr_mode = (m->bank_select >> 7) & 1u;
    uint8_t last     = m->prg_bank_count - 1u;
    uint8_t slast    = m->prg_bank_count - 2u;

    /* PRG banking (same as MMC3) */
    if (prg_mode == 0u) {
        nes_load_prgrom_8k(nes, 0, m->bank_values[6] % m->prg_bank_count);
        nes_load_prgrom_8k(nes, 1, m->bank_values[7] % m->prg_bank_count);
        nes_load_prgrom_8k(nes, 2, slast);
        nes_load_prgrom_8k(nes, 3, last);
    } else {
        nes_load_prgrom_8k(nes, 0, slast);
        nes_load_prgrom_8k(nes, 1, m->bank_values[7] % m->prg_bank_count);
        nes_load_prgrom_8k(nes, 2, m->bank_values[6] % m->prg_bank_count);
        nes_load_prgrom_8k(nes, 3, last);
    }

    /* CHR banking with CHR-RAM override for banks 66/67 */
    if (chr_mode == 0u) {
        mapper115_load_chr1k(nes, m, 0, m->bank_values[0] & 0xFEu);
        mapper115_load_chr1k(nes, m, 1, m->bank_values[0] | 0x01u);
        mapper115_load_chr1k(nes, m, 2, m->bank_values[1] & 0xFEu);
        mapper115_load_chr1k(nes, m, 3, m->bank_values[1] | 0x01u);
        mapper115_load_chr1k(nes, m, 4, m->bank_values[2]);
        mapper115_load_chr1k(nes, m, 5, m->bank_values[3]);
        mapper115_load_chr1k(nes, m, 6, m->bank_values[4]);
        mapper115_load_chr1k(nes, m, 7, m->bank_values[5]);
    } else {
        mapper115_load_chr1k(nes, m, 0, m->bank_values[2]);
        mapper115_load_chr1k(nes, m, 1, m->bank_values[3]);
        mapper115_load_chr1k(nes, m, 2, m->bank_values[4]);
        mapper115_load_chr1k(nes, m, 3, m->bank_values[5]);
        mapper115_load_chr1k(nes, m, 4, m->bank_values[0] & 0xFEu);
        mapper115_load_chr1k(nes, m, 5, m->bank_values[0] | 0x01u);
        mapper115_load_chr1k(nes, m, 6, m->bank_values[1] & 0xFEu);
        mapper115_load_chr1k(nes, m, 7, m->bank_values[1] | 0x01u);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper115_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper115_t* m = (nes_mapper115_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(nes_mapper115_t));

    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);

    m->bank_values[6] = 0;
    m->bank_values[7] = 1;

    mapper115_update_banks(nes);
}

/*
 * Register map identical to MMC3:
 *   $8000 (even): bank select  $8001 (odd): bank data
 *   $A000 (even): mirroring    $A001 (odd): PRG RAM protect (ignored)
 *   $C000 (even): IRQ latch    $C001 (odd): IRQ reload
 *   $E000 (even): IRQ disable  $E001 (odd): IRQ enable
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper115_t* m = (nes_mapper115_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE001u) {
    case 0x8000u:
        m->bank_select = data;
        mapper115_update_banks(nes);
        break;
    case 0x8001u: {
        uint8_t reg = m->bank_select & 0x07u;
        m->bank_values[reg] = data;
        mapper115_update_banks(nes);
        break;
    }
    case 0xA000u:
        m->mirroring = data & 0x01u;
        if (nes->nes_rom.four_screen == 0) {
            nes_ppu_screen_mirrors(nes, m->mirroring ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        }
        break;
    case 0xA001u:
        m->prg_ram_protect = data;
        break;
    case 0xC000u:
        m->irq_latch = data;
        break;
    case 0xC001u:
        m->irq_reload = 1u;
        break;
    case 0xE000u:
        m->irq_enabled = 0u;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0xE001u:
        m->irq_enabled = 1u;
        break;
    default:
        break;
    }
}

/* Scanline IRQ — identical to MMC3. */
static void nes_mapper_hsync(nes_t* nes) {
    nes_mapper115_t* m = (nes_mapper115_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;

    if (m->irq_counter == 0 || m->irq_reload) {
        m->irq_counter = m->irq_latch;
    } else {
        m->irq_counter--;
    }

    if (m->irq_counter == 0 && m->irq_enabled) {
        nes_cpu_irq(nes);
    }

    m->irq_reload = 0;
}

int nes_mapper115_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}
