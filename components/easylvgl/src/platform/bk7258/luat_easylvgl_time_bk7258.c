/**
 * @file luat_easylvgl_time_bk7258.c
 * @summary BK7258 时基实现
 * @responsible 提供 tick 获取与毫秒延时
 */
#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_EASYLVGL_BK7258)

#include "luat_easylvgl.h"
#include "luat_mcu.h"
#include "luat_rtos.h"

/**
 * 获取毫秒 tick
 */
static uint32_t bk7258_time_get_tick(easylvgl_ctx_t *ctx)
{
    (void)ctx;
    return (uint32_t)luat_mcu_tick64_ms();
}

/**
 * 毫秒延时
 */
static void bk7258_time_delay_ms(easylvgl_ctx_t *ctx, uint32_t ms)
{
    (void)ctx;
    luat_rtos_task_sleep(ms);
}

static const easylvgl_time_ops_t bk7258_time_ops = {
    .get_tick = bk7258_time_get_tick,
    .delay_ms = bk7258_time_delay_ms
};

const easylvgl_time_ops_t *easylvgl_platform_bk7258_get_time_ops(void)
{
    return &bk7258_time_ops;
}

#endif /* LUAT_USE_EASYLVGL_BK7258 */


