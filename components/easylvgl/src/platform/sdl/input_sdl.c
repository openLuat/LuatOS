/**
 * @file input_sdl.c
 * @summary SDL2 输入驱动实现
 * @responsible SDL2 鼠标/触摸输入处理
 */

#if defined(LUAT_USE_EASYLVGL_SDL2)

#include "easylvgl.h"
#include <SDL2/SDL.h>
#include <stdlib.h>
#include <string.h>

/** SDL 输入驱动私有数据 */
typedef struct {
    int16_t last_x;
    int16_t last_y;
    bool left_button_down;
} sdl_input_data_t;

/**
 * SDL2 输入驱动读取指针数据
 * @param ctx 上下文指针
 * @param data 输入数据（输出）
 * @return true 有数据，false 无数据
 */
static bool sdl_input_read_pointer(easylvgl_ctx_t *ctx, lv_indev_data_t *data)
{
    if (ctx == NULL || ctx->platform_data == NULL || data == NULL) {
        return false;
    }
    
    sdl_input_data_t *input_data = (sdl_input_data_t *)ctx->platform_data;
    
    // 处理 SDL 事件
    SDL_Event event;
    bool has_event = false;
    
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_MOUSEMOTION) {
            input_data->last_x = event.motion.x;
            input_data->last_y = event.motion.y;
            has_event = true;
        } else if (event.type == SDL_MOUSEBUTTONDOWN) {
            if (event.button.button == SDL_BUTTON_LEFT) {
                input_data->left_button_down = true;
                input_data->last_x = event.button.x;
                input_data->last_y = event.button.y;
                has_event = true;
            }
        } else if (event.type == SDL_MOUSEBUTTONUP) {
            if (event.button.button == SDL_BUTTON_LEFT) {
                input_data->left_button_down = false;
                input_data->last_x = event.button.x;
                input_data->last_y = event.button.y;
                has_event = true;
            }
        } else if (event.type == SDL_QUIT) {
            // 窗口关闭事件
            // TODO: 可以通过回调通知上层
        }
    }
    
    // 填充输入数据
    data->point.x = input_data->last_x;
    data->point.y = input_data->last_y;
    data->state = input_data->left_button_down ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    
    return has_event;
}

/**
 * SDL2 输入驱动读取键盘数据
 * @param ctx 上下文指针
 * @param data 输入数据（输出）
 * @return true 有数据，false 无数据
 */
static bool sdl_input_read_keypad(easylvgl_ctx_t *ctx, lv_indev_data_t *data)
{
    // 阶段一暂不实现键盘输入
    (void)ctx;
    (void)data;
    return false;
}

/**
 * SDL2 输入驱动校准
 * @param ctx 上下文指针
 * @param x X 坐标（输出）
 * @param y Y 坐标（输出）
 */
static void sdl_input_calibration(easylvgl_ctx_t *ctx, int16_t *x, int16_t *y)
{
    // SDL 不需要校准
    (void)ctx;
    (void)x;
    (void)y;
}

/** SDL2 输入驱动操作接口 */
static const easylvgl_input_ops_t sdl_input_ops = {
    .read_pointer = sdl_input_read_pointer,
    .read_keypad = sdl_input_read_keypad,
    .calibration = sdl_input_calibration
};

/** 获取 SDL2 输入驱动操作接口 */
const easylvgl_input_ops_t *easylvgl_platform_sdl2_get_input_ops(void)
{
    return &sdl_input_ops;
}

/**
 * 初始化 SDL 输入驱动私有数据
 * @param ctx 上下文指针
 * @return 0 成功，<0 失败
 */
int easylvgl_platform_sdl2_input_init(easylvgl_ctx_t *ctx)
{
    if (ctx == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    sdl_input_data_t *input_data = malloc(sizeof(sdl_input_data_t));
    if (input_data == NULL) {
        return EASYLVGL_ERR_NO_MEM;
    }
    
    memset(input_data, 0, sizeof(sdl_input_data_t));
    
    // 注意：这里假设 platform_data 已经被显示驱动使用
    // 实际应该使用独立的字段，阶段一先简化处理
    // TODO: 在 ctx 中添加 input_data 字段
    
    return EASYLVGL_OK;
}

#endif /* LUAT_USE_EASYLVGL_SDL2 */

