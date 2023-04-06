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

#ifndef _NES_CONF_
#define _NES_CONF_

#ifdef __cplusplus
    extern "C" {
#endif

#define NES_FRAME_SKIP          2

#define NES_USE_SRAM            0
#define NES_COLOR_DEPTH         16
#define NES_COLOR_SWAP          1
#define NES_RAM_LACK            1

#define NES_USE_FS              1

#ifndef NES_USE_FS
#define NES_USE_FS              0
#endif

#ifndef NES_FRAME_SKIP
#define NES_FRAME_SKIP          0
#endif

#ifndef NES_RAM_LACK
#define NES_RAM_LACK            0
#endif

#if (NES_RAM_LACK == 1)
#define NES_DRAW_SIZE         (NES_WIDTH * NES_HEIGHT / 2) 
#else
#define NES_DRAW_SIZE         (NES_WIDTH * NES_HEIGHT)
#endif

#ifndef NES_COLOR_SWAP
#define NES_COLOR_SWAP         0
#endif

/* Color depth:
 * - 16: RGB565
 * - 32: ARGB8888
 */
#ifndef NES_COLOR_DEPTH
#define NES_COLOR_DEPTH         32
#endif

#if (NES_COLOR_DEPTH == 32)
#define nes_color_t uint32_t
#elif (NES_COLOR_DEPTH == 16)
#define nes_color_t uint16_t
#else
#error "no supprt color depth"
#endif

#ifdef __cplusplus          
    }
#endif

#endif// _NES_CONF_
