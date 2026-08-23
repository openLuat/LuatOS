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
 * https://www.nesdev.org/wiki/Sunsoft_mapper_3_(INES_67)
 * Reference: Mesen2 Sunsoft3.h / FCEUX boards/67.cpp
 *
 * Register map (address & 0xF800):
 *   $8800: CHR 2KB slot 0 (PPU $0000-$07FF)
 *   $9800: CHR 2KB slot 1 (PPU $0800-$0FFF)
 *   $A800: CHR 2KB slot 2 (PPU $1000-$17FF)
 *   $B800: CHR 2KB slot 3 (PPU $1800-$1FFF)
 *   $C800: IRQ counter byte — toggles high/low on each write:
 *          first write  (irq_latch=0) → high byte; second write (irq_latch=1) → low byte
 *   $D800: bit[4]=IRQ enable; also ACKs pending IRQ and resets latch toggle
 *   $E800: mirroring  (bits[1:0]: 0=V, 1=H, 2=ONE_SCREEN_A, 3=ONE_SCREEN_B)
 *   $F800: 16KB PRG bank at $8000-$BFFF ($C000-$FFFF fixed to last bank)
 *
 * IRQ: CPU-cycle countdown; fires on 16-bit unsigned underflow (0 → 0xFFFF).
 *      Auto-disables after firing; game re-arms by writing $D800 with bit 4.
 */

typedef struct {
    uint8_t  irq_enable;
    uint8_t  irq_latch;   /* toggle: 0=next $C800 write→high byte, 1→low byte */
    uint16_t irq_counter;
} nes_mapper67_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static inline void mapper67_load_chr2k(nes_t* nes, uint8_t slot, uint8_t bank) {
    uint16_t num_1k = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
    if (num_1k == 0u) return;
    nes_load_chrrom_1k(nes, (uint8_t)(slot * 2u),      (uint16_t)((bank * 2u)      % num_1k));
    nes_load_chrrom_1k(nes, (uint8_t)(slot * 2u + 1u), (uint16_t)((bank * 2u + 1u) % num_1k));
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper67_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper67_t* r = (nes_mapper67_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(*r));

    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1u));
    for (uint8_t i = 0u; i < 4u; i++) {
        mapper67_load_chr2k(nes, i, i);
    }
    nes_ppu_screen_mirrors(nes, NES_MIRROR_AUTO);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper67_t* r = (nes_mapper67_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF800u) {
        case 0x8800u: mapper67_load_chr2k(nes, 0u, data); break;
        case 0x9800u: mapper67_load_chr2k(nes, 1u, data); break;
        case 0xA800u: mapper67_load_chr2k(nes, 2u, data); break;
        case 0xB800u: mapper67_load_chr2k(nes, 3u, data); break;
        case 0xC800u:
            /* First write (latch=0) → high byte; second write (latch=1) → low byte */
            if (!r->irq_latch) {
                r->irq_counter = (r->irq_counter & 0x00FFu) | ((uint16_t)data << 8u);
            } else {
                r->irq_counter = (r->irq_counter & 0xFF00u) | (uint16_t)data;
            }
            r->irq_latch = (uint8_t)(!r->irq_latch);
            break;
        case 0xD800u:
            r->irq_enable = (data >> 4u) & 1u;
            r->irq_latch  = 0u;
            nes->nes_cpu.irq_pending = 0;
            break;
        case 0xE800u:
            switch (data & 3u) {
                case 0u: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);    break;
                case 1u: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);  break;
                case 2u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0); break;
                case 3u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1); break;
            }
            break;
        case 0xF800u:
            nes_load_prgrom_16k(nes, 0, (uint16_t)(data % nes->nes_rom.prg_rom_size));
            break;
        default:
            break;
    }
}

/* CPU-cycle countdown; fires on unsigned underflow (crosses 0 → 0xFFFF).
 * Matches Mesen2 ProcessCpuClock / FCEUX MapIRQHook behaviour. */
static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    nes_mapper67_t* r = (nes_mapper67_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    uint16_t old = r->irq_counter;
    r->irq_counter -= cycles;
    if (r->irq_counter > old) { /* unsigned underflow */
        r->irq_enable = 0u;
        nes_cpu_irq(nes);
    }
}

int nes_mapper67_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}
