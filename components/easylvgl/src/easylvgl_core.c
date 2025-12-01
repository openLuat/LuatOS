/**
 * @file easylvgl_core.c
 * @summary EasyLVGL 核心实现 (LVGL 9.4)
 * @version 0.0.2
 */

#include "easylvgl.h"
#include "luat_mem.h"
#include "luat_log.h"
#include "luat_lcd.h"
#include "luat_timer.h"
#include <stdbool.h>
#include "../lvgl9/lvgl.h"
#include "easylvgl_component.h"

#define LUAT_LOG_TAG "easylvgl"
#include "luat_log.h"

#ifdef LUAT_USE_LVGL_SDL2
#include "luat_sdl2.h"
#include "../sdl2/lv_sdl_drv_input.h"
#endif

#define EASYLVGL_TICK_TIMER_ID 0xE5E5

#ifdef LUAT_USE_LVGL_SDL2
static uint32_t *g_sdl2_fb = NULL;       // SDL2 临时帧缓冲区（用于转换为 ARGB8888）
static size_t g_sdl2_fb_size = 0;        // SDL2 帧缓冲区大小
static lv_indev_t *g_sdl2_indev = NULL;  // SDL2 输入设备
#endif

static easylvgl_display_t g_display = {0};
static luat_timer_t g_tick_timer = {0};
static bool g_tick_timer_registered = false;
static luat_lcd_conf_t *g_lcd_conf = NULL;
static bool g_buf1_owned = false;
static bool g_buf2_owned = false;
static bool g_lcd_output = false;

static void *alloc_lv_buffer(lua_State *L, size_t size, int *ref, bool *owned, bool use_lua_heap) {
    if (size == 0) {
        return NULL;
    }
    if (use_lua_heap && L != NULL) {
        void *buf = lua_newuserdata(L, size);
        if (buf != NULL) {
            *ref = luaL_ref(L, LUA_REGISTRYINDEX);
            return buf;
        }
    }
    void *buf = luat_heap_malloc(size);
    if (buf != NULL && owned != NULL) {
        *owned = true;
    }
    return buf;
}

static int easylvgl_tick_timer_msg_handler(lua_State *L, void *ptr) {
    (void)L;
    (void)ptr;
    lv_tick_inc(5);  // 5ms tick
    return 0;
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
    #ifdef LUAT_USE_LCD
    if (g_lcd_conf != NULL) {
        luat_color_t *color_p = (luat_color_t *)px_map;
        luat_lcd_draw(g_lcd_conf, area->x1, area->y1, area->x2, area->y2, color_p);
        if (lv_display_flush_is_last(disp)) {
            g_lcd_conf->buff_draw = color_p;
            luat_lcd_flush(g_lcd_conf);
        }
        lv_display_flush_ready(disp);
        return;
    }
    #endif
    (void)w;
    (void)h;
    (void)px_map;
#endif
    
    // 通知 LVGL 刷新完成
    lv_display_flush_ready(disp);
}

/**
 * 初始化 EasyLVGL
 */
