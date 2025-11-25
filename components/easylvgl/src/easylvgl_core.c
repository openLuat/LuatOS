/**
 * @file easylvgl_core.c
 * @summary EasyLVGL 核心实现 (LVGL 9.4)
 * @version 0.0.2
 */

#include "easylvgl.h"
#include "luat_mem.h"
#include "luat_log.h"
#include "../lvgl9/lvgl.h"

#define LUAT_LOG_TAG "easylvgl"
#include "luat_log.h"

#ifdef LUAT_USE_LVGL_SDL2
#include "luat_sdl2.h"
#include "../sdl2/lv_sdl_drv_input.h"
static uint32_t *g_sdl2_fb = NULL;       // SDL2 临时帧缓冲区（用于转换为 ARGB8888）
static size_t g_sdl2_fb_size = 0;        // SDL2 帧缓冲区大小
static lv_indev_t *g_sdl2_indev = NULL;  // SDL2 输入设备
#endif

static easylvgl_display_t g_display = {0};
static lua_State *g_L = NULL;
static lv_timer_t *g_tick_timer = NULL;

/**
 * LVGL tick 更新定时器回调
 */
static void easylvgl_tick_timer_cb(lv_timer_t *timer) {
    (void)timer;
    lv_tick_inc(5);  // 5ms tick
}

/**
 * 显示刷新回调（LVGL 9 格式）
 * LVGL 9 使用 uint8_t* 作为像素数据，需要根据颜色深度转换
 */
