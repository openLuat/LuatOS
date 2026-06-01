/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#pragma once

#ifdef __cplusplus
    extern "C" {
#endif

#define GBC_ENABLE_SOUND            (0)       /* sound is disabled by default for MCU performance */
#define GBC_APU_SAMPLE_RATE         (32000)   /* stereo PCM sample rate when sound is enabled */
#define GBC_APU_BUFFER_SAMPLES      (256)     /* interleaved S16LE stereo frames per output batch */
#define GBC_ENABLE_DMG              (1)       /* support original GB/DMG cartridges */
#define GBC_ENABLE_CGB              (1)       /* support GBC/CGB cartridges */

#define GBC_FRAME_SKIP              (0)       /* skip rendered frames */
#define GBC_COLOR_DEPTH             (16)      /* 16: RGB565, 32: ARGB8888 */
#define GBC_COLOR_SWAP              (0)       /* swap RGB565 bytes for SPI panels */
#define GBC_RAM_LACK                (0)       /* 1: draw half-screen blocks to reduce RAM */

#define GBC_USE_FS                  (1)       /* enable file based ROM loading */
#define GBC_ENABLE_SRAM_SAVE        (1)       /* 1: save battery-backed RAM to .sav file; requires GBC_USE_FS=1 */
#define GBC_ROM_STREAM              (0)       /* 1: stream ROM banks from file with LRU cache */
#define GBC_ROM_CACHE_BANKS         (4)       /* 16KiB cache banks used when GBC_ROM_STREAM=1 */

#define GBC_LOG_LEVEL               GBC_LOG_LEVEL_INFO

#ifdef __cplusplus
    }
#endif

