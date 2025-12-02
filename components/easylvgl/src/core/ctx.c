/**
 * @file ctx.c
 * @summary EasyLVGL 上下文生命周期管理
 * @responsible 上下文创建、初始化、清理
 */

#include "easylvgl.h"
#include "easylvgl_component.h"
#include "easylvgl_task.h"
#include <string.h>
#include <assert.h>

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
 */
int easylvgl_init(easylvgl_ctx_t *ctx, uint16_t width, uint16_t height, lv_color_format_t color_format)
{
    if (ctx == NULL || ctx->ops == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    if (width == 0 || height == 0) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    ctx->width = width;
    ctx->height = height;
    
    // 初始化 LVGL
    lv_init();
    
    // 创建显示设备
    ctx->display = lv_display_create(width, height);
    if (ctx->display == NULL) {
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    lv_display_set_user_data(ctx->display, ctx);
    
    // 初始化平台显示驱动
    if (ctx->ops->display_ops == NULL || ctx->ops->display_ops->init == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    int ret = ctx->ops->display_ops->init(ctx, width, height, color_format);
    if (ret != 0) {
        lv_display_delete(ctx->display);
        ctx->display = NULL;
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    // 设置 flush 回调
    lv_display_set_flush_cb(ctx->display, display_flush_cb);
    
    // 分配显示缓冲（双缓冲模式）
    uint32_t buf_size = width * height * lv_color_format_get_size(color_format);
    void *buf1 = easylvgl_buffer_alloc(ctx, buf_size, EASYLVGL_BUFFER_OWNER_SYSTEM);
    void *buf2 = easylvgl_buffer_alloc(ctx, buf_size, EASYLVGL_BUFFER_OWNER_SYSTEM);
    
    if (buf1 == NULL || buf2 == NULL) {
        easylvgl_deinit(ctx);
        return EASYLVGL_ERR_NO_MEM;
    }
    
    // 设置缓冲
    easylvgl_display_set_buffers(ctx, buf1, buf2, buf_size, EASYLVGL_BUFFER_MODE_DOUBLE);
    
    // 创建输入设备
    ctx->indev = lv_indev_create();
    if (ctx->indev == NULL) {
        easylvgl_deinit(ctx);
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    lv_indev_set_type(ctx->indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_user_data(ctx->indev, ctx);
    lv_indev_set_read_cb(ctx->indev, input_read_cb);
    
    // 文件系统驱动初始化（可选）
    // TODO: 阶段一暂不实现文件系统驱动
    
    // 启动 LVGL 专职任务
    ret = easylvgl_task_start(ctx);
    if (ret != 0) {
        easylvgl_deinit(ctx);
        return ret;
    }
    
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