void easylvgl_disp_flush(lv_display_t *disp, const lv_area_t *area, uint8_t *px_map) {
    // 获取显示分辨率
    int32_t hor_res = lv_display_get_horizontal_resolution(disp);
    int32_t ver_res = lv_display_get_vertical_resolution(disp);
    
    // 边界检查
    if (area->x2 < 0 || area->y2 < 0 || area->x1 > hor_res - 1 || area->y1 > ver_res - 1) {
        lv_display_flush_ready(disp);
        return;
    }
    
    // 计算区域大小
    size_t w = area->x2 - area->x1 + 1;
    size_t h = area->y2 - area->y1 + 1;
    
#ifdef LUAT_USE_LVGL_SDL2
    // SDL2 模式：将像素数据转换为 ARGB8888 并绘制到 SDL2 窗口
    
    // 获取颜色格式
    lv_color_format_t color_format = lv_display_get_color_format(disp);
    
    // 检查临时帧缓冲区是否足够大
    size_t required_size = w * h;
    if (g_sdl2_fb == NULL || g_sdl2_fb_size < required_size) {
        // 重新分配缓冲区
        if (g_sdl2_fb != NULL) {
            luat_heap_free(g_sdl2_fb);
        }
        g_sdl2_fb = luat_heap_malloc(required_size * sizeof(uint32_t));
        if (g_sdl2_fb == NULL) {
            LLOGE("Failed to allocate SDL2 framebuffer");
            lv_display_flush_ready(disp);
            return;
        }
        g_sdl2_fb_size = required_size;
    }
    
    // 根据颜色格式转换像素数据
    if (color_format == LV_COLOR_FORMAT_RGB565 || color_format == LV_COLOR_FORMAT_RGB565_SWAPPED) {
        // RGB565 格式：每个像素 2 字节，转换为 ARGB8888
        uint16_t *color_p = (uint16_t *)px_map;
        uint32_t *tmp = g_sdl2_fb;
        
        for (size_t i = 0; i < h; i++) {
            for (size_t j = 0; j < w; j++) {
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
        uint32_t *tmp = g_sdl2_fb;
        
        for (size_t i = 0; i < h; i++) {
            for (size_t j = 0; j < w; j++) {
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
        uint32_t *tmp = g_sdl2_fb;
        
        for (size_t i = 0; i < h; i++) {
            for (size_t j = 0; j < w; j++) {
                *tmp = *argb_p;
                tmp++;
                argb_p++;
            }
        }
    } else {
        // 其他格式暂不支持
        LLOGE("Unsupported color format: %d", color_format);
        lv_display_flush_ready(disp);
        return;
    }
    
    // 调用 SDL2 绘制函数
    luat_sdl2_draw(area->x1, area->y1, area->x2, area->y2, g_sdl2_fb);
    
    // 检查是否是最后一块区域
    if (lv_display_flush_is_last(disp)) {
        // 执行最终的刷新操作
        luat_sdl2_flush();
    }
    
#else
    // 非 SDL2 模式：这里可以调用实际的嵌入式显示驱动
    (void)w;
    (void)h;
    (void)px_map;
    // 例如：调用 LCD 驱动的 flush 函数
#endif
    
    // 通知 LVGL 刷新完成
    lv_display_flush_ready(disp);
}

/**
 * 初始化 EasyLVGL
 */
int easylvgl_init_internal(int w, int h, size_t buf_size, uint8_t buff_mode) {
    if (g_display.display != NULL) {
        LLOGE("EasyLVGL already initialized");
        return -1;
    }
    
    // 初始化 LVGL
    if (!lv_is_initialized()) {
        lv_init();
    }
    
#ifdef LUAT_USE_LVGL_SDL2
    // 初始化 SDL2 显示
    luat_sdl2_conf_t conf = {
        .width = w,
        .height = h,
        .title = "EasyLVGL"
    };
    if (luat_sdl2_init(&conf) != 0) {
        LLOGE("Failed to initialize SDL2");
        return -1;
    }
    LLOGD("SDL2 initialized: %dx%d", w, h);
#endif
    
    // 创建显示对象（必须在输入设备之前创建！）
    g_display.display = lv_display_create(w, h);
    if (g_display.display == NULL) {
        LLOGE("Failed to create display");
        return -1;
    }
    
    // 设置颜色格式为 RGB565（16位）
    lv_display_set_color_format(g_display.display, LV_COLOR_FORMAT_RGB565);
    
    // 计算缓冲区大小（字节）
    if (buf_size == 0) {
        buf_size = w * 10;  // 默认 10 行
    }
    
    // 每个像素 2 字节（RGB565）
    size_t buf_size_bytes = buf_size * sizeof(lv_color_t);
    
    // 分配缓冲区
    if (buff_mode & 0x08) {
        // 使用 Lua heap
        if (buff_mode & 0x02) {
            g_display.buf1 = luat_heap_malloc(buf_size_bytes);
            if (g_display.buf1 == NULL) {
                LLOGE("Failed to allocate buf1");
                lv_display_delete(g_display.display);
                g_display.display = NULL;
                return -1;
            }
        }
        if (buff_mode & 0x04) {
            g_display.buf2 = luat_heap_malloc(buf_size_bytes);
            if (g_display.buf2 == NULL) {
                LLOGE("Failed to allocate buf2");
                if (g_display.buf1) {
                    luat_heap_free(g_display.buf1);
                    g_display.buf1 = NULL;
                }
                lv_display_delete(g_display.display);
                g_display.display = NULL;
                return -1;
            }
        }
    } else {
        // 使用系统 heap
        if (buff_mode & 0x02) {
            g_display.buf1 = luat_heap_malloc(buf_size_bytes);
            if (g_display.buf1 == NULL) {
                LLOGE("Failed to allocate buf1");
                lv_display_delete(g_display.display);
                g_display.display = NULL;
                return -1;
            }
        }
        if (buff_mode & 0x04) {
            g_display.buf2 = luat_heap_malloc(buf_size_bytes);
            if (g_display.buf2 == NULL) {
                LLOGE("Failed to allocate buf2");
                if (g_display.buf1) {
                    luat_heap_free(g_display.buf1);
                    g_display.buf1 = NULL;
                }
                lv_display_delete(g_display.display);
                g_display.display = NULL;
                return -1;
            }
        }
    }
    
    g_display.buf_size = buf_size_bytes;
    
    // 设置缓冲区（使用 PARTIAL 渲染模式）
    lv_display_set_buffers(g_display.display, 
                          g_display.buf1, 
                          g_display.buf2, 
                          buf_size_bytes,
                          LV_DISPLAY_RENDER_MODE_PARTIAL);
    
    // 设置刷新回调
    lv_display_set_flush_cb(g_display.display, easylvgl_disp_flush);
    
    // 设置为默认显示
    lv_display_set_default(g_display.display);
    
#ifdef LUAT_USE_LVGL_SDL2
    // 初始化 SDL2 输入设备（必须在显示设备创建并设为默认之后！）
    g_sdl2_indev = lv_sdl_init_input();
    if (g_sdl2_indev != NULL) {
        LLOGD("SDL2 input initialized");
    }
#endif

#ifndef LUAT_USE_LVGL_SDL2
    // 在非 PC 模拟器平台上，创建 tick 定时器（每 5ms 调用一次）
    // PC 模拟器上由 C 层 libuv 定时器处理 tick 更新
    g_tick_timer = lv_timer_create(easylvgl_tick_timer_cb, 5, NULL);
    if (g_tick_timer == NULL) {
        LLOGE("Failed to create tick timer");
        lv_display_delete(g_display.display);
        g_display.display = NULL;
        return -1;
    }
#endif
    
    LLOGD("EasyLVGL initialized: %dx%d, buf_size=%d, mode=0x%02x", 
          w, h, (int)buf_size_bytes, buff_mode);
    
    return 0;
}

/**
 * 反初始化 EasyLVGL
 */
void easylvgl_deinit(void) {
    // 删除定时器
    if (g_tick_timer != NULL) {
        lv_timer_delete(g_tick_timer);
        g_tick_timer = NULL;
    }
    
    // 释放缓冲区
    if (g_display.buf1 != NULL) {
        luat_heap_free(g_display.buf1);
        g_display.buf1 = NULL;
    }
    if (g_display.buf2 != NULL) {
        luat_heap_free(g_display.buf2);
        g_display.buf2 = NULL;
    }
    
    // 删除显示对象
    if (g_display.display != NULL) {
        lv_display_delete(g_display.display);
        g_display.display = NULL;
    }
    
#ifdef LUAT_USE_LVGL_SDL2
    // 释放 SDL2 帧缓冲区
    if (g_sdl2_fb != NULL) {
        luat_heap_free(g_sdl2_fb);
        g_sdl2_fb = NULL;
        g_sdl2_fb_size = 0;
    }
    // 反初始化 SDL2 输入设备
    lv_sdl_deinit_input();
    g_sdl2_indev = NULL;
    // 反初始化 SDL2
    luat_sdl2_deinit(NULL);
#endif
    
    LLOGD("EasyLVGL deinitialized");
}

