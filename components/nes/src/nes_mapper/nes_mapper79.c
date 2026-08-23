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
#include "nes_mapper.h"

/* https://www.nesdev.org/wiki/INES_Mapper_079 */

static void nes_mapper_init(nes_t* nes) {
    uint16_t prg32_count = (uint16_t)(nes->nes_rom.prg_rom_size / 2u);
    uint16_t last_prg32 = prg32_count ? (uint16_t)(prg32_count - 1u) : 0u;

    // CPU $8000-$FFFF: 32 KB switchable PRG ROM bank.
    nes_load_prgrom_32k(nes, 0, last_prg32);
    // CHR $0000-$1FFF: 8 KB switchable CHR ROM bank.
    nes_load_chrrom_8k(nes, 0, 0);
}

/*
    Register at $4100-$5FFF:
    7  bit  0
    ---- ----
    xxxx PCCC
         ||||
         |+++- Select 8 KB CHR ROM bank at $0000-$1FFF
         +---- Select 32 KB PRG ROM bank at $8000-$FFFF (only exact $4100)
*/
static void mapper79_write(nes_t* nes, uint16_t address, uint8_t data) {
    if (address == 0x4100u) {
        nes_load_prgrom_32k(nes, 0, (uint16_t)((data >> 3u) & 0x01u));
    }
    nes_load_chrrom_8k(nes, 0, (uint16_t)(data & 0x07u));
}

static void nes_mapper_apu_write(nes_t* nes, uint16_t address, uint8_t data) {
    if (address >= 0x4100u && address <= 0x5FFFu) {
        mapper79_write(nes, address, data);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper79_write(nes, address, data);
}

int nes_mapper79_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_apu   = nes_mapper_apu_write;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}
