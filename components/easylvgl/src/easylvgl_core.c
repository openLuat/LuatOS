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
    (void)disp;
    
    // 获取显示分辨率
    int32_t hor_res = lv_display_get_horizontal_resolution(disp);
    int32_t ver_res = lv_display_get_vertical_resolution(disp);
    
    // 边界检查
    if (area->x2 < 0 || area->y2 < 0 || area->x1 > hor_res - 1 || area->y1 > ver_res - 1) {
        lv_display_flush_ready(disp);
        return;
    }
    
    // 计算区域大小
    uint32_t w = area->x2 - area->x1 + 1;
    uint32_t h = area->y2 - area->y1 + 1;
    
    // 获取颜色格式
    lv_color_format_t color_format = lv_display_get_color_format(disp);
    uint8_t px_size = lv_color_format_get_size(color_format);
    
    // 转换像素数据（LVGL 9 使用 uint8_t*，需要转换为 lv_color_t）
    // 对于 RGB565，每个像素 2 字节
    lv_color_t *color_p = (lv_color_t *)px_map;
    
    // 这里可以调用实际的显示驱动
    // 例如：luat_sdl2_draw(area->x1, area->y1, area->x2, area->y2, color_p);
    
    // 检查是否是最后一块区域
    if (lv_display_flush_is_last(disp)) {
        // 可以在这里执行最终的刷新操作
        // 例如：luat_sdl2_flush();
    }
    
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
    
    // 创建显示对象
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
    
    // 创建 tick 定时器（每 5ms 调用一次）
    g_tick_timer = lv_timer_create(easylvgl_tick_timer_cb, 5, NULL);
    if (g_tick_timer == NULL) {
        LLOGE("Failed to create tick timer");
        lv_display_delete(g_display.display);
        g_display.display = NULL;
        return -1;
    }
    
    LLOGD("EasyLVGL initialized: %dx%d, buf_size=%d, mode=0x%02x", 
          w, h, (int)buf_size_bytes, buff_mode);
    
    return 0;
}

