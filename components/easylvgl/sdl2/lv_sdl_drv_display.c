/* MIT License
 * 
 * Copyright (c) [2020] [Ryan Wendland]
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

#include "luat_base.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "sdl2"
#include "luat_log.h"
#ifdef LUAT_USE_LVGL_SDL2
#include <stdio.h>
#include <assert.h>
#include "../lvgl9/lvgl.h"
#include "../lvgl9/lv_conf.h"
#include "lv_sdl_drv_display.h"

static void *pixels = NULL;
static uint32_t *fb = NULL;
#include "luat_sdl2.h"

/**
 * 显示刷新回调（LVGL 9 格式）
 * LVGL 9 使用 uint8_t* 作为像素数据，需要根据颜色格式转换
 */
static void sdl_fb_flush(lv_display_t *disp,
                         const lv_area_t *area,
                         uint8_t *px_map)
{
    // 获取显示分辨率
    int32_t hor_res = lv_display_get_horizontal_resolution(disp);
    int32_t ver_res = lv_display_get_vertical_resolution(disp);
    
    // 边界检查
    if(area->x2 < 0 || area->y2 < 0 || area->x1 > hor_res - 1 || area->y1 > ver_res - 1) {
        lv_display_flush_ready(disp);
        return;
    }
    
    size_t rw = area->x2 - area->x1 + 1;
    size_t rh = area->y2 - area->y1 + 1;
    
    // 获取颜色格式
    lv_color_format_t color_format = lv_display_get_color_format(disp);
    
    // 转换像素数据（LVGL 9 使用 uint8_t*，需要转换为 uint32_t 用于 SDL2）
    // 对于 RGB565，每个像素 2 字节
    if (color_format == LV_COLOR_FORMAT_RGB565 || color_format == LV_COLOR_FORMAT_RGB565_SWAPPED) {
        // RGB565 格式：每个像素 2 字节
        uint16_t *color_p = (uint16_t *)px_map;
        uint32_t *tmp = fb;
        
        for (size_t i = 0; i < rh; i++) {
            for (size_t j = 0; j < rw; j++) {
                // 将 RGB565 转换为 ARGB8888 (0xAARRGGBB)
                uint16_t rgb565 = *color_p;
                uint8_t r = ((rgb565 >> 11) & 0x1F) << 3;
                uint8_t g = ((rgb565 >> 5) & 0x3F) << 2;
                uint8_t b = (rgb565 & 0x1F) << 3;
                *tmp = (0xFF << 24) | (r << 16) | (g << 8) | b;
                tmp++;
                color_p++;
            }
        }
    } else if (color_format == LV_COLOR_FORMAT_RGB888) {
        // RGB888 格式：每个像素 3 字节
        uint8_t *rgb_p = px_map;
        uint32_t *tmp = fb;
        
        for (size_t i = 0; i < rh; i++) {
            for (size_t j = 0; j < rw; j++) {
                uint8_t r = rgb_p[0];
                uint8_t g = rgb_p[1];
                uint8_t b = rgb_p[2];
                *tmp = (0xFF << 24) | (r << 16) | (g << 8) | b;
                tmp++;
                rgb_p += 3;
            }
        }
    } else if (color_format == LV_COLOR_FORMAT_ARGB8888 || color_format == LV_COLOR_FORMAT_XRGB8888) {
        // ARGB8888/XRGB8888 格式：每个像素 4 字节，直接复制
        uint32_t *argb_p = (uint32_t *)px_map;
        uint32_t *tmp = fb;
        
        for (size_t i = 0; i < rh; i++) {
            for (size_t j = 0; j < rw; j++) {
                *tmp = *argb_p;
                tmp++;
                argb_p++;
            }
        }
    } else {
        // 其他格式暂不支持，直接返回
        LLOGE("Unsupported color format: %d", color_format);
        lv_display_flush_ready(disp);
        return;
    }
    
    // 调用 SDL2 绘制函数
    luat_sdl2_draw(area->x1, area->y1, area->x2, area->y2, fb);
    
    // 检查是否是最后一块区域
    if (lv_display_flush_is_last(disp)) {
        // 执行最终的刷新操作
        luat_sdl2_flush();
    }
    
    // 通知 LVGL 刷新完成
    lv_display_flush_ready(disp);
}

/**
 * 初始化 SDL2 显示驱动（LVGL 9.4）
 */
lv_display_t *lv_sdl_init_display(const char *win_name, int width, int height)
{
    (void)win_name;  // win_name 在 luat_sdl2_init 中使用
    
    // 初始化 SDL2
    luat_sdl2_conf_t conf = {
        .width = width,
        .height = height
    };
    luat_sdl2_init(&conf);
    
    // 创建显示对象
    lv_display_t *disp = lv_display_create(width, height);
    if (disp == NULL) {
        LLOGE("Failed to create display");
        return NULL;
    }
    
    // 设置颜色格式为 RGB565（16位）
    lv_display_set_color_format(disp, LV_COLOR_FORMAT_RGB565);
    
    // 分配缓冲区（16 行）
    size_t buff_line = 16;
    size_t buf_size_bytes = width * buff_line * sizeof(uint16_t);  // RGB565 每个像素 2 字节
    
    pixels = luat_heap_malloc(buf_size_bytes);
    if (pixels == NULL) {
        LLOGE("Failed to allocate pixels buffer");
        lv_display_delete(disp);
        return NULL;
    }
    
    // 分配临时帧缓冲区（用于转换为 ARGB8888）
    fb = luat_heap_malloc(sizeof(uint32_t) * width * buff_line);
    if (fb == NULL) {
        LLOGE("Failed to allocate fb buffer");
        luat_heap_free(pixels);
        lv_display_delete(disp);
        return NULL;
    }
    
    // 设置缓冲区（使用 PARTIAL 渲染模式）
    lv_display_set_buffers(disp, pixels, NULL, buf_size_bytes, LV_DISPLAY_RENDER_MODE_PARTIAL);
    
    // 设置刷新回调
    lv_display_set_flush_cb(disp, sdl_fb_flush);
    
    // 设置为默认显示
    lv_display_set_default(disp);
    
    LLOGD("SDL2 display initialized: %dx%d", width, height);
    
    return disp;
}

/**
 * 反初始化 SDL2 显示驱动
 */
void lv_sdl_deinit_display(void)
{
    if (pixels != NULL) {
        luat_heap_free(pixels);
        pixels = NULL;
    }
    if (fb != NULL) {
        luat_heap_free(fb);
        fb = NULL;
    }
}

#endif
