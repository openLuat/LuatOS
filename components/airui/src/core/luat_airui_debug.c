/**
 * @file luat_airui_debug.c
 * @brief AirUI 调试模块：FPS、内存占用、组件数量等性能统计
 */

#include "luat_airui.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include <stdint.h>

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

static luat_rtos_timer_t g_airui_debug_perf_timer = NULL;

/**
 * @brief 显示刷新事件回调，用于统计每秒钟的刷新次数（FPS 计算）
 * @param e LVGL 事件对象，事件码需为 LV_EVENT_REFR_READY
 */
static void airui_debug_display_event_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) != LV_EVENT_REFR_READY) {
        return;
    }

    airui_ctx_t *ctx = (airui_ctx_t *)lv_event_get_user_data(e);
    if (ctx == NULL) {
        return;
    }

    if (ctx->debug_refr_count < UINT32_MAX) {
        ctx->debug_refr_count++;
    }
}

/**
 * @brief 性能统计消息处理，在主线程中执行，计算 FPS、内存占用并输出日志
 * @param ptr 指向 airui_ctx_t 的指针
 * @return 0 表示处理完成
 */
static int airui_debug_perf_msg_handler(void *ptr)
{
    airui_ctx_t *ctx = (airui_ctx_t *)ptr;
    if (ctx == NULL || !ctx->debug_enabled) {
        return 0;
    }

    if (ctx->display == NULL) {
        return 0;
    }

    uint32_t fps = ctx->debug_refr_count - ctx->debug_last_refr_count;
    ctx->debug_last_refr_count = ctx->debug_refr_count;
    ctx->debug_last_fps = (uint16_t)fps;

    lv_mem_monitor_t mon;
    lv_mem_monitor(&mon);
    ctx->debug_last_mem_used_pct = mon.used_pct;

    uint32_t used = (uint32_t)(mon.total_size - mon.free_size);
    uint32_t total = (uint32_t)mon.total_size;
    uint32_t free = (uint32_t)mon.free_size;
    uint32_t max_used = (uint32_t)mon.max_used;
    uint32_t total_kb = total / 1024U;
    uint32_t used_kb = used / 1024U;
    uint32_t free_kb = free / 1024U;
    uint32_t max_used_kb = max_used / 1024U;
    uint32_t mem_pct_x100 = 0;
    if (mon.total_size > 0) {
        mem_pct_x100 = (uint32_t)(((uint64_t)used * 10000U) / (uint64_t)mon.total_size);
    }
    uint32_t mem_pct_int = mem_pct_x100 / 100U;
    uint32_t mem_pct_frac = mem_pct_x100 % 100U;

    LLOGI("[airui][debug][perf] fps=%u 内存占用=%u.%02u%% 内存总量=%uKB 内存使用=%uKB 内存空闲=%uKB 内存峰值=%uKB 组件数量=%u",
          (unsigned int)ctx->debug_last_fps,
          (unsigned int)mem_pct_int,
          (unsigned int)mem_pct_frac,
          (unsigned int)total_kb,
          (unsigned int)used_kb,
          (unsigned int)free_kb,
          (unsigned int)max_used_kb,
          (unsigned int)ctx->debug_component_count);

    return 0;
}

/**
 * @brief 性能统计定时器回调，每秒通过消息总线投递 airui_debug_perf_msg_handler 到主线程
 * @param param 指向 airui_ctx_t 的指针
 */
static void airui_debug_perf_timer_cb(LUAT_RT_CB_PARAM)
{
    airui_ctx_t *ctx = (airui_ctx_t *)param;
    if (ctx == NULL) {
        return;
    }

    rtos_msg_t msg = {
        .handler = airui_debug_perf_msg_handler,
        .ptr = ctx,
        .arg1 = 0,
        .arg2 = 0
    };
    luat_msgbus_put(&msg, 0);
}

/**
 * @brief 内部函数：关闭调试统计，停止定时器并移除刷新事件钩子
 * @param ctx AirUI 上下文，可为 NULL（则只清理全局定时器）
 */
static void airui_debug_disable_internal(airui_ctx_t *ctx)
{
    if (ctx == NULL) {
        if (g_airui_debug_perf_timer != NULL) {
            luat_rtos_timer_stop(g_airui_debug_perf_timer);
            luat_rtos_timer_delete(g_airui_debug_perf_timer);
            g_airui_debug_perf_timer = NULL;
        }
        return;
    }

    ctx->debug_enabled = false;

    if (g_airui_debug_perf_timer != NULL) {
        luat_rtos_timer_stop(g_airui_debug_perf_timer);
        luat_rtos_timer_delete(g_airui_debug_perf_timer);
        g_airui_debug_perf_timer = NULL;
    }

    if (ctx->display != NULL && ctx->debug_refr_hooked) {
        lv_display_remove_event_cb_with_user_data(ctx->display, airui_debug_display_event_cb, ctx);
        ctx->debug_refr_hooked = false;
    }

    ctx->debug_last_fps = 0;
    ctx->debug_last_mem_used_pct = 0;
    ctx->debug_last_refr_count = ctx->debug_refr_count;
}

/**
 * @brief 启用或禁用 AirUI 调试统计（FPS、内存占用、组件数量）
 * @param ctx AirUI 上下文
 * @param enable 为 true 则启用，为 false 则禁用
 * @return AIRUI_OK 成功；AIRUI_ERR_NOT_INITIALIZED 上下文未初始化；
 *         AIRUI_ERR_INIT_FAILED 显示对象未创建；AIRUI_ERR_PLATFORM_ERROR 定时器创建失败
 */
int airui_debug_set_enabled(airui_ctx_t *ctx, bool enable)
{
    if (ctx == NULL) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }

    if (!enable) {
        airui_debug_disable_internal(ctx);
        return AIRUI_OK;
    }

    if (ctx->debug_enabled) {
        return AIRUI_OK;
    }

    if (ctx->display == NULL) {
        return AIRUI_ERR_INIT_FAILED;
    }

    if (!ctx->debug_refr_hooked) {
        lv_display_add_event_cb(ctx->display, airui_debug_display_event_cb, LV_EVENT_REFR_READY, ctx);
        ctx->debug_refr_hooked = true;
    }

    if (g_airui_debug_perf_timer == NULL) {
        int ret = luat_rtos_timer_create(&g_airui_debug_perf_timer);
        if (ret != 0) {
            ctx->debug_refr_hooked = false;
            lv_display_remove_event_cb_with_user_data(ctx->display, airui_debug_display_event_cb, ctx);
            return AIRUI_ERR_PLATFORM_ERROR;
        }
    }

    int ret = luat_rtos_timer_start(g_airui_debug_perf_timer, 1000, 1, airui_debug_perf_timer_cb, ctx);
    if (ret != 0) {
        luat_rtos_timer_delete(g_airui_debug_perf_timer);
        g_airui_debug_perf_timer = NULL;
        ctx->debug_refr_hooked = false;
        lv_display_remove_event_cb_with_user_data(ctx->display, airui_debug_display_event_cb, ctx);
        return AIRUI_ERR_PLATFORM_ERROR;
    }

    ctx->debug_enabled = true;
    ctx->debug_warned_refr_unavailable = false;
    ctx->debug_last_refr_count = ctx->debug_refr_count;
    ctx->debug_last_fps = 0;
    ctx->debug_last_mem_used_pct = 0;

    return AIRUI_OK;
}

/**
 * @brief 反初始化调试模块，关闭调试统计并释放相关资源
 * @param ctx AirUI 上下文
 */
void airui_debug_deinit(airui_ctx_t *ctx)
{
    airui_debug_disable_internal(ctx);
}
