#include "luat_base.h"
#include "luat_display_sdl2.h"
#include "luat_mem.h"

#include "SDL2/SDL.h"

#define LUAT_LOG_TAG "display_sdl2"
#include "luat_log.h"

struct luat_display_sdl2_ctx {
    SDL_Window   *window;
    SDL_Renderer *renderer;
    SDL_Texture  *texture;
    uint32_t      width;
    uint32_t      height;
    uint8_t       exit_requested;
};

static uint8_t sdl_video_inited = 0;

static int luat_display_sdl2_init_video(void)
{
    if (sdl_video_inited) {
        return 0;
    }
    if (SDL_InitSubSystem(SDL_INIT_VIDEO) != 0) {
        LLOGE("SDL_InitSubSystem(SDL_INIT_VIDEO) failed: %s", SDL_GetError());
        return -1;
    }
    sdl_video_inited = 1;
    return 0;
}

static void luat_display_sdl2_calc_fitted_size(uint32_t native_w, uint32_t native_h,
                                               int *out_w, int *out_h)
{
    SDL_Rect usable;
    usable.x = 0;
    usable.y = 0;
    usable.w = (int)native_w;
    usable.h = (int)native_h;

    if (SDL_GetDisplayUsableBounds(0, &usable) != 0) {
        *out_w = (int)native_w;
        *out_h = (int)native_h;
        return;
    }

    int max_w = usable.w * 90 / 100;
    int max_h = usable.h * 90 / 100;
    if (max_w <= 0) max_w = usable.w;
    if (max_h <= 0) max_h = usable.h;

    if ((int)native_w <= max_w && (int)native_h <= max_h) {
        *out_w = (int)native_w;
        *out_h = (int)native_h;
        return;
    }

    int fitted_w = max_w;
    int fitted_h = (int)((int64_t)native_h * fitted_w / native_w);
    if (fitted_h > max_h) {
        fitted_h = max_h;
        fitted_w = (int)((int64_t)native_w * fitted_h / native_h);
    }
    if (fitted_w <= 0) fitted_w = 1;
    if (fitted_h <= 0) fitted_h = 1;

    *out_w = fitted_w;
    *out_h = fitted_h;
}

luat_display_sdl2_ctx_t* luat_display_sdl2_create(const char *title, uint32_t width, uint32_t height)
{
    if (width == 0 || height == 0) {
        return NULL;
    }

    if (luat_display_sdl2_init_video() != 0) {
        return NULL;
    }

    luat_display_sdl2_ctx_t *ctx = luat_heap_zalloc(sizeof(luat_display_sdl2_ctx_t));
    if (ctx == NULL) {
        LLOGE("alloc display_sdl2 ctx failed");
        return NULL;
    }

    ctx->width = width;
    ctx->height = height;

    int win_w = 0;
    int win_h = 0;
    luat_display_sdl2_calc_fitted_size(width, height, &win_w, &win_h);

    ctx->window = SDL_CreateWindow(title ? title : "LuatOS Display",
                                   SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                   win_w, win_h,
                                   SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    if (ctx->window == NULL) {
        LLOGE("SDL_CreateWindow failed: %s", SDL_GetError());
        luat_heap_free(ctx);
        return NULL;
    }

    ctx->renderer = SDL_CreateRenderer(ctx->window, -1,
                                       SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (ctx->renderer == NULL) {
        LLOGE("SDL_CreateRenderer failed: %s", SDL_GetError());
        SDL_DestroyWindow(ctx->window);
        luat_heap_free(ctx);
        return NULL;
    }

    ctx->texture = SDL_CreateTexture(ctx->renderer,
                                     SDL_PIXELFORMAT_RGB565,
                                     SDL_TEXTUREACCESS_STREAMING,
                                     (int)width,
                                     (int)height);
    if (ctx->texture == NULL) {
        LLOGE("SDL_CreateTexture failed: %s", SDL_GetError());
        SDL_DestroyRenderer(ctx->renderer);
        SDL_DestroyWindow(ctx->window);
        luat_heap_free(ctx);
        return NULL;
    }

    SDL_SetRenderDrawColor(ctx->renderer, 0, 0, 0, 255);
    SDL_RenderClear(ctx->renderer);
    SDL_RenderPresent(ctx->renderer);

    return ctx;
}

void luat_display_sdl2_destroy(luat_display_sdl2_ctx_t *ctx)
{
    if (ctx == NULL) {
        return;
    }
    if (ctx->texture) {
        SDL_DestroyTexture(ctx->texture);
        ctx->texture = NULL;
    }
    if (ctx->renderer) {
        SDL_DestroyRenderer(ctx->renderer);
        ctx->renderer = NULL;
    }
    if (ctx->window) {
        SDL_DestroyWindow(ctx->window);
        ctx->window = NULL;
    }
    luat_heap_free(ctx);
}

void luat_display_sdl2_draw(luat_display_sdl2_ctx_t *ctx, int16_t x, int16_t y,
                            uint16_t w, uint16_t h, const void *data, uint32_t pitch)
{
    if (ctx == NULL || ctx->texture == NULL || data == NULL || w == 0 || h == 0) {
        return;
    }

    SDL_Rect r;
    r.x = x;
    r.y = y;
    r.w = w;
    r.h = h;

    if (pitch == 0) {
        pitch = (uint32_t)w * 2; /* RGB565 default */
    }

    SDL_UpdateTexture(ctx->texture, &r, data, (int)pitch);
}

static void luat_display_sdl2_present(luat_display_sdl2_ctx_t *ctx)
{
    if (ctx == NULL || ctx->renderer == NULL || ctx->texture == NULL) {
        return;
    }
    SDL_RenderClear(ctx->renderer);
    SDL_RenderCopy(ctx->renderer, ctx->texture, NULL, NULL);
    SDL_RenderPresent(ctx->renderer);
}

void luat_display_sdl2_flush(luat_display_sdl2_ctx_t *ctx)
{
    if (ctx == NULL) {
        return;
    }
    luat_display_sdl2_present(ctx);
}

void luat_display_sdl2_pump_events(luat_display_sdl2_ctx_t *ctx)
{
    if (ctx == NULL || ctx->window == NULL) {
        return;
    }

    SDL_Event e;
    Uint32 my_id = SDL_GetWindowID(ctx->window);

    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) {
            ctx->exit_requested = 1;
            continue;
        }
        if (e.type == SDL_WINDOWEVENT && e.window.windowID == my_id) {
            if (e.window.event == SDL_WINDOWEVENT_EXPOSED ||
                e.window.event == SDL_WINDOWEVENT_RESIZED) {
                luat_display_sdl2_present(ctx);
            }
        }
    }
}

int luat_display_sdl2_is_exit_requested(luat_display_sdl2_ctx_t *ctx)
{
    return ctx ? ctx->exit_requested : 0;
}
