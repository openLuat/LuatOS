/**
 * @file luat_airui_ctx.c
 * @summary AIRUI 上下文生命周期管理
 * @responsible 上下文创建、初始化、清理
 */

#include "luat_airui.h"
#include "luat_airui_component.h"
#include "luat_rtos.h"
#include "lvgl9/lvgl.h"
#include <string.h>
#include <assert.h>
#include "luat_conf_bsp.h"
#include "luat_airui_conf.h"

#include "luat_msgbus.h"
#include "luat_rtos.h"

#ifdef LUAT_USE_WDT
#include "luat_wdt.h"
#endif

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

static bool g_lv_log_cb_registered = false;
static int airui_refresh_msg_handler(lua_State *L, void *ptr);
static void airui_refresh_timer_cb(LUAT_RT_CB_PARAM);
static int airui_start_runtime_timers(airui_ctx_t *ctx);
static void airui_stop_runtime_timers(airui_ctx_t *ctx);
static void airui_pause_lvgl_timers(airui_ctx_t *ctx);
static void airui_resume_lvgl_timers(airui_ctx_t *ctx);

static void airui_feed_wdt_if_enabled(void)
{
#ifdef LUAT_USE_WDT
    luat_wdt_feed();
#endif
}

/* 将 LVGL 日志映射到 LuatOS 日志 */
static void airui_lv_log_cb(lv_log_level_t level, const char * buf)
{
    switch (level) {
    case LV_LOG_LEVEL_TRACE:
        LLOGD("%s", buf);
        break;
    case LV_LOG_LEVEL_INFO:
        LLOGI("%s", buf);
        break;
    case LV_LOG_LEVEL_WARN:
        LLOGW("%s", buf);
        break;
    case LV_LOG_LEVEL_ERROR:
        LLOGE("%s", buf);
        break;
    case LV_LOG_LEVEL_USER:
    default:
        LLOGI("%s", buf);
        break;
    }
}

// 平台驱动声明（编译时选择）
#if defined(LUAT_USE_AIRUI_SDL2)
extern const airui_platform_ops_t *airui_platform_ops_sdl2_get(void);
#elif defined(LUAT_USE_AIRUI_LUATOS) 
extern const airui_platform_ops_t *airui_platform_ops_luatos_get(void);
// 注册 LuatOS 平台 JPG 解码器
extern int airui_platform_luatos_register_jpg_decoder(void);
#endif

/**
 * 显示驱动 flush 回调
 */
static void display_flush_cb(lv_display_t *disp, const lv_area_t *area, uint8_t *px_map)
{
    airui_ctx_t *ctx = (airui_ctx_t *)lv_display_get_user_data(disp);
    if (ctx == NULL || ctx->ops == NULL || ctx->ops->display_ops == NULL) {
        return;
    }
    
    if (ctx->ops->display_ops->flush) {
        ctx->ops->display_ops->flush(ctx, area, px_map);
    }
    // flush_ready 由平台驱动在实际完成时机调用
}

/**
 * 输入设备 read 回调
 */
static void input_read_cb(lv_indev_t *indev, lv_indev_data_t *data)
{
    airui_ctx_t *ctx = (airui_ctx_t *)lv_indev_get_user_data(indev);
    if (ctx == NULL || ctx->ops == NULL || ctx->ops->input_ops == NULL) {
        return;
    }
    
    if (ctx->ops->input_ops->read_pointer) {
        ctx->ops->input_ops->read_pointer(ctx, data);
    }
}

/**
 * 按键输入设备 read 回调
 */
static void input_read_keypad_cb(lv_indev_t *indev, lv_indev_data_t *data)
{
    airui_ctx_t *ctx = (airui_ctx_t *)lv_indev_get_user_data(indev);
    if (ctx == NULL || ctx->ops == NULL || ctx->ops->input_ops == NULL) {
        return;
    }

    if (ctx->ops->input_ops->read_keypad) {
        ctx->ops->input_ops->read_keypad(ctx, data);
    }
}

/**
 * LVGL Tick 定时器回调（每5ms调用 lv_tick_inc(5)）
 */
static void airui_lv_tick_timer_handler(void *param)
{
    (void)param;
    
    // 直接更新 LVGL tick
    lv_tick_inc(5);  // 5ms tick
}

