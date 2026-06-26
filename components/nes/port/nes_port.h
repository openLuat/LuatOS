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
#include "nes_default.h"

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

typedef struct {
    int  (*draw)(void *ctx, int x1, int y1, int x2, int y2, void *pixels);
    void (*frame)(void *ctx);
    void *ctx;
} nes_port_render_cb_t;

void nes_port_set_render_cb(nes_port_render_cb_t *cb);
void nes_port_clear_render_cb(void);

#ifdef LUAT_USE_AIRUI
/**
 * @brief 切换渲染模式
 * @param enabled 1=AirUI 模式，0=LCD 模式（默认）
 */
void nes_set_airui_mode(int enabled);
#endif

/* ==== NES 音频输出(audio v2 集成)==== */
#if (NES_ENABLE_SOUND == 1)
/**
 * @brief 初始化 NES 音频流
 *
 * 在 luat_lib_nes.c 的 l_nes_init 中,nes_load_file 之后、nes 任务创建之前
 * 被调用。内部使用 audio v2 的 RAW 编解码器与默认 DAC 驱动,创建一个
 * stream 模式的音频请求,NES APU 的 PCM 样本将经此通路播放。
 *
 * @return 0 成功;<0 失败(非致命,NES 仍可正常运行,仅无声)
 */
int nes_audio_init(void);

/**
 * @brief 反初始化 NES 音频流
 *
 * 在 luat_lib_nes.c 的 l_nes_deinit 中被调用。取消并释放
 * nes_audio_init 创建的 stream 请求。
 */
void nes_audio_deinit(void);
#endif


#ifdef __cplusplus
    }
#endif

#endif// _NES_PORT_
