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

/* https://www.nesdev.org/wiki/INES_Mapper_159
 * Mapper 159 — Bandai LZ93D50 with 24C01 EEPROM.
 * CHR 1KB × 8 banks, PRG 16KB × 2 banks, CPU-cycle IRQ.
 */

typedef struct {
    uint8_t chr[8];
    uint8_t prg;
    uint8_t irq_enable;
    uint16_t irq_counter;
    uint16_t irq_latch;
    uint8_t prg_bank_count;
    uint16_t chr_bank_count;
    uint8_t eeprom[0x80];
    uint8_t eeprom_state;
    uint8_t eeprom_word;
    uint8_t eeprom_shift;
    uint8_t eeprom_bit_count;
    uint8_t eeprom_scl;
    uint8_t eeprom_sda;
    uint8_t eeprom_out;
} mapper159_t;

enum {
    MAPPER159_EEPROM_STANDBY = 0,
    MAPPER159_EEPROM_ADDRESS,
    MAPPER159_EEPROM_WRITE,
    MAPPER159_EEPROM_READ
};

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper159_update_banks(nes_t* nes) {
    mapper159_t* m = (mapper159_t*)nes->nes_mapper.mapper_register;
    uint8_t prg16 = (uint8_t)(m->prg_bank_count / 2u);
    if (prg16 == 0u) prg16 = 1u;
    nes_load_prgrom_16k(nes, 0, (uint16_t)(m->prg % prg16));
    nes_load_prgrom_16k(nes, 1, (uint16_t)(prg16 - 1u));
    if (m->chr_bank_count > 0u) {
        for (uint8_t i = 0u; i < 8u; i++) {
            nes_load_chrrom_1k(nes, i, (uint16_t)(m->chr[i] % m->chr_bank_count));
        }
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper159_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper159_t* m = (mapper159_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper159_t));
    nes_memset(m->eeprom, 0xFF, sizeof(m->eeprom));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper159_update_banks(nes);
    nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);
}

static void mapper159_eeprom_start(mapper159_t* m) {
    m->eeprom_state = MAPPER159_EEPROM_ADDRESS;
    m->eeprom_word = 0;
    m->eeprom_shift = 0;
    m->eeprom_bit_count = 0;
}

static void mapper159_eeprom_write(mapper159_t* m, uint8_t data) {
    const uint8_t scl = (data >> 5u) & 0x01u;
    const uint8_t sda = (data >> 6u) & 0x01u;

    if (m->eeprom_scl && scl) {
        if (m->eeprom_sda && !sda) {
            mapper159_eeprom_start(m);
        } else if (!m->eeprom_sda && sda) {
            m->eeprom_state = MAPPER159_EEPROM_STANDBY;
        }
    } else if (!m->eeprom_scl && scl) {
        switch (m->eeprom_state) {
        case MAPPER159_EEPROM_ADDRESS:
            if (m->eeprom_bit_count < 7u) {
                m->eeprom_word = (uint8_t)(((m->eeprom_word << 1u) | sda) & 0x7Fu);
            } else {
                if (sda) {
                    m->eeprom_state = MAPPER159_EEPROM_READ;
                } else {
                    m->eeprom_state = MAPPER159_EEPROM_WRITE;
                }
            }
            m->eeprom_bit_count++;
            break;
        case MAPPER159_EEPROM_WRITE:
            if (m->eeprom_bit_count == 8u) {
                m->eeprom_out = 0;
                m->eeprom_shift = 0;
                m->eeprom_bit_count = 0;
            } else {
                m->eeprom_shift = (uint8_t)((m->eeprom_shift << 1u) | sda);
                if (++m->eeprom_bit_count == 8u) {
                    m->eeprom[m->eeprom_word] = m->eeprom_shift;
                    m->eeprom_word = (m->eeprom_word + 1u) & 0x7Fu;
                }
            }
            break;
        case MAPPER159_EEPROM_READ:
            if (m->eeprom_bit_count == 8u) {
                m->eeprom_out = 0;
                m->eeprom_shift = m->eeprom[m->eeprom_word];
                m->eeprom_word = (m->eeprom_word + 1u) & 0x7Fu;
                m->eeprom_bit_count = 0;
            } else {
                m->eeprom_out = (m->eeprom_shift >> 7u) & 0x01u;
                m->eeprom_shift <<= 1u;
                m->eeprom_bit_count++;
            }
            break;
        default:
            break;
        }
    }

    m->eeprom_scl = scl;
    m->eeprom_sda = sda;
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper159_t* m = (mapper159_t*)nes->nes_mapper.mapper_register;
    uint8_t reg = (uint8_t)(address & 0x0Fu);

    /* Bandai FCG/LZ93D50 register layout, mirrored through $6000-$FFFF:
     * $x0-$x7 CHR, $x8 PRG, $x9 mirroring, $xA IRQ control,
     * $xB/$xC IRQ latch, $xD 24C01 serial EEPROM.
     */
    switch (reg) {
    case 0u: case 1u: case 2u: case 3u:
    case 4u: case 5u: case 6u: case 7u:
        m->chr[reg] = data;
        mapper159_update_banks(nes);
        break;
    case 8u:
        m->prg = data & 0x0Fu;
        mapper159_update_banks(nes);
        break;
    case 9u:
        switch (data & 0x03u) {
        case 0u: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);    break;
        case 1u: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);  break;
        case 2u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0); break;
        case 3u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1); break;
        }
        break;
    case 10u:
        m->irq_enable  = data & 0x01u;
        m->irq_counter = m->irq_latch;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 11u: m->irq_latch = (uint16_t)((m->irq_latch & 0xFF00u) | data); break;
    case 12u: m->irq_latch = (uint16_t)((m->irq_latch & 0x00FFu) | ((uint16_t)data << 8u)); break;
    case 13u:
        mapper159_eeprom_write(m, data);
        break;
    default: break;
    }
}

static uint8_t nes_mapper_read_sram(nes_t* nes, uint16_t address) {
    (void)address;
    mapper159_t* m = (mapper159_t*)nes->nes_mapper.mapper_register;
    return (uint8_t)(0xE7u | (m->eeprom_out << 4u));
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper159_t* m = (mapper159_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enable) return;
    if (m->irq_counter <= (uint16_t)cycles) {
        m->irq_counter = 0u;
        m->irq_enable  = 0u;
        nes_cpu_irq(nes);
    } else {
        m->irq_counter = (uint16_t)(m->irq_counter - cycles);
    }
}

int nes_mapper159_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_sram      = nes_mapper_write;
    nes->nes_mapper.mapper_read_sram = nes_mapper_read_sram;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}