// 信息接受后激活 LVGL 定时器处理函数
static int airui_refresh_msg_handler(lua_State *L, void *ptr) {
    airui_ctx_t *ctx = (airui_ctx_t *)ptr;
    rtos_msg_t *msg = NULL;
    uint32_t handled_seq = 0;
    if (ctx == NULL) {
        return 0;
    }

    msg = (rtos_msg_t *)lua_topointer(L, -1);
    if (msg != NULL && msg->arg1 > 0) {
        handled_seq = (uint32_t)msg->arg1;
    } else {
        handled_seq = ctx->refresh_posted_seq;
    }

    if (ctx->sleeping) {
        if (handled_seq > ctx->refresh_handled_seq) {
            ctx->refresh_handled_seq = handled_seq;
        }
        return 0;
    }

    airui_feed_wdt_if_enabled();
    lv_timer_handler();
    airui_feed_wdt_if_enabled();
    if (handled_seq > ctx->refresh_handled_seq) {
        ctx->refresh_handled_seq = handled_seq;
    }
    return 0;
}

// 自动刷新定时器回调发送信息激活 LVGL 定时器处理函数
static void airui_refresh_timer_cb(LUAT_RT_CB_PARAM) {
    airui_ctx_t *ctx = (airui_ctx_t *)param;
    uint32_t next_seq = 0;
    uint32_t now = 0;
    bool has_unhandled = false;
    if (ctx == NULL || ctx->sleeping) {
        return;
    }

    if (ctx->ops != NULL && ctx->ops->time_ops != NULL && ctx->ops->time_ops->get_tick != NULL) {
        now = ctx->ops->time_ops->get_tick(ctx);
    }

    has_unhandled = (ctx->refresh_posted_seq != ctx->refresh_handled_seq);
    if (has_unhandled) {
        uint32_t elapsed = 0;
        if (ctx->refresh_last_post_tick != 0U && now != 0U) {
            elapsed = now - ctx->refresh_last_post_tick;
        }
        if (elapsed < AIRUI_REFRESH_RETRY_TIMEOUT_MS) {
            return;
        }
    }

    next_seq = ctx->refresh_posted_seq + 1U;

    rtos_msg_t msg = {
        .handler = airui_refresh_msg_handler,
        .ptr = ctx,
        .arg1 = (int)next_seq,
        .arg2 = 0
    };

    if (luat_msgbus_put(&msg, 0) == 0) {
        ctx->refresh_posted_seq = next_seq;
        ctx->refresh_last_post_tick = now;
        if (has_unhandled) {
            LLOGW("refresh retry posted seq=%lu handled=%lu posted=%lu",
                  (unsigned long)next_seq,
                  (unsigned long)ctx->refresh_handled_seq,
                  (unsigned long)ctx->refresh_posted_seq);
        }
    }
}

