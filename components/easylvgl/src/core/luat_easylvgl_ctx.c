/**
 * @file luat_easylvgl_ctx.c
 * @summary EasyLVGL 上下文生命周期管理
 * @responsible 上下文创建、初始化、清理
 */

#include "luat_easylvgl.h"
#include "luat_easylvgl_component.h"
#include "luat_easylvgl_task.h"
#include "luat_rtos.h"
#include <string.h>
#include <assert.h>

#define LUAT_LOG_TAG "easylvgl.ctx"
#include "luat_log.h"

// LVGL Tick 定时器句柄（全局静态变量，用于在 deinit 中清理）
static luat_rtos_timer_t g_lv_tick_timer = NULL;

// 平台驱动声明（编译时选择）
#if defined(LUAT_USE_EASYLVGL_SDL2)
extern const easylvgl_platform_ops_t *easylvgl_platform_ops_sdl2_get(void);
#elif defined(LUAT_USE_EASYLVGL_BK7258)
extern const easylvgl_platform_ops_t *easylvgl_platform_ops_bk7258_get(void);
#else
#error "No platform driver selected. Please define LUAT_USE_EASYLVGL_SDL2 or LUAT_USE_EASYLVGL_BK7258"
#endif

/**
 * 显示驱动 flush 回调
 */
static void display_flush_cb(lv_display_t *disp, const lv_area_t *area, uint8_t *px_map)
{
    easylvgl_ctx_t *ctx = (easylvgl_ctx_t *)lv_display_get_user_data(disp);
    if (ctx == NULL || ctx->ops == NULL || ctx->ops->display_ops == NULL) {
        return;
    }
    
    if (ctx->ops->display_ops->flush) {
        ctx->ops->display_ops->flush(ctx, area, px_map);
    }
    
    lv_display_flush_ready(disp);
}

/**
 * 输入设备 read 回调
 */
