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

#ifndef _NES_PORT_
#define _NES_PORT_

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "nes_conf.h"

#ifdef __cplusplus
    extern "C" {
#endif

/* log */
#ifdef __DEBUG__
#define nes_printf(...)  printf(__VA_ARGS__)
#else
#define nes_printf(...)
#endif

/* memory */
void *nes_malloc(int num);
void nes_free(void *address);
void *nes_memcpy(void *str1, const void *str2, size_t n);
void *nes_memset(void *str, int c, size_t n);
int nes_memcmp(const void *str1, const void *str2, size_t n);

#if (NES_USE_FS == 1)
/* io */
FILE *nes_fopen( const char * filename, const char * mode );
size_t nes_fread(void *ptr, size_t size_of_elements, size_t number_of_elements, FILE *a_file);
int nes_fseek(FILE *stream, long int offset, int whence);
int nes_fclose( FILE *fp );
#endif

void nes_wait(uint32_t ms);

void nes_frame(void);

int nes_draw(size_t x1, size_t y1, size_t x2, size_t y2, nes_color_t* color_data);


#ifdef __cplusplus          
    }
#endif

#endif// _NES_PORT_
