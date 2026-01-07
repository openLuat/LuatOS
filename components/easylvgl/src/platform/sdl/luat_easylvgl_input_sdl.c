/**
 * @file luat_easylvgl_input_sdl.c
 * @summary SDL2 输入驱动实现
 * @responsible SDL2 鼠标/触摸输入处理
 */

#include "luat_conf_bsp.h"

#if defined(LUAT_USE_EASYLVGL_SDL2)

#include "luat_easylvgl.h"
#include <SDL2/SDL.h>
#include <stdlib.h>
#include <string.h>
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"

#define LUAT_LOG_TAG "easylvgl_input_sdl"
#include "luat_log.h"

/** SDL 输入驱动私有数据 */
typedef struct {
    int16_t last_x;
    int16_t last_y;
    bool left_button_down;
} sdl_input_data_t;

/**
 * 清除当前 SDL 预编辑文本（如果存在）
 */
void easylvgl_system_keyboard_clear_preedit(easylvgl_ctx_t *ctx)
{
    if (ctx == NULL || ctx->focused_textarea == NULL || ctx->system_keyboard_preedit_len <= 0) {
        if (ctx != NULL && ctx->focused_textarea != NULL) {
            ctx->system_keyboard_preedit_pos = (int32_t)lv_textarea_get_cursor_pos(ctx->focused_textarea);
        }
        return;
    }

    lv_obj_t *textarea = ctx->focused_textarea;
    lv_textarea_set_cursor_pos(textarea, ctx->system_keyboard_preedit_pos);
    int32_t len = ctx->system_keyboard_preedit_len;
    ctx->system_keyboard_preedit_len = 0;

    for (int32_t i = 0; i < len; ++i) {
        lv_textarea_delete_char_forward(textarea);
    }

    ctx->system_keyboard_preedit_pos = (int32_t)lv_textarea_get_cursor_pos(textarea);
}

/**
 * 插入或更新 SDL 预编辑文本
 */
void easylvgl_system_keyboard_set_preedit(easylvgl_ctx_t *ctx, const char *text)
{
    if (ctx == NULL || ctx->focused_textarea == NULL) {
        return;
    }

    lv_obj_t *textarea = ctx->focused_textarea;
    // sdl完整返回预编辑文字，所以需要清空重填
    easylvgl_system_keyboard_clear_preedit(ctx);

    if (text == NULL || text[0] == '\0') {
        return;
    }

    ctx->system_keyboard_preedit_pos = (int32_t)lv_textarea_get_cursor_pos(textarea);
    lv_textarea_add_text(textarea, text);
    ctx->system_keyboard_preedit_len = (int32_t)(lv_textarea_get_cursor_pos(textarea) - ctx->system_keyboard_preedit_pos);
    LLOGD("easylvgl_system_keyboard_set_preedit: system_keyboard_preedit_len=%d", ctx->system_keyboard_preedit_len);
}

/**
 * 处理 SDL 键盘输入事件，将其转化为 LVGL 预编辑、按键或文本事件
 * @param event SDL 事件指针
 * @param ctx easylvgl 上下文
 */