// 启动运行时定时器
static int airui_start_runtime_timers(airui_ctx_t *ctx)
{
    int ret = 0;

    if (ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (ctx->tick_rtos_timer == NULL) {
        ret = luat_rtos_timer_create((luat_rtos_timer_t *)&ctx->tick_rtos_timer);
        if (ret != 0) {
            LLOGE("airui_init failed: create lv tick timer failed, ret=%d", ret);
            return AIRUI_ERR_INIT_FAILED;
        }
    }

    ret = luat_rtos_timer_start((luat_rtos_timer_t)ctx->tick_rtos_timer, 5, 1, airui_lv_tick_timer_handler, NULL);
    if (ret != 0) {
        LLOGE("airui_init failed: start lv tick timer failed, ret=%d", ret);
        luat_rtos_timer_delete((luat_rtos_timer_t)ctx->tick_rtos_timer);
        ctx->tick_rtos_timer = NULL;
        return AIRUI_ERR_INIT_FAILED;
    }

    if (ctx->refresh_rtos_timer == NULL) {
        ret = luat_rtos_timer_create((luat_rtos_timer_t *)&ctx->refresh_rtos_timer);
        if (ret != 0) {
            LLOGE("airui_init failed: create lv refresh timer failed, ret=%d", ret);
            luat_rtos_timer_stop((luat_rtos_timer_t)ctx->tick_rtos_timer);
            luat_rtos_timer_delete((luat_rtos_timer_t)ctx->tick_rtos_timer);
            ctx->tick_rtos_timer = NULL;
            return AIRUI_ERR_INIT_FAILED;
        }
    }

    ret = luat_rtos_timer_start((luat_rtos_timer_t)ctx->refresh_rtos_timer, AIRUI_REFRESH_PERIOD_MS, 1, airui_refresh_timer_cb, ctx);
    if (ret != 0) {
        LLOGE("airui_init failed: start lv refresh timer failed, ret=%d", ret);
        luat_rtos_timer_delete((luat_rtos_timer_t)ctx->refresh_rtos_timer);
        ctx->refresh_rtos_timer = NULL;
        luat_rtos_timer_stop((luat_rtos_timer_t)ctx->tick_rtos_timer);
        luat_rtos_timer_delete((luat_rtos_timer_t)ctx->tick_rtos_timer);
        ctx->tick_rtos_timer = NULL;
        return AIRUI_ERR_INIT_FAILED;
    }

    return AIRUI_OK;
}

// 停止运行时定时器
static void airui_stop_runtime_timers(airui_ctx_t *ctx)
{
    if (ctx == NULL) {
        return;
    }

    if (ctx->tick_rtos_timer != NULL) {
        luat_rtos_timer_stop((luat_rtos_timer_t)ctx->tick_rtos_timer);
        luat_rtos_timer_delete((luat_rtos_timer_t)ctx->tick_rtos_timer);
        ctx->tick_rtos_timer = NULL;
        LLOGD("lv tick timer stopped");
    }

    if (ctx->refresh_rtos_timer != NULL) {
        luat_rtos_timer_stop((luat_rtos_timer_t)ctx->refresh_rtos_timer);
        luat_rtos_timer_delete((luat_rtos_timer_t)ctx->refresh_rtos_timer);
        ctx->refresh_rtos_timer = NULL;
        LLOGD("lv refresh timer stopped");
    }

    ctx->refresh_posted_seq = 0;
    ctx->refresh_handled_seq = 0;
    ctx->refresh_last_post_tick = 0;
}

// 暂停 LVGL 定时器
static void airui_pause_lvgl_timers(airui_ctx_t *ctx)
{
    lv_timer_t *timer = NULL;

    if (ctx == NULL) {
        return;
    }

    if (ctx->display != NULL) {
        timer = lv_display_get_refr_timer(ctx->display);
        if (timer != NULL) {
            lv_timer_pause(timer);
        }
    }

    if (ctx->indev != NULL) {
        timer = lv_indev_get_read_timer(ctx->indev);
        if (timer != NULL) {
            lv_timer_pause(timer);
        }
    }

    if (ctx->indev_keypad != NULL) {
        timer = lv_indev_get_read_timer(ctx->indev_keypad);
        if (timer != NULL) {
            lv_timer_pause(timer);
        }
    }
}

// 恢复 LVGL 定时器
static void airui_resume_lvgl_timers(airui_ctx_t *ctx)
{
    lv_timer_t *timer = NULL;

    if (ctx == NULL) {
        return;
    }

    if (ctx->display != NULL) {
        timer = lv_display_get_refr_timer(ctx->display);
        if (timer != NULL) {
            lv_timer_resume(timer);
        }
    }

    if (ctx->indev != NULL) {
        timer = lv_indev_get_read_timer(ctx->indev);
        if (timer != NULL) {
            lv_timer_resume(timer);
        }
    }

    if (ctx->indev_keypad != NULL) {
        timer = lv_indev_get_read_timer(ctx->indev_keypad);
        if (timer != NULL) {
            lv_timer_resume(timer);
        }
    }
}

/**
 * 创建 AIRUI 上下文对象
 * @param ctx 上下文指针（输出）
 * @param ops 平台操作接口
 * @return 0 成功，<0 失败
 */
int airui_ctx_create(airui_ctx_t *ctx, const airui_platform_ops_t *ops)
{
    if (ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    // 清零上下文
    memset(ctx, 0, sizeof(airui_ctx_t));
    ctx->touch_last_state = AIRUI_TOUCH_STATE_NONE;
    ctx->sleep_power_down_lcd = true;
    
    // 如果没有传入 ops，则根据编译时宏定义自动选择
    if (ops == NULL) {
#if defined(LUAT_USE_AIRUI_SDL2)
        ops = airui_platform_ops_sdl2_get();
#elif defined(LUAT_USE_AIRUI_LUATOS)
        ops = airui_platform_ops_luatos_get();
#else
        return AIRUI_ERR_INVALID_PARAM;
#endif
    }
    
    if (ops == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    // 存储平台 ops
    ctx->ops = ops;
    
    // 创建缓冲管理器
    ctx->buffer = airui_buffer_create();
    if (ctx->buffer == NULL) {
        return AIRUI_ERR_NO_MEM;
    }
    
    return AIRUI_OK;
}

/**
 * 初始化 AIRUI
 * @param ctx 上下文指针
 * @param width 屏幕宽度
 * @param height 屏幕高度
 * @param color_format 颜色格式
 * @return 0 成功，<0 失败
 * 
 * 主要任务：
 * 1. 参数验证和基础设置（宽度、高度、LVGL初始化）
 * 2. 创建显示设备和初始化平台显示驱动
 * 3. 分配显示缓冲（双缓冲模式）
 * 4. 创建输入设备和tick定时器
 */
int airui_init(airui_ctx_t *ctx, uint16_t width, uint16_t height, lv_color_format_t color_format)
{
    if (ctx == NULL || ctx->ops == NULL || width == 0 || height == 0) {
        if (ctx == NULL || ctx->ops == NULL) {
            LLOGE("airui_init failed: invalid context or ops");
        } else {
            LLOGE("airui_init failed: invalid size %dx%d", width, height);
        }
        return AIRUI_ERR_INIT_FAILED;
    }
    
    ctx->width = width;
    ctx->height = height;
    ctx->native_width = width;
    ctx->native_height = height;
    
    // 初始化 LVGL
    if (!lv_is_initialized()) {
        lv_init();
    }

    /* 如果 LV_USE_LOG 宏定义为 1，则注册 LVGL 日志回调到 LuatOS 日志 */
    #if LV_USE_LOG == 1
        LLOGD("LV_USE_LOG is enabled");
        // 注册 LVGL 日志回调到 LuatOS 日志，仅注册一次
        if (!g_lv_log_cb_registered) {
            lv_log_register_print_cb(airui_lv_log_cb);
            g_lv_log_cb_registered = true;
        }
    #endif

    // 创建显示设备
    ctx->display = lv_display_create(width, height);
    if (ctx->display == NULL) {
        LLOGE("airui_init failed: lv_display_create failed");
        return AIRUI_ERR_INIT_FAILED;
    }
    
    lv_display_set_user_data(ctx->display, ctx);
    
    // 初始化平台显示驱动
    if (ctx->ops->display_ops == NULL || ctx->ops->display_ops->init == NULL) {
        LLOGE("airui_init failed: display_ops or init callback is NULL");
        lv_display_delete(ctx->display);
        ctx->display = NULL;
        return AIRUI_ERR_INIT_FAILED;
    }
    
    int ret = ctx->ops->display_ops->init(ctx, width, height, color_format);
    if (ret != 0) {
        LLOGE("airui_init failed: platform display init failed, ret=%d", ret);
        lv_display_delete(ctx->display);
        ctx->display = NULL;
        return AIRUI_ERR_INIT_FAILED;
    }
    
    // 设置 flush 回调
    lv_display_set_flush_cb(ctx->display, display_flush_cb);
    
    // 设置 display 的颜色格式（要和平台 driver 传入的一致）
    lv_display_set_color_format(ctx->display, color_format);

    // 将 LVGL 显示刷新周期调整为 AIRUI_REFRESH_PERIOD_MS，保证刷新节拍一致
    lv_timer_t *refr_timer = lv_display_get_refr_timer(ctx->display);
    if (refr_timer != NULL) {
        lv_timer_set_period(refr_timer, AIRUI_REFRESH_PERIOD_MS);
    }
    
    // 分配显示缓冲（双缓冲模式）
    uint32_t buf_size = width * height * lv_color_format_get_size(color_format) / AIRUI_DISPLAY_BUFFER_SIZE_DIVISOR;
    void *buf1 = airui_buffer_alloc(ctx, buf_size, AIRUI_BUFFER_OWNER_SYSTEM);
    void *buf2 = airui_buffer_alloc(ctx, buf_size, AIRUI_BUFFER_OWNER_SYSTEM);
    
    if (buf1 == NULL || buf2 == NULL) {
        LLOGE("airui_init failed: buffer allocation failed, size=%u", buf_size);
        airui_deinit(ctx);
        return AIRUI_ERR_INIT_FAILED;
    }
    
    // 设置缓冲
    airui_display_set_buffers(ctx, buf1, buf2, buf_size, AIRUI_BUFFER_MODE_DOUBLE);
    
    // 创建输入设备
    ctx->indev = lv_indev_create();
    if (ctx->indev == NULL) {
        LLOGE("airui_init failed: lv_indev_create failed");
        airui_deinit(ctx);
        return AIRUI_ERR_INIT_FAILED;
    }
    lv_indev_set_type(ctx->indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_user_data(ctx->indev, ctx);
    lv_indev_set_read_cb(ctx->indev, input_read_cb);

    // 创建按键输入设备（用于物理按键/键盘/方向键）
    ctx->indev_keypad = lv_indev_create();
    if (ctx->indev_keypad == NULL) {
        LLOGE("airui_init failed: lv_indev_create keypad failed");
        airui_deinit(ctx);
        return AIRUI_ERR_INIT_FAILED;
    }
    lv_indev_set_type(ctx->indev_keypad, LV_INDEV_TYPE_KEYPAD);
    lv_indev_set_user_data(ctx->indev_keypad, ctx);
    lv_indev_set_read_cb(ctx->indev_keypad, input_read_keypad_cb);

    // 创建默认焦点组，用于支持实体按键导航
    ctx->indev_group = lv_group_create();
    if (ctx->indev_group == NULL) {
        LLOGE("airui_init failed: lv_group_create failed");
        airui_deinit(ctx);
        return AIRUI_ERR_INIT_FAILED;
    }
    lv_group_set_default(ctx->indev_group);
    lv_indev_set_group(ctx->indev_keypad, ctx->indev_group);
    
    // 文件系统驱动初始化（可选）
    ret = airui_fs_init(ctx);
    if (ret != 0) {
        LLOGE("airui_init failed: file system init failed, ret=%d", ret);
        // 文件系统初始化失败不影响整体初始化，只记录错误
    }

    #if defined(LUAT_USE_AIRUI_LUATOS)
    ret = airui_platform_luatos_register_jpg_decoder();
    if (ret != AIRUI_OK) {
        LLOGW("airui_init: register luatos jpg decoder failed, ret=%d", ret);
    }
    #endif

    // 启动运行时定时器
    ret = airui_start_runtime_timers(ctx);
    if (ret != AIRUI_OK) {
        airui_deinit(ctx);
        return ret;
    }

    LLOGD("airui_init success: %dx%d, color_format=%d", width, height, color_format);
    
    return AIRUI_OK;
}

// 休眠 AIRUI
int airui_sleep(airui_ctx_t *ctx)
{
    int ret = AIRUI_OK;

    if (ctx == NULL || ctx->display == NULL) {
        LLOGE("airui_sleep invalid ctx=%p display=%p", ctx, ctx ? ctx->display : NULL);
        return AIRUI_ERR_NOT_INITIALIZED;
    }

    if (ctx->sleeping) {
        LLOGW("airui_sleep ignored already sleeping ctx=%p", ctx);
        return AIRUI_OK;
    }

    airui_pause_lvgl_timers(ctx);

    if (ctx->tick_rtos_timer != NULL) {
        luat_rtos_timer_stop((luat_rtos_timer_t)ctx->tick_rtos_timer);
    }
    if (ctx->refresh_rtos_timer != NULL) {
        luat_rtos_timer_stop((luat_rtos_timer_t)ctx->refresh_rtos_timer);
    }

    ctx->refresh_posted_seq = 0;
    ctx->refresh_handled_seq = 0;
    ctx->refresh_last_post_tick = 0;

    ctx->sleeping = true;

    if (ctx->ops != NULL && ctx->ops->display_ops != NULL && ctx->ops->display_ops->suspend != NULL) {
        ret = ctx->ops->display_ops->suspend(ctx);
        if (ret != 0) {
            ctx->sleeping = false;
            LLOGE("airui_sleep suspend failed restore runtime ctx=%p", ctx);
            airui_resume_lvgl_timers(ctx);
            if (ctx->tick_rtos_timer != NULL) {
                luat_rtos_timer_start((luat_rtos_timer_t)ctx->tick_rtos_timer, 5, 1, airui_lv_tick_timer_handler, NULL);
            }
            if (ctx->refresh_rtos_timer != NULL) {
                luat_rtos_timer_start((luat_rtos_timer_t)ctx->refresh_rtos_timer, AIRUI_REFRESH_PERIOD_MS, 1, airui_refresh_timer_cb, ctx);
            }
            return ret;
        }
    }

    return AIRUI_OK;
}

// 唤醒 AIRUI
int airui_wakeup(airui_ctx_t *ctx, bool auto_refresh)
{
    int ret = AIRUI_OK;

    if (ctx == NULL || ctx->display == NULL) {
        LLOGE("airui_wakeup invalid ctx=%p display=%p", ctx, ctx ? ctx->display : NULL);
        return AIRUI_ERR_NOT_INITIALIZED;
    }

    if (!ctx->sleeping) {
        LLOGW("airui_wakeup ignored not sleeping ctx=%p", ctx);
        return AIRUI_OK;
    }

    if (ctx->ops != NULL && ctx->ops->display_ops != NULL && ctx->ops->display_ops->resume != NULL) {
        ret = ctx->ops->display_ops->resume(ctx);
        if (ret != 0) {
            return ret;
        }
    }

    if (ctx->tick_rtos_timer != NULL) {
        ret = luat_rtos_timer_start((luat_rtos_timer_t)ctx->tick_rtos_timer, 5, 1, airui_lv_tick_timer_handler, NULL);
        if (ret != 0) {
            LLOGE("airui_wakeup start tick_rtos_timer failed ret=%d ctx=%p", ret, ctx);
            return AIRUI_ERR_PLATFORM_ERROR;
        }
    }
    if (ctx->refresh_rtos_timer != NULL) {
        ctx->refresh_posted_seq = 0;
        ctx->refresh_handled_seq = 0;
        ctx->refresh_last_post_tick = 0;
        ret = luat_rtos_timer_start((luat_rtos_timer_t)ctx->refresh_rtos_timer, AIRUI_REFRESH_PERIOD_MS, 1, airui_refresh_timer_cb, ctx);
        if (ret != 0) {
            LLOGE("airui_wakeup start refresh_rtos_timer failed ret=%d ctx=%p", ret, ctx);
            return AIRUI_ERR_PLATFORM_ERROR;
        }
    }

    airui_resume_lvgl_timers(ctx);
    ctx->sleeping = false;
    if (auto_refresh) {
        lv_obj_t *act_scr = lv_display_get_screen_active(ctx->display);
        if (act_scr != NULL) {
            lv_obj_invalidate(act_scr);
        }
        lv_refr_now(ctx->display);
    }
    return AIRUI_OK;
}

// 全屏刷新 
int airui_full_refresh(airui_ctx_t *ctx)
{
    lv_obj_t *act_scr = NULL;

    if (ctx == NULL || ctx->display == NULL) {
        LLOGE("airui_full_refresh invalid ctx=%p display=%p", ctx, ctx ? ctx->display : NULL);
        return AIRUI_ERR_NOT_INITIALIZED;
    }

    if (ctx->sleeping) {
        LLOGW("airui_full_refresh ignored while sleeping ctx=%p", ctx);
        return AIRUI_ERR_PLATFORM_ERROR;
    }

    act_scr = lv_display_get_screen_active(ctx->display);
    if (act_scr == NULL) {
        LLOGW("airui_full_refresh active screen missing ctx=%p display=%p", ctx, ctx->display);
        return AIRUI_ERR_PLATFORM_ERROR;
    }

    lv_obj_invalidate(act_scr);
    lv_refr_now(ctx->display);
    return AIRUI_OK;
}

/**
 * 反初始化 AIRUI
 * @param ctx 上下文指针
 */
void airui_deinit(airui_ctx_t *ctx)
{
    if (ctx == NULL) {
        return;
    }

    // 释放调试信息数据
    airui_debug_deinit(ctx);

    // 释放全局触摸订阅
    airui_touch_unsubscribe(ctx, ctx->L);
    
    // 停止运行时定时器
    airui_stop_runtime_timers(ctx);
    
    // 清理平台驱动
    if (ctx->ops != NULL && ctx->ops->display_ops != NULL && ctx->ops->display_ops->deinit != NULL) {
        ctx->ops->display_ops->deinit(ctx);
    }
    
    // 删除输入设备
    if (ctx->indev != NULL) {
        lv_indev_delete(ctx->indev);
        ctx->indev = NULL;
    }

    // 删除按键输入设备
    if (ctx->indev_keypad != NULL) {
        lv_indev_delete(ctx->indev_keypad);
        ctx->indev_keypad = NULL;
    }

    // 删除默认焦点组
    if (ctx->indev_group != NULL) {
        if (lv_group_get_default() == ctx->indev_group) {
            lv_group_set_default(NULL);
        }
        lv_group_delete(ctx->indev_group);
        ctx->indev_group = NULL;
    }
    
    // 删除显示设备
    if (ctx->display != NULL) {
        lv_display_delete(ctx->display);
        ctx->display = NULL;
    }
    
    // 释放所有缓冲
    airui_buffer_free_all(ctx);
    
    // 清零上下文
    memset(ctx, 0, sizeof(airui_ctx_t));
}
