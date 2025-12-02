/**
 * @file luat_easylvgl_display_sdl.c
 * @summary SDL2 显示驱动实现
 * @responsible SDL2 显示初始化、flush、vsync
 */

#if defined(LUAT_USE_EASYLVGL_SDL2)

#include "luat_easylvgl.h"
#include <SDL2/SDL.h>
#include <string.h>
#include <stdlib.h>

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
    
    // 创建 SDL 纹理（ARGB8888 格式）
    data->texture = SDL_CreateTexture(
        data->renderer,
        SDL_PIXELFORMAT_ARGB8888,
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
    
    // 锁定纹理
    void *pixels;
    int pitch;
    if (SDL_LockTexture(data->texture, NULL, &pixels, &pitch) != 0) {
        return;
    }
    
    // 计算区域大小
    uint32_t w = lv_area_get_width(area);
    uint32_t h = lv_area_get_height(area);
    uint32_t bytes_per_pixel = lv_color_format_get_size(data->color_format);
    
    // 复制像素数据（简化实现：直接复制整个区域）
    // 注意：这里需要根据颜色格式进行转换，阶段一先简化处理
    uint8_t *dst = (uint8_t *)pixels + area->y1 * pitch + area->x1 * bytes_per_pixel;
    const uint8_t *src = px_map;
    
    for (uint32_t y = 0; y < h; y++) {
        memcpy(dst, src, w * bytes_per_pixel);
        dst += pitch;
        src += w * bytes_per_pixel;
    }
    
    // 解锁纹理
    SDL_UnlockTexture(data->texture);
    
    // 渲染到窗口
    SDL_RenderClear(data->renderer);
    SDL_RenderCopy(data->renderer, data->texture, NULL, NULL);
    SDL_RenderPresent(data->renderer);
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

