/**
 * @file luat_airui_display_sdl.c
 * @summary SDL2 显示驱动实现
 * @responsible SDL2 显示初始化、flush、vsync
 */

#include "luat_conf_bsp.h"

#if defined(LUAT_USE_AIRUI_SDL2)

#include "luat_airui.h"
#include "luat_airui_conf.h"
#include "luat_lcd.h"
#include "luat_sdl2.h"
#include "lvgl9/src/draw/lv_draw_buf.h"
#include "lvgl9/src/draw/sw/lv_draw_sw_utils.h"
#include "luat_log.h"
#include <SDL2/SDL.h>
#if defined(_WIN32)
#include <windows.h>
#include <SDL_syswm.h>
#endif
#include <string.h>
#include <stdlib.h>

#define LUAT_LOG_TAG "airui.sdl"
#include "luat_log.h"

// 屏幕适配比例, 当画面超过屏幕长宽时，缩放到屏幕长宽的90%以内
#define AIRUI_SDL_SCREEN_FIT_PERCENT 90

/** SDL 显示驱动私有数据 */
typedef struct {
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *texture;
    uint16_t width;
    uint16_t height;
    lv_color_format_t color_format;
    uint8_t reuse_lcd;
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
} sdl_display_data_t;

static void sdl_display_present_current_frame(sdl_display_data_t *data);

static bool sdl_display_use_upright_preview(void)
{
#if defined(AIRUI_SDL_UPRIGHT_PREVIEW) && AIRUI_SDL_UPRIGHT_PREVIEW
    return true;
#else
    return false;
#endif
}

#if defined(_WIN32)
static void sdl_display_refresh_window_frame(sdl_display_data_t *data)
{
    if (data == NULL || data->hwnd == NULL) {
        return;
    }

    RECT window_rect;
    RECT client_rect;
    if (!GetWindowRect(data->hwnd, &window_rect) || !GetClientRect(data->hwnd, &client_rect)) {
        return;
    }

    data->frame_w = (window_rect.right - window_rect.left) - (client_rect.right - client_rect.left);
    data->frame_h = (window_rect.bottom - window_rect.top) - (client_rect.bottom - client_rect.top);
}

static void sdl_display_apply_aspect_rect(sdl_display_data_t *data, RECT *rect, UINT edge)
{
    if (data == NULL || rect == NULL || data->width <= 0 || data->height <= 0) {
        return;
    }

    int outer_w = rect->right - rect->left;
    int outer_h = rect->bottom - rect->top;
    int client_w = outer_w - data->frame_w;
    int client_h = outer_h - data->frame_h;
    if (client_w <= 0 || client_h <= 0) {
        return;
    }

    int width_driven = 0;
    switch (edge) {
        case WMSZ_LEFT:
        case WMSZ_RIGHT:
            width_driven = 1;
            break;
        case WMSZ_TOP:
        case WMSZ_BOTTOM:
            width_driven = 0;
            break;
        default:
            width_driven = abs(outer_w - data->last_window_w) >= abs(outer_h - data->last_window_h);
            break;
    }

    if (width_driven) {
        int target_client_h = (int)(((int64_t)client_w * data->height + data->width / 2) / data->width);
        int target_outer_h = target_client_h + data->frame_h;
        if (edge == WMSZ_TOP || edge == WMSZ_TOPLEFT || edge == WMSZ_TOPRIGHT) {
            rect->top = rect->bottom - target_outer_h;
        } else {
            rect->bottom = rect->top + target_outer_h;
        }
    } else {
        int target_client_w = (int)(((int64_t)client_h * data->width + data->height / 2) / data->height);
        int target_outer_w = target_client_w + data->frame_w;
        if (edge == WMSZ_LEFT || edge == WMSZ_TOPLEFT || edge == WMSZ_BOTTOMLEFT) {
            rect->left = rect->right - target_outer_w;
        } else {
            rect->right = rect->left + target_outer_w;
        }
    }

    data->last_window_w = rect->right - rect->left;
    data->last_window_h = rect->bottom - rect->top;
}

