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
#include "luat_malloc.h"
#include "luat_timer.h"
#include "luat_fs.h"
#include "luat_lcd.h"

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
    luat_timer_mdelay(ms);
}

static luat_lcd_conf_t* nes_lcd_conf;

int nes_initex(nes_t *nes){
    nes_lcd_conf = luat_lcd_get_default();
    return 0;
}

int nes_deinitex(nes_t *nes){
    return 0;
}

int nes_draw(size_t x1, size_t y1, size_t x2, size_t y2, nes_color_t* color_data){
    return luat_lcd_draw(nes_lcd_conf, x1, y1, x2, y2, color_data);
}

void nes_frame(void){
    luat_timer_us_delay(10);
}

