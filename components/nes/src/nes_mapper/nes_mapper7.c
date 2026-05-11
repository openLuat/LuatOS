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

/* https://www.nesdev.org/wiki/AxROM */
static void nes_mapper_init(nes_t* nes){
    // CPU $8000-$FFFF: 32 KB switchable PRG ROM bank
    nes_load_prgrom_32k(nes, 0, 0);
    // CHR capacity: 8 KiB ROM.
    nes_load_chrrom_8k(nes, 0, 0);
}

/*
    Bank select ($8000-$FFFF)
    7  bit  0
    ---- ----
    xxxM xPPP
       |  |||
       |  +++- Select 32 KB PRG ROM bank for CPU $8000-$FFFF
       +------ Select 1 KB VRAM page for all 4 nametables
*/

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    nes_load_prgrom_32k(nes, 0, data & 0x07);
    nes_ppu_screen_mirrors(nes, (data & 0x10) ? NES_MIRROR_ONE_SCREEN1 : NES_MIRROR_ONE_SCREEN0);
}

int nes_mapper7_init(nes_t* nes){
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

