/*
 * MIT License
 *
 * Copyright (c) 2022 Dozingfiretruck
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include "nes.h"

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_fs.h"

#ifdef LUAT_USE_GUI
#include "luat_lcd.h"
#endif

#ifdef LUAT_USE_AIRUI
#include "nes_airui_video.h"
static int g_nes_airui_mode = 0;

void nes_set_airui_mode(int enabled) {
    g_nes_airui_mode = enabled;
}
#endif

/* memory */
void *nes_malloc(int num){
    return luat_heap_malloc(num);
}

void nes_free(void *address){
    luat_heap_free(address);
}

void *nes_memcpy(void *str1, const void *str2, size_t n){
    return memcpy(str1, str2, n);
}

void *nes_memset(void *str, int c, size_t n){
    return memset(str,c,n);
}

int nes_memcmp(const void *str1, const void *str2, size_t n){
    return memcmp(str1,str2,n);
}

#if (NES_USE_FS == 1)
/* io */
FILE *nes_fopen( const char * filename, const char * mode ){
    return luat_fs_fopen(filename,mode);
}

size_t nes_fread(void *ptr, size_t size_of_elements, size_t number_of_elements, FILE *a_file){
    return luat_fs_fread(ptr, size_of_elements, number_of_elements,a_file);
}

int nes_fseek(FILE *stream, long int offset, int whence){
    return luat_fs_fseek(stream,offset,whence);
}

int nes_fclose( FILE *fp ){
    return luat_fs_fclose(fp);
}
#endif

/* wait */
void nes_wait(uint32_t ms){
    luat_rtos_task_sleep(ms);
}

#ifdef LUAT_USE_GUI
static luat_lcd_conf_t* nes_lcd_conf;
#endif

int nes_initex(nes_t *nes){
#ifdef LUAT_USE_GUI
    nes_lcd_conf = luat_lcd_get_default();
#endif
    return 0;
}

int nes_deinitex(nes_t *nes){
    return 0;
}

int nes_draw(int x1, int y1, int x2, int y2, nes_color_t* color_data){
#ifdef LUAT_USE_AIRUI
    if (g_nes_airui_mode) {
        return nes_airui_video_draw(NULL, x1, y1, x2, y2, color_data);
    }
#endif
#ifdef LUAT_USE_GUI
    return luat_lcd_draw(nes_lcd_conf, x1, y1, x2, y2, color_data);
#else
    return 0;
#endif
}

void nes_frame(nes_t* nes){
#ifdef LUAT_USE_AIRUI
    if (g_nes_airui_mode) {
        nes_airui_video_frame(NULL);
        return;
    }
#endif
#ifdef LUAT_BSP_PC
    /* PC 上限速到约 60fps（NES 实际约 60.1Hz），否则模拟器以全速运行 */
    luat_rtos_task_sleep(15);
#else
    luat_rtos_task_sleep(1);
#endif
}

/* log */
void nes_log_printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