static LRESULT CALLBACK sdl_display_window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    sdl_display_data_t *data = (sdl_display_data_t *)GetPropA(hwnd, "luatos_airui_sdl_window_data");
    if (msg == WM_SIZING && data != NULL) {
        sdl_display_apply_aspect_rect(data, (RECT *)lparam, (UINT)wparam);
        return TRUE;
    }

    if ((msg == WM_SIZE || msg == WM_PAINT) && data != NULL) {
        LRESULT result = CallWindowProc(data->prev_wndproc, hwnd, msg, wparam, lparam);
        sdl_display_present_current_frame(data);
        return result;
    }

    if (data != NULL && data->prev_wndproc != NULL) {
        return CallWindowProc(data->prev_wndproc, hwnd, msg, wparam, lparam);
    }
    return DefWindowProc(hwnd, msg, wparam, lparam);
}

static void sdl_display_install_native_resize_hook(sdl_display_data_t *data)
{
    if (data == NULL || data->window == NULL || data->prev_wndproc != NULL) {
        return;
    }

    SDL_SysWMinfo wm_info;
    SDL_VERSION(&wm_info.version);
    if (!SDL_GetWindowWMInfo(data->window, &wm_info) || wm_info.subsystem != SDL_SYSWM_WINDOWS) {
        return;
    }

    data->hwnd = wm_info.info.win.window;
    SetPropA(data->hwnd, "luatos_airui_sdl_window_data", data);
    data->prev_wndproc = (WNDPROC)SetWindowLongPtr(data->hwnd, GWLP_WNDPROC, (LONG_PTR)sdl_display_window_proc);
    sdl_display_refresh_window_frame(data);
}

static void sdl_display_uninstall_native_resize_hook(sdl_display_data_t *data)
{
    if (data == NULL || data->hwnd == NULL) {
        return;
    }

    RemovePropA(data->hwnd, "luatos_airui_sdl_window_data");
    if (data->prev_wndproc != NULL) {
        SetWindowLongPtr(data->hwnd, GWLP_WNDPROC, (LONG_PTR)data->prev_wndproc);
    }
    data->hwnd = NULL;
    data->prev_wndproc = NULL;
}

static void sdl_display_update_native_aspect(sdl_display_data_t *data)
{
    if (data == NULL) {
        return;
    }
    sdl_display_refresh_window_frame(data);
}
#else
static void sdl_display_install_native_resize_hook(sdl_display_data_t *data) { (void)data; }
static void sdl_display_uninstall_native_resize_hook(sdl_display_data_t *data) { (void)data; }
static void sdl_display_update_native_aspect(sdl_display_data_t *data) { (void)data; }
#endif

static void sdl_display_get_usable_bounds(SDL_Window *window, SDL_Rect *usable_bounds)
{
    if (usable_bounds == NULL) {
        return;
    }

    int display_index = 0;
    if (window != NULL) {
        display_index = SDL_GetWindowDisplayIndex(window);
        if (display_index < 0) {
            display_index = 0;
        }
    }

    if (SDL_GetDisplayUsableBounds(display_index, usable_bounds) != 0) {
        usable_bounds->x = 0;
        usable_bounds->y = 0;
        usable_bounds->w = 0;
        usable_bounds->h = 0;
    }
}

