/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#pragma once

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "gbc_conf.h"

#ifdef __cplusplus
    extern "C" {
#endif

#if defined(__ARMCC_VERSION)
#define GBC_WEAK                    __attribute__((weak))
#elif defined(__IAR_SYSTEMS_ICC__)
#define GBC_WEAK                    __weak
#elif defined(__GNUC__)
#define GBC_WEAK                    __attribute__((weak))
#elif defined(_MSC_VER)
#define GBC_WEAK
#else
#define GBC_WEAK                    __attribute__((weak))
#endif

#if defined(_MSC_VER)
#define GBC_INLINE                  static __forceinline
#elif defined(__GNUC__) || defined(__clang__)
#define GBC_INLINE                  static inline __attribute__((always_inline))
#else
#define GBC_INLINE                  static inline
#endif

#ifndef GBC_ENABLE_SOUND
#define GBC_ENABLE_SOUND            (0)
#endif

#ifndef GBC_ENABLE_DMG
#define GBC_ENABLE_DMG              (1)
#endif

#ifndef GBC_ENABLE_CGB
#define GBC_ENABLE_CGB              (1)
#endif

#ifndef GBC_USE_FS
#define GBC_USE_FS                  (1)
#endif

#ifndef GBC_ENABLE_SRAM_SAVE
#define GBC_ENABLE_SRAM_SAVE        (GBC_USE_FS)
#endif

#ifndef GBC_FRAME_SKIP
#define GBC_FRAME_SKIP              (0)
#endif

#ifndef GBC_RAM_LACK
#define GBC_RAM_LACK                (0)
#endif

#ifndef GBC_ROM_STREAM
#define GBC_ROM_STREAM              (0)
#endif

#ifndef GBC_ROM_CACHE_BANKS
#define GBC_ROM_CACHE_BANKS         (4)
#endif

#ifndef GBC_COLOR_SWAP
#define GBC_COLOR_SWAP              (0)
#endif

#ifndef GBC_COLOR_DEPTH
#define GBC_COLOR_DEPTH             (32)
#endif

#ifndef GBC_LOG_LEVEL
#define GBC_LOG_LEVEL               GBC_LOG_LEVEL_INFO
#endif

#ifndef GBC_APU_SAMPLE_RATE
#define GBC_APU_SAMPLE_RATE         (32000)
#endif

#ifndef GBC_APU_BUFFER_SAMPLES
#define GBC_APU_BUFFER_SAMPLES      (256)
#endif

#ifndef GBC_SAVE_PATH_MAX
#define GBC_SAVE_PATH_MAX           (260)
#endif

#define GBC_WIDTH                   (160)
#define GBC_HEIGHT                  (144)
#define GBC_CPU_CLOCK_FREQ          (4194304UL)
#define GBC_CPU_CLOCK_FREQ_CGB      (8388608UL)
#define GBC_CYCLES_PER_LINE         (456)
#define GBC_LINES_PER_FRAME         (154)
#define GBC_CYCLES_PER_FRAME        (GBC_CYCLES_PER_LINE * GBC_LINES_PER_FRAME)

#if (GBC_RAM_LACK == 1)
#define GBC_DRAW_SIZE               (GBC_WIDTH * GBC_HEIGHT / 2)
#else
#define GBC_DRAW_SIZE               (GBC_WIDTH * GBC_HEIGHT)
#endif

#if (GBC_COLOR_DEPTH == 32)
#define gbc_color_t                 uint32_t
#elif (GBC_COLOR_DEPTH == 16)
#define gbc_color_t                 uint16_t
#else
#error "unsupported GBC_COLOR_DEPTH"
#endif

typedef enum {
    GBC_OK = 0,
    GBC_ERROR = -1,
    GBC_ERROR_ALLOC = -2,
    GBC_ERROR_BAD_ROM = -3,
    GBC_ERROR_UNSUPPORTED = -4,
    GBC_ERROR_IO = -5,
} gbc_error_t;

typedef enum {
    GBC_LOG_LEVEL_NONE = 0,
    GBC_LOG_LEVEL_ERROR,
    GBC_LOG_LEVEL_WARN,
    GBC_LOG_LEVEL_INFO,
    GBC_LOG_LEVEL_DEBUG,
} gbc_log_level_t;

#define GBC_LOG_ERROR(format, ...)  do { if (GBC_LOG_LEVEL >= GBC_LOG_LEVEL_ERROR) gbc_log_printf("[E] " format, ##__VA_ARGS__); } while (0)
#define GBC_LOG_WARN(format, ...)   do { if (GBC_LOG_LEVEL >= GBC_LOG_LEVEL_WARN) gbc_log_printf("[W] " format, ##__VA_ARGS__); } while (0)
#define GBC_LOG_INFO(format, ...)   do { if (GBC_LOG_LEVEL >= GBC_LOG_LEVEL_INFO) gbc_log_printf("[I] " format, ##__VA_ARGS__); } while (0)
#define GBC_LOG_DEBUG(format, ...)  do { if (GBC_LOG_LEVEL >= GBC_LOG_LEVEL_DEBUG) gbc_log_printf("[D] " format, ##__VA_ARGS__); } while (0)

void *gbc_malloc(int num);
void gbc_free(void *address);
void *gbc_memcpy(void *str1, const void *str2, size_t n);
void *gbc_memset(void *str, int c, size_t n);
int gbc_memcmp(const void *str1, const void *str2, size_t n);

#if (GBC_USE_FS == 1)
FILE *gbc_fopen(const char *filename, const char *mode);
size_t gbc_fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t gbc_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
int gbc_fseek(FILE *stream, long int offset, int whence);
long gbc_ftell(FILE *stream);
int gbc_fclose(FILE *stream);
#endif

int gbc_draw(int x1, int y1, int x2, int y2, gbc_color_t *color_data);
int gbc_sound_output(uint8_t *buffer, size_t len);
int gbc_log_printf(const char *format, ...);
uint32_t gbc_get_ticks(void);
void gbc_delay(uint32_t ms);

#ifdef __cplusplus
    }
#endif

