# gbc

A GB/GBC emulator targeting low-memory MCUs. Project structure, xmake build style, and trimming configuration follow the same conventions as `nes_github`.

## Features

- Supports both GB (DMG) and GBC (CGB) cartridge modes.
- No Boot ROM required; CPU/registers are initialized to post-boot defaults based on cartridge type.
- Core written in C11; `src/` has zero dependency on SDL or OS window interfaces.
- Platform capabilities are provided through weak `port/` functions: memory, filesystem, logging, display, audio, and time.
- Audio disabled by default; four-channel stereo APU available via `GBC_ENABLE_SOUND=1` using integer/fixed-point math only.
- Supported cartridge controllers: ROM ONLY, MBC1, MBC2, MBC3 (with RTC), MBC5.
- Battery-backed SRAM save/load to `.sav` files (configurable via `GBC_ENABLE_SRAM_SAVE`).
- Full-screen framebuffer or half-screen/block refresh modes; full ROM or streamed ROM with LRU bank cache.

## Directory Layout

```text
inc/                Public API and core module headers
src/                Platform-independent emulator core
port/               Default configuration and weak platform functions
sdl/sdl2/           SDL2 desktop verification port and xmake build
AGENTS.md           Chinese contributor/agent guidelines
README_zh.md        Chinese README
```

## Build (SDL2 example)

```powershell
Set-Location .\sdl\sdl2
xmake
xmake run gbc path\to\game.gb
xmake run gbc path\to\game.gbc

# Regression tests
xmake build core_test && xmake run core_test
xmake build sound_test && xmake run sound_test
```

`sdl/sdl2/xmake.lua` fetches `libsdl2` automatically and compiles `src/**.c`, `sdl/sdl2/main.c`, and the SDL port.

Default key bindings: `W/A/S/D` or arrow keys for D-pad, `J` = A, `K` = B, `V` = Select, `B` = Start, `Esc` = quit.

## Core API

```c
#include "gbc.h"

gbc_t *gbc = gbc_init();
gbc_set_model(gbc, GBC_MODEL_CGB); /* optional: force DMG with GBC_MODEL_DMG */
gbc_load_file(gbc, "game.gbc");    /* loads ROM and battery RAM if present */
gbc_run(gbc);
gbc_unload_file(gbc);              /* saves battery RAM before unloading */
gbc_deinit(gbc);
```

Loading ROM from memory:

```c
gbc_load_rom(gbc, rom_data, rom_size);
```

## Configuration Macros

All macros are set in `port/gbc_conf.h`. Defaults are tuned for PC/SDL debugging; MCU builds override as needed.

| Macro | Default | Description |
| --- | --- | --- |
| `GBC_ENABLE_DMG` | `1` | Enable GB/DMG cartridge support |
| `GBC_ENABLE_CGB` | `1` | Enable GBC/CGB cartridge support |
| `GBC_ENABLE_SOUND` | `0` | Audio output; disabled by default. Enable for S16LE stereo PCM |
| `GBC_APU_SAMPLE_RATE` | `32000` | APU sample rate (fixed-point accumulator, no floating point) |
| `GBC_APU_BUFFER_SAMPLES` | `256` | Interleaved S16LE stereo frames per audio flush |
| `GBC_RAM_LACK` | `0` | `1`: use half-screen/block refresh to reduce framebuffer RAM |
| `GBC_FRAME_SKIP` | `0` | Number of rendered frames to skip per emulated frame |
| `GBC_COLOR_DEPTH` | `32` | `16` = RGB565, `32` = ARGB8888 |
| `GBC_COLOR_SWAP` | `0` | Swap RGB565 bytes for SPI panels |
| `GBC_USE_FS` | `1` | Enable filesystem-based ROM loading |
| `GBC_ENABLE_SRAM_SAVE` | `(GBC_USE_FS)` | Save battery-backed RAM to `.sav` file; auto-disabled when `GBC_USE_FS=0` |
| `GBC_ROM_STREAM` | `0` | `1`: stream ROM banks from file with LRU bank cache |
| `GBC_ROM_CACHE_BANKS` | `4` | Number of 16 KiB ROM cache banks for streaming mode |
| `GBC_LOG_LEVEL` | `GBC_LOG_LEVEL_INFO` | Log verbosity |

Recommended low-memory MCU configuration:

```c
#define GBC_COLOR_DEPTH      (16)
#define GBC_RAM_LACK         (1)
#define GBC_ROM_STREAM       (1)
#define GBC_ROM_CACHE_BANKS  (3)
#define GBC_ENABLE_SOUND     (0)
#define GBC_ENABLE_SRAM_SAVE (0)   /* disable if no persistent storage */
```

## Porting

Replace or implement the following functions in your platform port:

- `gbc_malloc` / `gbc_free`
- `gbc_memcpy` / `gbc_memset` / `gbc_memcmp`
- `gbc_fopen` / `gbc_fread` / `gbc_fwrite` / `gbc_fseek` / `gbc_ftell` / `gbc_fclose`
- `gbc_draw` — receives pixel buffer for the current scanline block
- `gbc_sound_output` — receives S16LE stereo PCM bytes when `GBC_ENABLE_SOUND=1`
- `gbc_log_printf`
- `gbc_get_ticks` / `gbc_delay`
- `gbc_initex` / `gbc_deinitex` / `gbc_frame` — optional lifecycle hooks

## Known Limitations

This is an MCU-focused MVP, not a cycle-accurate emulator:

- SM83 CPU covers all common opcode paths; a few edge-case timing behaviors may not be exact.
- PPU uses scanline rendering; Mode 3 length is approximated by `SCX&7` + visible sprite count × 6. Pixel FIFO border behavior is not fully accurate.
- APU is off by default; when enabled, four-channel approximate stereo (square, wave, noise) is provided using integer/fixed-point arithmetic only.
- MBC3 RTC, HBlank HDMA, basic OAM DMA blocking, and basic internal-clock serial transfer are implemented; infrared and link-cable serial are not.
- Supported MBC types: ROM ONLY, MBC1, MBC2, MBC3, MBC5. Other types return an unsupported error.