static void sdl_display_calc_fitted_size(int container_w, int container_h,
                                         int content_w, int content_h,
                                         int max_percent,
                                         int *target_w, int *target_h)
{
    if (target_w == NULL || target_h == NULL || container_w <= 0 || container_h <= 0 || content_w <= 0 || content_h <= 0) {
        return;
    }

    int max_w = container_w * max_percent / 100;
    int max_h = container_h * max_percent / 100;
    if (max_w <= 0) {
        max_w = container_w;
    }
    if (max_h <= 0) {
        max_h = container_h;
    }

    if (content_w <= max_w && content_h <= max_h) {
        *target_w = content_w;
        *target_h = content_h;
        return;
    }

    int fitted_w = max_w;
    int fitted_h = (int)((int64_t)content_h * fitted_w / content_w);
    if (fitted_h > max_h) {
        fitted_h = max_h;
        fitted_w = (int)((int64_t)content_w * fitted_h / content_h);
    }

    if (fitted_w <= 0) {
        fitted_w = 1;
    }
    if (fitted_h <= 0) {
        fitted_h = 1;
    }

    *target_w = fitted_w;
    *target_h = fitted_h;
}

static void sdl_display_get_target_window_size(SDL_Window *window, int content_w, int content_h,
                                               int *target_w, int *target_h)
{
    SDL_Rect usable_bounds;
    sdl_display_get_usable_bounds(window, &usable_bounds);
    if (usable_bounds.w <= 0 || usable_bounds.h <= 0) {
        *target_w = content_w;
        *target_h = content_h;
        return;
    }

    sdl_display_calc_fitted_size(usable_bounds.w, usable_bounds.h,
                                 content_w, content_h,
                                 AIRUI_SDL_SCREEN_FIT_PERCENT,
                                 target_w, target_h);
}

static void sdl_display_present_current_frame(sdl_display_data_t *data)
{
    if (data == NULL || data->renderer == NULL || data->texture == NULL) {
        return;
    }

    SDL_RenderClear(data->renderer);
    SDL_RenderCopy(data->renderer, data->texture, NULL, NULL);
    SDL_RenderPresent(data->renderer);
}

// 将窗口居中显示
static void sdl_display_center_window(SDL_Window *window)
{
    if (window == NULL) {
        return;
    }

    int window_w = 0;
    int window_h = 0;
    SDL_GetWindowSize(window, &window_w, &window_h);
    if (window_w <= 0 || window_h <= 0) {
        return;
    }

    SDL_Rect usable_bounds;
    sdl_display_get_usable_bounds(window, &usable_bounds);
    if (usable_bounds.w <= 0 || usable_bounds.h <= 0) {
        SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
        return;
    }

    int pos_x = usable_bounds.x + (usable_bounds.w - window_w) / 2;
    int pos_y = usable_bounds.y + (usable_bounds.h - window_h) / 2;
    SDL_SetWindowPosition(window, pos_x, pos_y);
}

static void sdl_display_sync_lcd_preview(airui_ctx_t *ctx, sdl_display_data_t *data)
{
    if (ctx == NULL || data == NULL || !data->reuse_lcd) {
        return;
    }

    luat_sdl2_set_upright_preview(
        sdl_display_use_upright_preview() ? 1 : 0,
        (uint16_t)airui_display_get_rotation(ctx),
        ctx->native_width,
        ctx->native_height
    );
}

static void sdl_display_get_preview_size(airui_ctx_t *ctx, uint16_t native_w, uint16_t native_h,
                                         uint16_t *preview_w, uint16_t *preview_h)
{
    if (preview_w == NULL || preview_h == NULL) {
        return;
    }

    *preview_w = native_w;
    *preview_h = native_h;

    if (ctx == NULL || ctx->display == NULL || !sdl_display_use_upright_preview()) {
        return;
    }

    *preview_w = (uint16_t)lv_display_get_horizontal_resolution(ctx->display);
    *preview_h = (uint16_t)lv_display_get_vertical_resolution(ctx->display);
}

