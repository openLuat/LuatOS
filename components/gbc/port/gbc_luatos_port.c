/*
 * LuatOS port for the GBC emulator component.
 * Provides memory, file I/O, display, and timing hooks using LuatOS APIs.
 * Modelled after components/nes/port/nes_port.c.
 */

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_fs.h"

#ifdef LUAT_USE_GUI
#include "luat_lcd.h"
#endif

#include "gbc.h"
#include <stdarg.h>

/* --- memory ---------------------------------------------------------------- */

void *gbc_malloc(int num)
{
    return luat_heap_malloc(num);
}

void gbc_free(void *address)
{
    luat_heap_free(address);
}

void *gbc_memcpy(void *str1, const void *str2, size_t n)
{
    return memcpy(str1, str2, n);
}

void *gbc_memset(void *str, int c, size_t n)
{
    return memset(str, c, n);
}

int gbc_memcmp(const void *str1, const void *str2, size_t n)
{
    return memcmp(str1, str2, n);
}

/* --- file I/O -------------------------------------------------------------- */

#if (GBC_USE_FS == 1)
FILE *gbc_fopen(const char *filename, const char *mode)
{
    return luat_fs_fopen(filename, mode);
}

size_t gbc_fread(void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    return luat_fs_fread(ptr, size, nmemb, stream);
}

size_t gbc_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    return luat_fs_fwrite(ptr, size, nmemb, stream);
}

int gbc_fseek(FILE *stream, long int offset, int whence)
{
    return luat_fs_fseek(stream, offset, whence);
}

long gbc_ftell(FILE *stream)
{
    return (long)luat_fs_ftell(stream);
}

int gbc_fclose(FILE *stream)
{
    return luat_fs_fclose(stream);
}
#endif /* GBC_USE_FS */

/* --- timing ---------------------------------------------------------------- */

uint32_t gbc_get_ticks(void)
{
    extern uint64_t luat_mcu_tick64_ms(void);
    return (uint32_t)luat_mcu_tick64_ms();
}

void gbc_delay(uint32_t ms)
{
    luat_rtos_task_sleep(ms);
}

/* --- log ------------------------------------------------------------------- */

int gbc_log_printf(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    int ret = vprintf(format, args);
    va_end(args);
    return ret;
}

/* --- sound (disabled) ------------------------------------------------------ */

int gbc_sound_output(uint8_t *buffer, size_t len)
{
    (void)buffer;
    (void)len;
    return GBC_OK;
}

/* --- display --------------------------------------------------------------- */

#ifdef LUAT_USE_GUI
static luat_lcd_conf_t *gbc_lcd_conf;
#endif

int gbc_initex(gbc_t *gbc)
{
    (void)gbc;
#ifdef LUAT_USE_GUI
    gbc_lcd_conf = luat_lcd_get_default();
#endif
    return GBC_OK;
}

int gbc_deinitex(gbc_t *gbc)
{
    (void)gbc;
    return GBC_OK;
}

int gbc_draw(int x1, int y1, int x2, int y2, gbc_color_t *color_data)
{
#ifdef LUAT_USE_GUI
    return luat_lcd_draw(gbc_lcd_conf,
                         (int16_t)x1, (int16_t)y1,
                         (int16_t)x2, (int16_t)y2,
                         (luat_color_t *)color_data);
#else
    (void)x1; (void)y1; (void)x2; (void)y2; (void)color_data;
    return GBC_OK;
#endif
}

void gbc_frame(gbc_t *gbc)
{
    (void)gbc;
    /* ~60 fps: sleep ~16ms per frame, same cadence as the NES port */
#ifdef LUAT_BSP_PC
    luat_rtos_task_sleep(16);
#else
    luat_rtos_task_sleep(1);
#endif
}
