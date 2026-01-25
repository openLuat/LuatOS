/**
 * @file luat_airui_time_luatos.c
 * @summary LuatOS 时基实现
 * @responsible 提供 tick 获取与毫秒延时
 */
#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui.h"
#include "luat_mcu.h"
#include "luat_rtos.h"

/**
 * 获取毫秒 tick
 */
static uint32_t luatos_time_get_tick(airui_ctx_t *ctx)
{
    (void)ctx;
    return (uint32_t)luat_mcu_tick64_ms();
}

/**
 * 毫秒延时
 */
static void luatos_time_delay_ms(airui_ctx_t *ctx, uint32_t ms)
{
    (void)ctx;
    luat_rtos_task_sleep(ms);
}

static const airui_time_ops_t luatos_time_ops = {
    .get_tick = luatos_time_get_tick,
    .delay_ms = luatos_time_delay_ms
};

const airui_time_ops_t *airui_platform_luatos_get_time_ops(void)
{
    return &luatos_time_ops;
}

#endif /* LUAT_USE_AIRUI_LUATOS */   


