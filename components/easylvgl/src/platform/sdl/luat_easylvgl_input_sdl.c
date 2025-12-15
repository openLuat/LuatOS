/**
 * @file luat_easylvgl_input_sdl.c
 * @summary SDL2 输入驱动实现
 * @responsible SDL2 鼠标/触摸输入处理
 */

#if defined(LUAT_USE_EASYLVGL_SDL2)

#include "luat_easylvgl.h"
#include <SDL2/SDL.h>
#include <stdlib.h>
#include <string.h>

/** SDL 输入驱动私有数据 */
typedef struct {
    int16_t last_x;
    int16_t last_y;
    bool left_button_down;
} sdl_input_data_t;

static void sdl_process_keyboard_event(const SDL_Event *event, easylvgl_ctx_t *ctx)
{
    if (event == NULL || ctx == NULL) {
        return;
    }

    if (event->type == SDL_KEYDOWN) {
        easylvgl_system_keyboard_post_key(ctx, (uint32_t)event->key.keysym.sym, true);
    } else if (event->type == SDL_TEXTINPUT) {
        easylvgl_system_keyboard_post_text(ctx, event->text.text);
    }
}

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
    
    // platform_data 被显示驱动使用，存储的是 sdl_display_data_t
    // 我们需要通过它来访问 SDL 窗口
    // 注意：这里需要与 luat_easylvgl_display_sdl.c 中的结构体定义保持一致
    typedef struct {
        SDL_Window *window;
        SDL_Renderer *renderer;
        SDL_Texture *texture;
        uint16_t width;
        uint16_t height;
        lv_color_format_t color_format;
    } sdl_display_data_t;
    
    sdl_display_data_t *display_data = (sdl_display_data_t *)ctx->platform_data;
    
    // 输入数据存储在静态变量中（因为 platform_data 已被显示驱动使用）
    static sdl_input_data_t input_data = {0};
    
    // 处理 SDL 事件
    SDL_Event event;
    bool has_event = false;
    int32_t sdl_x = 0, sdl_y = 0;
    
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_MOUSEMOTION) {
            sdl_x = event.motion.x;
            sdl_y = event.motion.y;
            has_event = true;
        } else if (event.type == SDL_MOUSEBUTTONDOWN) {
            if (event.button.button == SDL_BUTTON_LEFT) {
                input_data.left_button_down = true;
                sdl_x = event.button.x;
                sdl_y = event.button.y;
                has_event = true;
            }
        } else if (event.type == SDL_MOUSEBUTTONUP) {
            if (event.button.button == SDL_BUTTON_LEFT) {
                input_data.left_button_down = false;
                sdl_x = event.button.x;
                sdl_y = event.button.y;
                has_event = true;
            }
        } else if (event.type == SDL_QUIT) {
            // 窗口关闭事件
            // TODO: 可以通过回调通知上层
        } else if (event.type == SDL_KEYDOWN || event.type == SDL_TEXTINPUT) {
            sdl_process_keyboard_event(&event, ctx);
        }
    }
    
    if (has_event) {
        // 获取 SDL 窗口的实际大小（逻辑大小，考虑高 DPI 缩放）
        int window_w = 0, window_h = 0;
        if (display_data->window != NULL) {
            SDL_GetWindowSize(display_data->window, &window_w, &window_h);
        }
        
        // 如果无法获取窗口大小，使用显示驱动的存储值
        if (window_w == 0 || window_h == 0) {
            window_w = display_data->width;
            window_h = display_data->height;
        }
        
        // 将 SDL 坐标转换为 LVGL 逻辑坐标
        // LVGL 的逻辑分辨率存储在 ctx->width 和 ctx->height
        int32_t lvgl_x, lvgl_y;
        
        if (window_w > 0 && window_h > 0 && ctx->width > 0 && ctx->height > 0) {
            // 按比例缩放坐标
            lvgl_x = (int32_t)((int64_t)sdl_x * ctx->width / window_w);
            lvgl_y = (int32_t)((int64_t)sdl_y * ctx->height / window_h);
            
            // 限制坐标范围
            if (lvgl_x < 0) lvgl_x = 0;
            if (lvgl_x >= ctx->width) lvgl_x = ctx->width - 1;
            if (lvgl_y < 0) lvgl_y = 0;
            if (lvgl_y >= ctx->height) lvgl_y = ctx->height - 1;
        } else {
            // 如果无法转换，直接使用 SDL 坐标（兼容性处理）
            lvgl_x = sdl_x;
            lvgl_y = sdl_y;
        }
        
        input_data.last_x = (int16_t)lvgl_x;
        input_data.last_y = (int16_t)lvgl_y;
    }
    
    // 填充输入数据
    data->point.x = input_data.last_x;
    data->point.y = input_data.last_y;
    data->state = input_data.left_button_down ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    
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