int easylvgl_init_internal(int w, int h, size_t buf_size, uint8_t buff_mode, luat_lcd_conf_t* lcd_conf) {
    if (g_display.display != NULL) {
        LLOGE("EasyLVGL already initialized");
        return -1;
    }

    if (!lv_is_initialized()) {
        lv_init();
    }

    lua_State *L = easylvgl_get_lua_state();
    g_display.buf1_ref = LUA_NOREF;
    g_display.buf2_ref = LUA_NOREF;
    g_buf1_owned = false;
    g_buf2_owned = false;
    g_lcd_output = false;

#ifdef LUAT_USE_LCD
    if (lcd_conf == NULL) {
        lcd_conf = luat_lcd_get_default();
    }
    g_lcd_conf = lcd_conf;
    if (g_lcd_conf != NULL) {
        g_lcd_conf->lcd_use_lvgl = 1;
        if (w == 0) {
            w = g_lcd_conf->w;
        }
        if (h == 0) {
            h = g_lcd_conf->h;
        }
    }
    LLOGD("lcd_conf: %p, w: %d, h: %d", g_lcd_conf, w, h);
#else
    (void)lcd_conf;
    g_lcd_conf = NULL;
#endif

    #if defined(LUA_USE_LINUX) || defined(LUA_USE_WINDOWS)
    if (w == 0) w = 800;
    if (h == 0) h = 640;
    #else
    if (w == 0 || h == 0) {
        LLOGE("setup lcd first!!");
        return -1;
    }
    #endif

    if (buf_size == 0) {
        buf_size = w * 10;
    }

#ifdef LUAT_USE_LCD
    bool use_lcd_buffer = false;
    if (g_lcd_conf != NULL && g_lcd_conf->buff != NULL && (buff_mode & 0x01) == 0) {
        buff_mode |= 0x01;
    }
    if ((buff_mode & 0x01) && g_lcd_conf != NULL && g_lcd_conf->buff != NULL) {
        use_lcd_buffer = true;
        buf_size = (size_t)w * h;
    }
#else
    bool use_lcd_buffer = false;
#endif

    size_t fbuff_pixels = buf_size;
    size_t buf_size_bytes = fbuff_pixels * sizeof(lv_color_t);
    bool need_buf1 = (buff_mode & 0x02) != 0;
    bool need_buf2 = (buff_mode & 0x04) != 0;
    if (!need_buf1) {
        need_buf1 = true;
    }
    bool use_lua_heap = (buff_mode & 0x08) != 0;
    int result = -1;

#ifdef LUAT_USE_LVGL_SDL2
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

    g_display.display = lv_display_create(w, h);
    if (g_display.display == NULL) {
        LLOGE("Failed to create display");
        goto cleanup;
    }

    lv_display_set_color_format(g_display.display, LV_COLOR_FORMAT_RGB565);

    if (need_buf1) {
#ifdef LUAT_USE_LCD
        if (use_lcd_buffer && g_lcd_conf != NULL) {
            g_display.buf1 = g_lcd_conf->buff;
            g_lcd_output = true;
        } else
#endif
        {
            g_display.buf1 = alloc_lv_buffer(L, buf_size_bytes, &g_display.buf1_ref, &g_buf1_owned, use_lua_heap);
        }
        if (g_display.buf1 == NULL) {
            LLOGE("Failed to allocate buf1");
            goto cleanup;
        }
    }

    if (need_buf2) {
#ifdef LUAT_USE_LCD
        if (use_lcd_buffer && g_lcd_conf != NULL && g_lcd_conf->buff_ex != NULL) {
            g_display.buf2 = g_lcd_conf->buff_ex;
            g_lcd_output = true;
        } else
#endif
        {
            g_display.buf2 = alloc_lv_buffer(L, buf_size_bytes, &g_display.buf2_ref, &g_buf2_owned, use_lua_heap);
        }
        if (g_display.buf2 == NULL) {
            LLOGE("Failed to allocate buf2");
            goto cleanup;
        }
    }

    g_display.buf_size = buf_size_bytes;

    lv_display_set_buffers(g_display.display,
                          g_display.buf1,
                          g_display.buf2,
                          buf_size_bytes,
                          LV_DISPLAY_RENDER_MODE_PARTIAL);

    lv_display_set_flush_cb(g_display.display, easylvgl_disp_flush);
    lv_display_set_default(g_display.display);

#ifdef LUAT_USE_LVGL_SDL2
    g_sdl2_indev = lv_sdl_init_input();
    if (g_sdl2_indev != NULL) {
        LLOGD("SDL2 input initialized");
    }
#endif

#ifndef LUAT_USE_LVGL_SDL2
    g_tick_timer.id = EASYLVGL_TICK_TIMER_ID;
    g_tick_timer.timeout = 5;
    g_tick_timer.repeat = -1;
    g_tick_timer.func = easylvgl_tick_timer_msg_handler;
    g_tick_timer.type = 0;
    if (luat_timer_start(&g_tick_timer) != 0) {
        LLOGE("Failed to start tick timer");
        goto cleanup;
    }
    g_tick_timer_registered = true;
#endif

    easylvgl_fs_init();

    LLOGD("EasyLVGL initialized: %dx%d, buf_size=%d, mode=0x%02x",
          w, h, (int)buf_size_bytes, buff_mode);

    result = 0;

cleanup:
    if (result != 0) {
        easylvgl_deinit();
    }
    return result;
}

/**
 * 反初始化 EasyLVGL
 */
void easylvgl_deinit(void) {
    lua_State *L = easylvgl_get_lua_state();
    #ifndef LUAT_USE_LVGL_SDL2
    if (g_tick_timer_registered) {
        luat_timer_stop(&g_tick_timer);
        g_tick_timer_registered = false;
    }
    #endif

    if (g_display.buf1_ref != LUA_NOREF && L != NULL) {
        luaL_unref(L, LUA_REGISTRYINDEX, g_display.buf1_ref);
    }
    if (g_display.buf2_ref != LUA_NOREF && L != NULL) {
        luaL_unref(L, LUA_REGISTRYINDEX, g_display.buf2_ref);
    }
    g_display.buf1_ref = LUA_NOREF;
    g_display.buf2_ref = LUA_NOREF;

    if (g_buf1_owned && g_display.buf1 != NULL) {
        luat_heap_free(g_display.buf1);
    }
    if (g_buf2_owned && g_display.buf2 != NULL) {
        luat_heap_free(g_display.buf2);
    }

    g_display.buf1 = NULL;
    g_display.buf2 = NULL;
    g_display.buf_size = 0;
    g_buf1_owned = false;
    g_buf2_owned = false;
    g_lcd_output = false;

    if (g_display.display != NULL) {
        lv_display_delete(g_display.display);
        g_display.display = NULL;
    }

#ifdef LUAT_USE_LCD
    if (g_lcd_conf != NULL) {
        g_lcd_conf->lcd_use_lvgl = 0;
        g_lcd_conf = NULL;
    }
#endif

#ifdef LUAT_USE_LVGL_SDL2
    if (g_sdl2_fb != NULL) {
        luat_heap_free(g_sdl2_fb);
        g_sdl2_fb = NULL;
        g_sdl2_fb_size = 0;
    }
    lv_sdl_deinit_input();
    g_sdl2_indev = NULL;
    luat_sdl2_deinit(NULL);
#endif

    LLOGD("EasyLVGL deinitialized");
}

