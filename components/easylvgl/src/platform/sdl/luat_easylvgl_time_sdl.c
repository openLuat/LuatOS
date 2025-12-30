/**
 * @file luat_easylvgl_time_sdl.c
 * @summary SDL2 时基实现
 * @responsible SDL2 时基获取和延时
 */

#include "luat_conf_bsp.h"

#if defined(LUAT_USE_EASYLVGL_SDL2)

#include "luat_easylvgl.h"
#include <SDL2/SDL.h>

/**
 * SDL2 时基获取 tick
 * @param ctx 上下文指针
 * @return tick 值（毫秒）
 */
static uint32_t sdl_time_get_tick(easylvgl_ctx_t *ctx)
{
    (void)ctx;
    return SDL_GetTicks();
}

/**
 * SDL2 时基延时
 * @param ctx 上下文指针
 * @param ms 延时毫秒数
 */
static void sdl_time_delay_ms(easylvgl_ctx_t *ctx, uint32_t ms)
{
    (void)ctx;
    SDL_Delay(ms);
}

/** SDL2 时基操作接口 */
static const easylvgl_time_ops_t sdl_time_ops = {
    .get_tick = sdl_time_get_tick,
    .delay_ms = sdl_time_delay_ms
};

/** 获取 SDL2 时基操作接口 */
const easylvgl_time_ops_t *easylvgl_platform_sdl2_get_time_ops(void)
{
    return &sdl_time_ops;
}

#endif /* LUAT_USE_EASYLVGL_SDL2 */