static void input_read_cb(lv_indev_t *indev, lv_indev_data_t *data)
{
    easylvgl_ctx_t *ctx = (easylvgl_ctx_t *)lv_indev_get_user_data(indev);
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
static void easylvgl_lv_tick_timer_handler(void *param)
{
    (void)param;
    
    // 直接更新 LVGL tick
    lv_tick_inc(5);  // 5ms tick
}

/**
 * 创建 EasyLVGL 上下文对象
 * @param ctx 上下文指针（输出）
 * @param ops 平台操作接口
 * @return 0 成功，<0 失败
 */
int easylvgl_ctx_create(easylvgl_ctx_t *ctx, const easylvgl_platform_ops_t *ops)
{
    if (ctx == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    // 清零上下文
    memset(ctx, 0, sizeof(easylvgl_ctx_t));
    
    // 如果没有传入 ops，则根据编译时宏定义自动选择
    if (ops == NULL) {
#if defined(LUAT_USE_EASYLVGL_SDL2)
        ops = easylvgl_platform_ops_sdl2_get();
#elif defined(LUAT_USE_EASYLVGL_BK7258)
        ops = easylvgl_platform_ops_bk7258_get();
#else
        return EASYLVGL_ERR_INVALID_PARAM;
#endif
    }
    
    if (ops == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    // 存储平台 ops
    ctx->ops = ops;
    
    // 创建缓冲管理器
    ctx->buffer = easylvgl_buffer_create();
    if (ctx->buffer == NULL) {
        return EASYLVGL_ERR_NO_MEM;
    }
    
    return EASYLVGL_OK;
}

/**
 * 初始化 EasyLVGL
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
int easylvgl_init(easylvgl_ctx_t *ctx, uint16_t width, uint16_t height, lv_color_format_t color_format, uint32_t buff_size, uint8_t buff_mode)
{
    if (ctx == NULL || ctx->ops == NULL || width == 0 || height == 0) {
        if (ctx == NULL || ctx->ops == NULL) {
            LLOGE("easylvgl_init failed: invalid context or ops");
        } else {
            LLOGE("easylvgl_init failed: invalid size %dx%d", width, height);
        }
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    ctx->width = width;
    ctx->height = height;
    
    // 初始化 LVGL
    if (!lv_is_initialized()) {
        lv_init();
    }
    
    // 创建显示设备
    ctx->display = lv_display_create(width, height);
    if (ctx->display == NULL) {
        LLOGE("easylvgl_init failed: lv_display_create failed");
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    lv_display_set_user_data(ctx->display, ctx);
    
    // 初始化平台显示驱动
    if (ctx->ops->display_ops == NULL || ctx->ops->display_ops->init == NULL) {
        LLOGE("easylvgl_init failed: display_ops or init callback is NULL");
        lv_display_delete(ctx->display);
        ctx->display = NULL;
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    int ret = ctx->ops->display_ops->init(ctx, width, height, color_format);
    if (ret != 0) {
        LLOGE("easylvgl_init failed: platform display init failed, ret=%d", ret);
        lv_display_delete(ctx->display);
        ctx->display = NULL;
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    // 设置 flush 回调
    lv_display_set_flush_cb(ctx->display, display_flush_cb);
    
    // 设置 display 的颜色格式（要和平台 driver 传入的一致）
    lv_display_set_color_format(ctx->display, color_format);
    
    // 分配显示缓冲（双缓冲模式）
    uint32_t buf_size = width * height * lv_color_format_get_size(color_format);
    void *buf1 = easylvgl_buffer_alloc(ctx, buf_size, EASYLVGL_BUFFER_OWNER_SYSTEM);
    void *buf2 = easylvgl_buffer_alloc(ctx, buf_size, EASYLVGL_BUFFER_OWNER_SYSTEM);
    
    if (buf1 == NULL || buf2 == NULL) {
        LLOGE("easylvgl_init failed: buffer allocation failed, size=%u", buf_size);
        easylvgl_deinit(ctx);
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    // 设置缓冲
    easylvgl_display_set_buffers(ctx, buf1, buf2, buf_size, EASYLVGL_BUFFER_MODE_DOUBLE);
    
    // 创建输入设备
    ctx->indev = lv_indev_create();
    if (ctx->indev == NULL) {
        LLOGE("easylvgl_init failed: lv_indev_create failed");
        easylvgl_deinit(ctx);
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    lv_indev_set_type(ctx->indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_user_data(ctx->indev, ctx);
    lv_indev_set_read_cb(ctx->indev, input_read_cb);
    
    // 文件系统驱动初始化（可选）
    ret = easylvgl_fs_init(ctx);
    if (ret != 0) {
        LLOGE("easylvgl_init failed: file system init failed, ret=%d", ret);
        // 文件系统初始化失败不影响整体初始化，只记录错误
    }

    // 创建 LVGL tick 定时器（每5ms触发一次，用于更新 lv_tick_inc(5)）
    ret = luat_rtos_timer_create(&g_lv_tick_timer);
    if (ret != 0) {
        LLOGE("easylvgl_init failed: create lv tick timer failed, ret=%d", ret);
        easylvgl_deinit(ctx);
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    // 启动定时器：5ms 超时，重复执行
    ret = luat_rtos_timer_start(g_lv_tick_timer, 5, 1, easylvgl_lv_tick_timer_handler, NULL);
    if (ret != 0) {
        LLOGE("easylvgl_init failed: start lv tick timer failed, ret=%d", ret);
        luat_rtos_timer_delete(g_lv_tick_timer);
        g_lv_tick_timer = NULL;
        easylvgl_deinit(ctx);
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    LLOGD("easylvgl_init success: %dx%d, color_format=%d", width, height, color_format);
    
    // 启动 LVGL 专职任务
    // ret = easylvgl_task_start(ctx);
    // if (ret != 0) {
    //     easylvgl_deinit(ctx);
    //     return ret;
    // }
    
    return EASYLVGL_OK;
}

/**
 * 反初始化 EasyLVGL
 * @param ctx 上下文指针
 */
void easylvgl_deinit(easylvgl_ctx_t *ctx)
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
    
    // 停止 LVGL 专职任务
    easylvgl_task_stop();
    
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
    easylvgl_buffer_free_all(ctx);
    
    // 清零上下文
    memset(ctx, 0, sizeof(easylvgl_ctx_t));
}

