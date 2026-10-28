/**
 * @file luat_airui_display_sdl_priv.h
 * @summary AirUI SDL 显示私有数据。输入和文本输入与显示驱动共用这一份，避免各自抄一份再强转。
 */
#ifndef LUAT_AIRUI_DISPLAY_SDL_PRIV_H
#define LUAT_AIRUI_DISPLAY_SDL_PRIV_H

#include "luat_conf_bsp.h"

#if defined(LUAT_USE_AIRUI_SDL2)

#include "lvgl9/lvgl.h"
#include "luat_lcd.h"
#include "luat_display.h"
#include <SDL2/SDL.h>
#if defined(_WIN32)
#include <windows.h>
#endif

typedef struct {
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *texture;
    uint16_t width;
    uint16_t height;
    lv_color_format_t color_format;
    uint8_t reuse_lcd;
    uint8_t reuse_display;
    struct luat_display *display_conf;
    luat_lcd_conf_t *lcd_conf;
    uint8_t *rotation_buf;
    uint32_t rotation_buf_size;
    int last_window_w;
    int last_window_h;
    uint8_t adjusting_window_size;
#if defined(_WIN32)
    HWND hwnd;
    WNDPROC prev_wndproc;
    int frame_w;
    int frame_h;
#endif
    lv_timer_t *overlay_timer;
} sdl_display_data_t;

#endif /* LUAT_USE_AIRUI_SDL2 */

#endif /* LUAT_AIRUI_DISPLAY_SDL_PRIV_H */