static void sdl_process_keyboard_event(const SDL_Event *event, easylvgl_ctx_t *ctx)
{
    if (event == NULL || ctx == NULL) {
        return;
    }

    // LLOGD("sdl_process_keyboard_event: event->type=%d", event->type);

    switch (event->type) {
    case SDL_KEYDOWN: {
        // 虚拟按键映射到 LVGL 键值（回车/退格/ESC）
        uint32_t lv_key = 0;
        switch (event->key.keysym.sym) {
        case SDLK_BACKSPACE:
            lv_key = LV_KEY_BACKSPACE;
            break;
        case SDLK_RETURN:
        case SDLK_KP_ENTER:
            lv_key = LV_KEY_ENTER;
            break;
        case SDLK_ESCAPE:
            lv_key = LV_KEY_ESC;
            break;
        default:
            break;
        }
        if (lv_key != 0) {
            easylvgl_system_keyboard_post_key(ctx, lv_key, true);
        }
        break;
    }
    case SDL_TEXTEDITING:
        // 进入预编辑阶段，保存 SIMD 编辑器反馈的未提交文本
        // LLOGD("SDL_TEXTEDITING text=%s cursor=%d length=%d", event->edit.text, event->edit.start, event->edit.length);
        easylvgl_system_keyboard_set_preedit(ctx, event->edit.text);
        ctx->system_keyboard_preedit_active = true;
        break;
    case SDL_TEXTINPUT:
        // 文本输入完成，清理预编辑状态后提交最终字符串
        easylvgl_system_keyboard_clear_preedit(ctx);
        ctx->system_keyboard_preedit_active = false;
        easylvgl_system_keyboard_post_text(ctx, event->text.text);
        break;
    default:
        break;
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
            // 窗口关闭时 SDL 会发出 SDL_QUIT，优雅清理并退出程序
            LLOGI("SDL_QUIT received, shutting down");
            easylvgl_deinit(ctx);
            SDL_Quit();
            exit(0);
        } else if (event.type == SDL_KEYDOWN || event.type == SDL_TEXTINPUT || event.type == SDL_TEXTEDITING) {
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

/**
 * SDL2 平台同步文本输入矩形给 SDL
 */
void easylvgl_platform_sdl2_set_text_input_rect(easylvgl_ctx_t *ctx, lv_obj_t *target) 
{
    // 基础参数和平台数据校验
    if (ctx == NULL || target == NULL || ctx->platform_data == NULL) {
        return;
    }

    // 复制 SDL 显示私有数据类型定义（与 display 驱动同步）
    typedef struct {
        SDL_Window *window;
        SDL_Renderer *renderer;
        SDL_Texture *texture;
        uint16_t width;
        uint16_t height;
        lv_color_format_t color_format;
    } sdl_display_data_t;

    // 获取 display_data 指针并判空
    sdl_display_data_t *display_data = (sdl_display_data_t *)ctx->platform_data;
    if (display_data == NULL || display_data->window == NULL) {
        return;
    }

    // 获取 LVGL 对象的屏幕坐标区域
    lv_area_t coords;
    lv_obj_get_coords(target, &coords);

    // 初始将 lvgl 区域直接转换为 SDL_Rect
    SDL_Rect rect = {
        .x = coords.x1,
        .y = coords.y1,
        .w = lv_area_get_width(&coords),
        .h = lv_area_get_height(&coords)
    };

    // 获取窗口实际像素尺寸（窗口可缩放情况下）
    int window_w = display_data->width;
    int window_h = display_data->height;
    if (display_data->window != NULL) {
        SDL_GetWindowSize(display_data->window, &window_w, &window_h);
    }

    // 按实际窗口尺寸缩放 LVGL 坐标
    if (window_w > 0 && window_h > 0 && ctx->width > 0 && ctx->height > 0) {
        rect.x = (int32_t)((int64_t)coords.x1 * window_w / ctx->width);
        rect.y = (int32_t)((int64_t)coords.y1 * window_h / ctx->height);
        rect.w = (int32_t)((int64_t)lv_area_get_width(&coords) * window_w / ctx->width);
        rect.h = (int32_t)((int64_t)lv_area_get_height(&coords) * window_h / ctx->height);
    }

    // 如果是文本区域，进一步精确到光标位置
    lv_point_t letter_pos = {0};
    lv_obj_t *label = lv_textarea_get_label(target);
    if (label != NULL) {
        // 获取当前光标在 label 内的字符 id
        uint32_t cp = lv_textarea_get_cursor_pos(target);
        // 获取 label 区域坐标
        lv_area_t label_coords;
        lv_obj_get_coords(label, &label_coords);
        // 查询某字符左上角相对 label 的偏移
        lv_label_get_letter_pos(label, cp, &letter_pos);
        // 用 label 区域原点 + 字符偏移指定输入法聚焦位
        rect.x = label_coords.x1 + letter_pos.x;
        rect.y = label_coords.y1 + letter_pos.y;
        // 推荐一个典型大小，防止输入法候选窗太大（可微调）
        rect.w = 24;
        rect.h = 24;
    }

    // 防止宽/高为 0，输入法无法显示（设为最小 1）
    if (rect.w <= 0) {
        rect.w = 1;
    }
    if (rect.h <= 0) {
        rect.h = 1;
    }

    // 日志打印最终输入法矩形，并通知 SDL
    LLOGD("easylvgl_platform_sdl2_set_text_input_rect: rect=%d,%d,%d,%d", rect.x, rect.y, rect.w, rect.h);
    SDL_SetTextInputRect(&rect);
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

