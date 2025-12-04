/**
 * @file luat_easylvgl_display_sdl.c
 * @summary SDL2 显示驱动实现
 * @responsible SDL2 显示初始化、flush、vsync
 */

#if defined(LUAT_USE_EASYLVGL_SDL2)

#include "luat_easylvgl.h"
#include "lvgl9/src/draw/lv_draw_buf.h"
#include "luat_log.h"
#include <SDL2/SDL.h>
#include <string.h>
#include <stdlib.h>

#define LUAT_LOG_TAG "easylvgl.sdl"
#include "luat_log.h"

/** SDL 显示驱动私有数据 */
typedef struct {
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *texture;
    uint16_t width;
    uint16_t height;
    lv_color_format_t color_format;
} sdl_display_data_t;

/**
 * SDL2 显示驱动初始化
 * @param ctx 上下文指针
 * @param w 屏幕宽度
 * @param h 屏幕高度
 * @param fmt 颜色格式
 * @return 0 成功，<0 失败
 */
static int sdl_display_init(easylvgl_ctx_t *ctx, uint16_t w, uint16_t h, lv_color_format_t fmt)
{
    if (ctx == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    // 初始化 SDL（如果尚未初始化）
    static bool sdl_inited = false;
    if (!sdl_inited) {
        if (SDL_Init(SDL_INIT_VIDEO) < 0) {
            return EASYLVGL_ERR_INIT_FAILED;
        }
        sdl_inited = true;
    }
    
    // 分配私有数据
    sdl_display_data_t *data = malloc(sizeof(sdl_display_data_t));
    if (data == NULL) {
        return EASYLVGL_ERR_NO_MEM;
    }
    memset(data, 0, sizeof(sdl_display_data_t));
    
    data->width = w;
    data->height = h;
    data->color_format = fmt;
    
    // 创建 SDL 窗口
    data->window = SDL_CreateWindow(
        "EasyLVGL",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        w,
        h,
        SDL_WINDOW_SHOWN
    );
    
    if (data->window == NULL) {
        free(data);
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    // 创建 SDL 渲染器
    data->renderer = SDL_CreateRenderer(data->window, -1, SDL_RENDERER_ACCELERATED);
    if (data->renderer == NULL) {
        SDL_DestroyWindow(data->window);
        free(data);
        return EASYLVGL_ERR_INIT_FAILED;
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
        w,
        h
    );
    
    if (data->texture == NULL) {
        SDL_DestroyRenderer(data->renderer);
        SDL_DestroyWindow(data->window);
        free(data);
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    ctx->platform_data = data;
    return EASYLVGL_OK;
}

/**
 * SDL2 显示驱动 flush
 * @param ctx 上下文指针
 * @param area 刷新区域
 * @param px_map 像素数据
 */
static void sdl_display_flush(easylvgl_ctx_t *ctx, const lv_area_t *area, const uint8_t *px_map)
{
    if (ctx == NULL || ctx->platform_data == NULL) {
        return;
    }
    
    sdl_display_data_t *data = (sdl_display_data_t *)ctx->platform_data;
    
    if (data->texture == NULL || px_map == NULL) {
        return;
    }
    
    
    // 边界检查
    int32_t hor_res = lv_display_get_horizontal_resolution(ctx->display);
    int32_t ver_res = lv_display_get_vertical_resolution(ctx->display);
    
    if (area->x2 < 0 || area->y2 < 0 || area->x1 > hor_res - 1 || area->y1 > ver_res - 1) {
        return;
    }
    
    
    // 计算区域大小
    uint32_t w = lv_area_get_width(area);
    uint32_t h = lv_area_get_height(area);
    uint32_t bytes_per_pixel = lv_color_format_get_size(data->color_format);
    
    // 使用 SDL_UpdateTexture 更新部分区域（类似重构前的 luat_sdl2_draw）
    // 这比 LockTexture + memcpy + UnlockTexture 更高效
    SDL_Rect rect = {
        .x = area->x1,
        .y = area->y1,
        .w = (int)w,
        .h = (int)h
    };
    
    // 计算 px_map 的实际 stride
    // 在 PARTIAL 模式下，px_map 的数据可能是紧密打包的（区域宽度），
    // 但为了安全，我们使用 LockTexture + 逐行复制的方式
    uint32_t px_map_stride = lv_draw_buf_width_to_stride(w, data->color_format);  // 区域宽度的 stride
    uint32_t px_map_line_bytes = w * bytes_per_pixel;  // 每行实际数据字节数
    
    
    // 使用 LockTexture + 逐行复制的方式（更安全，可以处理对齐的 stride）
    void *texture_pixels;
    int texture_pitch;
    if (SDL_LockTexture(data->texture, &rect, &texture_pixels, &texture_pitch) != 0) {
        const char *error = SDL_GetError();
        return;
    }
    
    // 逐行复制数据
    const uint8_t *src = px_map;
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
        // 渲染到窗口（不清除，直接复制整个纹理）
        // 注意：不要调用 SDL_RenderClear，因为这会清除之前的内容
        if (SDL_RenderCopy(data->renderer, data->texture, NULL, NULL) != 0) {
            const char *error = SDL_GetError();
            return;
        }
        SDL_RenderPresent(data->renderer);
    }
    // 注意：lv_display_flush_ready() 已经在 display_flush_cb 中调用了
}

/**
 * SDL2 显示驱动等待垂直同步
 * @param ctx 上下文指针
 */
static void sdl_display_wait_vsync(easylvgl_ctx_t *ctx)
{
    // SDL 自动处理 vsync
    (void)ctx;
}

/**
 * SDL2 显示驱动反初始化
 * @param ctx 上下文指针
 */
static void sdl_display_deinit(easylvgl_ctx_t *ctx)
{
    if (ctx == NULL || ctx->platform_data == NULL) {
        return;
    }
    
    sdl_display_data_t *data = (sdl_display_data_t *)ctx->platform_data;
    
    if (data->texture != NULL) {
        SDL_DestroyTexture(data->texture);
        data->texture = NULL;
    }
    
    if (data->renderer != NULL) {
        SDL_DestroyRenderer(data->renderer);
        data->renderer = NULL;
    }
    
    if (data->window != NULL) {
        SDL_DestroyWindow(data->window);
        data->window = NULL;
    }
    
    free(data);
    ctx->platform_data = NULL;
}

/** SDL2 显示驱动操作接口 */
static const easylvgl_display_ops_t sdl_display_ops = {
    .init = sdl_display_init,
    .flush = sdl_display_flush,
    .wait_vsync = sdl_display_wait_vsync,
    .deinit = sdl_display_deinit
};

/** 获取 SDL2 显示驱动操作接口 */
const easylvgl_display_ops_t *easylvgl_platform_sdl2_get_display_ops(void)
{
    return &sdl_display_ops;
}

#endif /* LUAT_USE_EASYLVGL_SDL2 */