static int sdl_display_ensure_preview_target(airui_ctx_t *ctx, sdl_display_data_t *data)
{
    if (ctx == NULL || data == NULL || data->reuse_lcd) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    uint16_t preview_w = 0;
    uint16_t preview_h = 0;
    sdl_display_get_preview_size(ctx, data->width, data->height, &preview_w, &preview_h);

    if (preview_w == 0 || preview_h == 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (data->texture == NULL || preview_w != data->width || preview_h != data->height) {
        Uint32 sdl_format;
        if (data->color_format == LV_COLOR_FORMAT_RGB565) {
            sdl_format = SDL_PIXELFORMAT_RGB565;
        } else {
            sdl_format = SDL_PIXELFORMAT_ARGB8888;
        }

        if (data->texture != NULL) {
            SDL_DestroyTexture(data->texture);
            data->texture = NULL;
        }

        data->texture = SDL_CreateTexture(data->renderer, sdl_format, SDL_TEXTUREACCESS_STREAMING, preview_w, preview_h);
        if (data->texture == NULL) {
            return AIRUI_ERR_INIT_FAILED;
        }

        int target_w = 0;
        int target_h = 0;
        sdl_display_get_target_window_size(data->window, preview_w, preview_h, &target_w, &target_h);
        if (target_w > 0 && target_h > 0) {
            SDL_SetWindowSize(data->window, target_w, target_h);
            data->last_window_w = target_w;
            data->last_window_h = target_h;
        }
        sdl_display_update_native_aspect(data);
        sdl_display_center_window(data->window);
    }

    data->width = preview_w;
    data->height = preview_h;
    return AIRUI_OK;
}

static uint8_t *sdl_display_get_rotation_buf(sdl_display_data_t *data, uint32_t size)
{
    if (data == NULL || size == 0) {
        return NULL;
    }

    if (data->rotation_buf != NULL && data->rotation_buf_size >= size) {
        return data->rotation_buf;
    }

    uint8_t *new_buf = (uint8_t *)realloc(data->rotation_buf, size);
    if (new_buf == NULL) {
        return NULL;
    }

    data->rotation_buf = new_buf;
    data->rotation_buf_size = size;
    return data->rotation_buf;
}

/**
 * SDL2 显示驱动初始化
 * @param ctx 上下文指针
 * @param w 屏幕宽度
 * @param h 屏幕高度
 * @param fmt 颜色格式
 * @return 0 成功，<0 失败
 */
static int sdl_display_init(airui_ctx_t *ctx, uint16_t w, uint16_t h, lv_color_format_t fmt)
{
    if (ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    // 初始化 SDL（如果尚未初始化）
    static bool sdl_inited = false;
    if (!sdl_inited) {
        if (SDL_Init(SDL_INIT_VIDEO) < 0) {
            return AIRUI_ERR_INIT_FAILED;
        }
        // 启用 SDL 输入法 UI
        SDL_SetHint(SDL_HINT_IME_SHOW_UI, "1");
        sdl_inited = true;
    }
    
    // 分配私有数据
    sdl_display_data_t *data = malloc(sizeof(sdl_display_data_t));
    if (data == NULL) {
        return AIRUI_ERR_NO_MEM;
    }
    memset(data, 0, sizeof(sdl_display_data_t));
    
    data->width = w;
    data->height = h;
    data->color_format = fmt;

    luat_lcd_conf_t *lcd_conf = luat_lcd_get_default();
    if (lcd_conf != NULL && lcd_conf->opts != NULL && lcd_conf->opts->name != NULL && strcmp(lcd_conf->opts->name, "sdl2") == 0) {
        data->window = (SDL_Window *)luat_sdl2_get_window();
        data->reuse_lcd = 1;
        data->lcd_conf = lcd_conf;
        lcd_conf->lcd_use_lvgl = 1;
        ctx->platform_data = data;
        sdl_display_sync_lcd_preview(ctx, data);
        LLOGI("reuse lcd sdl2 window for airui");
        return AIRUI_OK;
    }
    
    uint16_t preview_w = w;
    uint16_t preview_h = h;
    sdl_display_get_preview_size(ctx, w, h, &preview_w, &preview_h);

    int window_w = 0;
    int window_h = 0;
    sdl_display_get_target_window_size(NULL, preview_w, preview_h, &window_w, &window_h);
    if (window_w <= 0 || window_h <= 0) {
        window_w = preview_w;
        window_h = preview_h;
    }

    // 创建 SDL 窗口
    data->window = SDL_CreateWindow(
        "AIRUI",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        window_w,
        window_h,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI
    );
    
    if (data->window == NULL) {
        free(data);
        return AIRUI_ERR_INIT_FAILED;
    }

    // 将窗口居中显示
    sdl_display_center_window(data->window);
    data->last_window_w = window_w;
    data->last_window_h = window_h;
    sdl_display_install_native_resize_hook(data);
    sdl_display_update_native_aspect(data);
    
    // 创建 SDL 渲染器
    data->renderer = SDL_CreateRenderer(data->window, -1, SDL_RENDERER_ACCELERATED);
    if (data->renderer == NULL) {
        SDL_DestroyWindow(data->window);
        free(data);
        return AIRUI_ERR_INIT_FAILED;
    }
    
    // 根据颜色格式选择 SDL 像素格式
    Uint32 sdl_format;
    if (fmt == LV_COLOR_FORMAT_RGB565) {
        sdl_format = SDL_PIXELFORMAT_RGB565;
    } else if (fmt == LV_COLOR_FORMAT_ARGB8888) {
        sdl_format = SDL_PIXELFORMAT_ARGB8888;
    } else {
        // 默认使用 ARGB8888
        sdl_format = SDL_PIXELFORMAT_ARGB8888;
    }
    
    // 创建 SDL 纹理（使用对应的格式）
    data->texture = SDL_CreateTexture(
        data->renderer,
        sdl_format,
        SDL_TEXTUREACCESS_STREAMING,
        preview_w,
        preview_h
    );
    
    if (data->texture == NULL) {
        SDL_DestroyRenderer(data->renderer);
        SDL_DestroyWindow(data->window);
        free(data);
        return AIRUI_ERR_INIT_FAILED;
    }
    
    data->width = preview_w;
    data->height = preview_h;
    ctx->platform_data = data;
    return AIRUI_OK;
}

/**
 * SDL2 显示驱动 flush
 * @param ctx 上下文指针
 * @param area 刷新区域
 * @param px_map 像素数据
 */
static void sdl_display_flush(airui_ctx_t *ctx, const lv_area_t *area, const uint8_t *px_map)
{
    if (ctx == NULL || ctx->platform_data == NULL) {
        return;
    }
    
    sdl_display_data_t *data = (sdl_display_data_t *)ctx->platform_data;
    
    if (px_map == NULL) {
        return;
    }

    if (data->reuse_lcd) {
        sdl_display_sync_lcd_preview(ctx, data);
        if (data->lcd_conf == NULL) {
            lv_display_flush_ready(ctx->display);
            return;
        }

        lv_display_rotation_t rotation = lv_display_get_rotation(ctx->display);
        if (rotation == LV_DISPLAY_ROTATION_0) {
            luat_lcd_draw(data->lcd_conf, area->x1, area->y1, area->x2, area->y2, (luat_color_t *)px_map);
        }
        else {
            lv_area_t rotated_area = *area;
            lv_color_format_t cf = lv_display_get_color_format(ctx->display);
            uint32_t px_size = lv_color_format_get_size(cf);
            uint32_t src_w = (uint32_t)lv_area_get_width(area);
            uint32_t src_h = (uint32_t)lv_area_get_height(area);
            uint32_t src_stride = src_w * px_size;

            lv_display_rotate_area(ctx->display, &rotated_area);

            uint32_t dest_w = (uint32_t)lv_area_get_width(&rotated_area);
            uint32_t dest_h = (uint32_t)lv_area_get_height(&rotated_area);
            uint32_t dest_stride = dest_w * px_size;
            uint32_t rotate_buf_size = dest_stride * dest_h;
            uint8_t *rotate_buf = sdl_display_get_rotation_buf(data, rotate_buf_size);
            if (rotate_buf == NULL) {
                lv_display_flush_ready(ctx->display);
                return;
            }

            lv_draw_sw_rotate(px_map, rotate_buf, (int32_t)src_w, (int32_t)src_h,
                              (int32_t)src_stride, (int32_t)dest_stride, rotation, cf);
            luat_lcd_draw(data->lcd_conf, rotated_area.x1, rotated_area.y1, rotated_area.x2, rotated_area.y2,
                          (luat_color_t *)rotate_buf);
        }

        if (lv_display_flush_is_last(ctx->display)) {
            luat_lcd_flush(data->lcd_conf);
        }
        lv_display_flush_ready(ctx->display);
        return;
    }

    if (sdl_display_ensure_preview_target(ctx, data) != AIRUI_OK) {
        lv_display_flush_ready(ctx->display);
        return;
    }

    if (data->texture == NULL) {
        lv_display_flush_ready(ctx->display);
        return;
    }
    
    
    // 边界检查
    int32_t hor_res = lv_display_get_horizontal_resolution(ctx->display);
    int32_t ver_res = lv_display_get_vertical_resolution(ctx->display);
    
    if (area->x2 < 0 || area->y2 < 0 || area->x1 > hor_res - 1 || area->y1 > ver_res - 1) {
        return;
    }
    
    
    lv_display_rotation_t rotation = lv_display_get_rotation(ctx->display);
    lv_area_t draw_area = *area;
    const uint8_t *draw_px_map = px_map;
    bool rotated = false;
    if (!sdl_display_use_upright_preview() && rotation != LV_DISPLAY_ROTATION_0) {
        lv_color_format_t cf = data->color_format;
        uint32_t px_size = lv_color_format_get_size(cf);
        uint32_t src_w = (uint32_t)lv_area_get_width(area);
        uint32_t src_h = (uint32_t)lv_area_get_height(area);
        uint32_t src_stride = src_w * px_size;

        lv_display_rotate_area(ctx->display, &draw_area);

        uint32_t dest_w = (uint32_t)lv_area_get_width(&draw_area);
        uint32_t dest_h = (uint32_t)lv_area_get_height(&draw_area);
        uint32_t dest_stride = dest_w * px_size;
        uint32_t rotate_buf_size = dest_stride * dest_h;
        uint8_t *rotate_buf = sdl_display_get_rotation_buf(data, rotate_buf_size);
        if (rotate_buf == NULL) {
            lv_display_flush_ready(ctx->display);
            return;
        }

        lv_draw_sw_rotate(px_map, rotate_buf, (int32_t)src_w, (int32_t)src_h,
                          (int32_t)src_stride, (int32_t)dest_stride, rotation, cf);
        draw_px_map = rotate_buf;
        rotated = true;
    }

    // 计算区域大小
    uint32_t w = lv_area_get_width(&draw_area);
    uint32_t h = lv_area_get_height(&draw_area);
    uint32_t bytes_per_pixel = lv_color_format_get_size(data->color_format);
    
    // 使用 SDL_UpdateTexture 更新部分区域（类似重构前的 luat_sdl2_draw）
    // 这比 LockTexture + memcpy + UnlockTexture 更高效
    SDL_Rect rect = {
        .x = draw_area.x1,
        .y = draw_area.y1,
        .w = (int)w,
        .h = (int)h
    };
    
    // 计算 px_map 的实际 stride
    // 在 PARTIAL 模式下，px_map 的数据可能是紧密打包的（区域宽度），
    // 但为了安全，我们使用 LockTexture + 逐行复制的方式
    uint32_t px_map_stride = rotated ? (w * bytes_per_pixel) : lv_draw_buf_width_to_stride(w, data->color_format);
    uint32_t px_map_line_bytes = w * bytes_per_pixel;  // 每行实际数据字节数
    
    
    // 使用 LockTexture + 逐行复制的方式（更安全，可以处理对齐的 stride）
    void *texture_pixels;
    int texture_pitch;
    if (SDL_LockTexture(data->texture, &rect, &texture_pixels, &texture_pitch) != 0) {
        const char *error = SDL_GetError();
        LLOGE("SDL_LockTexture failed: %s", error);
        return;
    }
    
    // 逐行复制数据
    const uint8_t *src = draw_px_map;
    uint8_t *dst = (uint8_t *)texture_pixels;

    for (uint32_t y = 0; y < h; y++) {
        memcpy(dst, src, px_map_line_bytes);
        src += px_map_stride;  // 使用区域宽度的 stride
        dst += texture_pitch;  // 使用纹理的 pitch
    }
    
    SDL_UnlockTexture(data->texture);
    
    // 关键：只在最后一块区域时才刷新到屏幕
    // 这样可以避免在 PARTIAL 模式下频繁 Present，提高性能并避免闪烁
    bool is_last = lv_display_flush_is_last(ctx->display);

    if (is_last) {
        SDL_RenderClear(data->renderer);
        if (SDL_RenderCopy(data->renderer, data->texture, NULL, NULL) != 0) {
            const char *error = SDL_GetError();
            LLOGE("SDL_RenderCopy failed: %s", error);
            // 即便渲染失败也要通知 LVGL 完成，避免卡死
        } else {
            SDL_RenderPresent(data->renderer);
        }
    }
    // SDL 是同步的，直接标记完成
    lv_display_flush_ready(ctx->display);
}

/**
 * SDL2 显示驱动等待垂直同步
 * @param ctx 上下文指针
 */
static void sdl_display_wait_vsync(airui_ctx_t *ctx)
{
    // SDL 自动处理 vsync
    (void)ctx;
}

/**
 * SDL2 显示驱动反初始化
 * @param ctx 上下文指针
 */
static void sdl_display_deinit(airui_ctx_t *ctx)
{
    if (ctx == NULL || ctx->platform_data == NULL) {
        return;
    }
    
    sdl_display_data_t *data = (sdl_display_data_t *)ctx->platform_data;

    if (data->reuse_lcd) {
        luat_sdl2_set_upright_preview(0, 0, 0, 0);
        if (data->lcd_conf != NULL) {
            data->lcd_conf->lcd_use_lvgl = 0;
        }
        if (data->rotation_buf != NULL) {
            free(data->rotation_buf);
            data->rotation_buf = NULL;
            data->rotation_buf_size = 0;
        }
        free(data);
        ctx->platform_data = NULL;
        return;
    }
    
    if (data->texture != NULL) {
        SDL_DestroyTexture(data->texture);
        data->texture = NULL;
    }
    
    if (data->renderer != NULL) {
        SDL_DestroyRenderer(data->renderer);
        data->renderer = NULL;
    }
    
    if (data->window != NULL) {
        sdl_display_uninstall_native_resize_hook(data);
        SDL_DestroyWindow(data->window);
        data->window = NULL;
    }

    if (data->rotation_buf != NULL) {
        free(data->rotation_buf);
        data->rotation_buf = NULL;
        data->rotation_buf_size = 0;
    }
    
    free(data);
    ctx->platform_data = NULL;
}

/** SDL2 显示驱动操作接口 */
static const airui_display_ops_t sdl_display_ops = {
    .init = sdl_display_init,
    .flush = sdl_display_flush,
    .wait_vsync = sdl_display_wait_vsync,
    .deinit = sdl_display_deinit
};

/** 获取 SDL2 显示驱动操作接口 */
const airui_display_ops_t *airui_platform_sdl2_get_display_ops(void)
{
    return &sdl_display_ops;
}

#endif /* LUAT_USE_AIRUI_SDL2 */

