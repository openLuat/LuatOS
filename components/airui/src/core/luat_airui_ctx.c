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

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

// LVGL Tick 定时器句柄（全局静态变量，用于在 deinit 中清理）
static luat_rtos_timer_t g_lv_tick_timer = NULL;
static bool g_lv_log_cb_registered = false;

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
// #else
// #warning "No platform driver selected. Please define LUAT_USE_AIRUI_SDL2 or LUAT_USE_AIRUI_LUATOS"
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
 * LVGL Tick 定时器回调（每5ms调用 lv_tick_inc(5)）
 */
static void airui_lv_tick_timer_handler(void *param)
{
    (void)param;
    
    // 直接更新 LVGL tick
    lv_tick_inc(5);  // 5ms tick
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
    
    // 分配显示缓冲（双缓冲模式）
    uint32_t buf_size = width * height * lv_color_format_get_size(color_format);
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
    
    // 文件系统驱动初始化（可选）
    ret = airui_fs_init(ctx);
    if (ret != 0) {
        LLOGE("airui_init failed: file system init failed, ret=%d", ret);
        // 文件系统初始化失败不影响整体初始化，只记录错误
    }

    // 创建 LVGL tick 定时器（每5ms触发一次，用于更新 lv_tick_inc(5)）
    ret = luat_rtos_timer_create(&g_lv_tick_timer);
    if (ret != 0) {
        LLOGE("airui_init failed: create lv tick timer failed, ret=%d", ret);
        airui_deinit(ctx);
        return AIRUI_ERR_INIT_FAILED;
    }
    
    // 启动定时器：5ms 超时，重复执行
    ret = luat_rtos_timer_start(g_lv_tick_timer, 5, 1, airui_lv_tick_timer_handler, NULL);
    if (ret != 0) {
        LLOGE("airui_init failed: start lv tick timer failed, ret=%d", ret);
        luat_rtos_timer_delete(g_lv_tick_timer);
        g_lv_tick_timer = NULL;
        airui_deinit(ctx);
        return AIRUI_ERR_INIT_FAILED;
    }
    
    LLOGD("airui_init success: %dx%d, color_format=%d", width, height, color_format);
    
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
    
    // 停止并删除 LVGL tick 定时器
    if (g_lv_tick_timer != NULL) {
        luat_rtos_timer_stop(g_lv_tick_timer);
        luat_rtos_timer_delete(g_lv_tick_timer);
        g_lv_tick_timer = NULL;
        LLOGD("lv tick timer stopped");
    }
    
    // 清理平台驱动
    if (ctx->ops != NULL && ctx->ops->display_ops != NULL && ctx->ops->display_ops->deinit != NULL) {
        ctx->ops->display_ops->deinit(ctx);
    }
    
    // 删除输入设备
    if (ctx->indev != NULL) {
        lv_indev_delete(ctx->indev);
        ctx->indev = NULL;
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

