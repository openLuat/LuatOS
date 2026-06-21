/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#pragma once

#ifdef __cplusplus
    extern "C" {
#endif

#include "luat_conf_bsp.h"

// #define GBC_ENABLE_SOUND            (0)       /* sound is disabled by default for MCU performance */
#define GBC_APU_SAMPLE_RATE         (32000)   /* stereo PCM sample rate when sound is enabled */
#define GBC_APU_BUFFER_SAMPLES      (256)     /* interleaved S16LE stereo frames per output batch */
#define GBC_ENABLE_DMG              (1)       /* support original GB/DMG cartridges */
#define GBC_ENABLE_CGB              (1)       /* support GBC/CGB cartridges */

#define GBC_USE_FS                  (1)       /* enable file based ROM loading */

/* ROM stream mode: only 0x150 header + LRU bank cache; required for ROMs > ~1MB
 * on memory-constrained targets. Override via BSP define (e.g. luat_conf_bsp.h). */
#ifndef GBC_ROM_STREAM
#define GBC_ROM_STREAM              (0)       /* 1: stream ROM banks from file with LRU cache */
#endif

#ifndef GBC_ROM_CACHE_BANKS
#define GBC_ROM_CACHE_BANKS         (4)       /* 16KiB cache banks used when GBC_ROM_STREAM=1 */
#endif

#define GBC_LOG_LEVEL               GBC_LOG_LEVEL_INFO

#ifdef __cplusplus
    }
#endif

