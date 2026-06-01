/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <stdarg.h>
#include <stdlib.h>
#include <time.h>

#include "gbc.h"

GBC_WEAK void *gbc_malloc(int num)
{
    return malloc((size_t)num);
}

GBC_WEAK void gbc_free(void *address)
{
    free(address);
}

GBC_WEAK void *gbc_memcpy(void *str1, const void *str2, size_t n)
{
    return memcpy(str1, str2, n);
}

GBC_WEAK void *gbc_memset(void *str, int c, size_t n)
{
    return memset(str, c, n);
}

GBC_WEAK int gbc_memcmp(const void *str1, const void *str2, size_t n)
{
    return memcmp(str1, str2, n);
}

#if (GBC_USE_FS == 1)
GBC_WEAK FILE *gbc_fopen(const char *filename, const char *mode)
{
    return fopen(filename, mode);
}

GBC_WEAK size_t gbc_fread(void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    return fread(ptr, size, nmemb, stream);
}

GBC_WEAK size_t gbc_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    return fwrite(ptr, size, nmemb, stream);
}

GBC_WEAK int gbc_fseek(FILE *stream, long int offset, int whence)
{
    return fseek(stream, offset, whence);
}

GBC_WEAK long gbc_ftell(FILE *stream)
{
    return ftell(stream);
}

GBC_WEAK int gbc_fclose(FILE *stream)
{
    return fclose(stream);
}
#endif

GBC_WEAK int gbc_log_printf(const char *format, ...)
{
    int ret;
    va_list args;

    va_start(args, format);
    ret = vprintf(format, args);
    va_end(args);
    return ret;
}

GBC_WEAK int gbc_draw(int x1, int y1, int x2, int y2, gbc_color_t *color_data)
{
    (void)x1;
    (void)y1;
    (void)x2;
    (void)y2;
    (void)color_data;
    return GBC_OK;
}

GBC_WEAK int gbc_sound_output(uint8_t *buffer, size_t len)
{
    (void)buffer;
    (void)len;
    return GBC_OK;
}

GBC_WEAK uint32_t gbc_get_ticks(void)
{
    return (uint32_t)((clock() * 1000) / CLOCKS_PER_SEC);
}

GBC_WEAK void gbc_delay(uint32_t ms)
{
    uint32_t start = gbc_get_ticks();
    while ((gbc_get_ticks() - start) < ms) {
    }
}

GBC_WEAK int gbc_initex(gbc_t *gbc)
{
    (void)gbc;
    return GBC_OK;
}

GBC_WEAK int gbc_deinitex(gbc_t *gbc)
{
    (void)gbc;
    return GBC_OK;
}

GBC_WEAK void gbc_frame(gbc_t *gbc)
{
    (void)gbc;
}

