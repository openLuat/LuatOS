/**
 * @file luat_airui_input_sdl.c
 * @summary SDL2 输入驱动实现
 * @responsible SDL2 鼠标/触摸输入处理
 */

#include "luat_conf_bsp.h"

#if defined(LUAT_USE_AIRUI_SDL2)

#include "luat_airui.h"
#include <SDL2/SDL.h>
#include <stdlib.h>
#include <string.h>
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"

#define LUAT_LOG_TAG "airui_input_sdl"
#include "luat_log.h"

/** SDL 输入驱动私有数据 */
typedef struct {
    int16_t last_x;
    int16_t last_y;
    bool left_button_down;
} sdl_input_data_t;

/** 按键队列大小 */
#define AIRUI_KEYPAD_QUEUE_SIZE 32

/** 按键事件结构体 */
typedef struct {
    uint32_t key; // 按键值
    lv_indev_state_t state; // 按键状态
} airui_keypad_event_t;

static airui_keypad_event_t g_keypad_queue[AIRUI_KEYPAD_QUEUE_SIZE]; // 按键队列
static uint8_t g_keypad_head = 0; // 按键队列头
static uint8_t g_keypad_tail = 0; // 按键队列尾
static bool g_keypad_enabled = false; // 按键是否启用

/** SDL2 按键映射配置 */
typedef struct {
    SDL_Keycode up;      /**< 上方向键 */
    SDL_Keycode down;    /**< 下方向键 */
    SDL_Keycode left;    /**< 左方向键 */
    SDL_Keycode right;   /**< 右方向键 */
    SDL_Keycode ok;      /**< 确认键 */
    SDL_Keycode back;    /**< 返回键 */
} sdl_keypad_cfg_t;

// 默认按键配置
static sdl_keypad_cfg_t g_keypad_cfg = {
    .up = SDLK_UP,      // 默认使用方向键
    .down = SDLK_DOWN,
    .left = SDLK_LEFT,
    .right = SDLK_RIGHT,
    .ok = SDLK_RETURN,
    .back = SDLK_ESCAPE
};

// 按键队列推入
static bool airui_keypad_queue_push(uint32_t key, lv_indev_state_t state)
{
    uint8_t next = (uint8_t)((g_keypad_tail + 1) % AIRUI_KEYPAD_QUEUE_SIZE);
    if (next == g_keypad_head) {
        return false;
    }
    g_keypad_queue[g_keypad_tail].key = key;
    g_keypad_queue[g_keypad_tail].state = state;
    g_keypad_tail = next;
    return true;
}

// 按键队列弹出
static bool airui_keypad_queue_pop(lv_indev_data_t *data)
{
    if (data == NULL || g_keypad_head == g_keypad_tail) {
        return false;
    }
    data->key = g_keypad_queue[g_keypad_head].key;
    data->state = g_keypad_queue[g_keypad_head].state;
    g_keypad_head = (uint8_t)((g_keypad_head + 1) % AIRUI_KEYPAD_QUEUE_SIZE);
    return true;
}

// 将SDL按键映射为LVGL按键
static uint32_t sdl_map_to_lvgl_key(SDL_Keycode key)
{
    // LVGL的KEYPAD模式使用LV_KEY_NEXT和LV_KEY_PREV来移动焦点
    // 方向键需要转换为NEXT/PREV才能正确导航
    // 右和下 -> NEXT (下一个对象)
    // 左和上 -> PREV (上一个对象)
    
    if (key == g_keypad_cfg.right || key == SDLK_d) {
        return LV_KEY_NEXT;  // 右方向键 -> 下一个
    }
    if (key == g_keypad_cfg.down || key == SDLK_s) {
        return LV_KEY_NEXT;  // 下方向键 -> 下一个
    }
    if (key == g_keypad_cfg.left || key == SDLK_a) {
        return LV_KEY_PREV;  // 左方向键 -> 上一个
    }
    if (key == g_keypad_cfg.up || key == SDLK_w) {
        return LV_KEY_PREV;  // 上方向键 -> 上一个
    }
    if (key == g_keypad_cfg.ok || key == SDLK_RETURN || key == SDLK_KP_ENTER || key == SDLK_SPACE) {
        return LV_KEY_ENTER;
    }
    if (key == g_keypad_cfg.back || key == SDLK_ESCAPE) {
        return LV_KEY_ESC;
    }
    return 0;
}

/**
 * 将字符串转换为SDL_Keycode
 * @param key_name 按键名称（如 "w", "up", "return", "space" 等）
 * @return SDL_Keycode，如果无法识别则返回0
 */
static SDL_Keycode sdl_string_to_keycode(const char *key_name)
{
    if (key_name == NULL) {
        return 0;
    }
    
    // 方向键
    if (strcmp(key_name, "up") == 0) return SDLK_UP;
    if (strcmp(key_name, "down") == 0) return SDLK_DOWN;
    if (strcmp(key_name, "left") == 0) return SDLK_LEFT;
    if (strcmp(key_name, "right") == 0) return SDLK_RIGHT;
    
    // 字母键
    if (strlen(key_name) == 1 && key_name[0] >= 'a' && key_name[0] <= 'z') {
        return SDLK_a + (key_name[0] - 'a');
    }
    if (strlen(key_name) == 1 && key_name[0] >= 'A' && key_name[0] <= 'Z') {
        return SDLK_a + (key_name[0] - 'A');
    }
    
    // 数字键
    if (strlen(key_name) == 1 && key_name[0] >= '0' && key_name[0] <= '9') {
        return SDLK_0 + (key_name[0] - '0');
    }
    
    // 特殊键
    if (strcmp(key_name, "return") == 0 || strcmp(key_name, "enter") == 0) return SDLK_RETURN;
    if (strcmp(key_name, "space") == 0) return SDLK_SPACE;
    if (strcmp(key_name, "escape") == 0 || strcmp(key_name, "esc") == 0) return SDLK_ESCAPE;
    if (strcmp(key_name, "backspace") == 0) return SDLK_BACKSPACE;
    if (strcmp(key_name, "tab") == 0) return SDLK_TAB;
    if (strcmp(key_name, "shift") == 0) return SDLK_LSHIFT;
    if (strcmp(key_name, "ctrl") == 0) return SDLK_LCTRL;
    if (strcmp(key_name, "alt") == 0) return SDLK_LALT;
    
    return 0;
}

// 绑定SDL2按键
void airui_platform_sdl2_bind_keypad(bool enable)
{
    g_keypad_enabled = enable;
    if (!enable) {
        g_keypad_head = 0;
        g_keypad_tail = 0;
    }
}

/**
 * 配置SDL2按键映射
 * @param cfg 按键配置，如果为NULL则使用默认配置
 */
void airui_platform_sdl2_bind_keypad_cfg(const void *cfg_ptr)
{
    if (cfg_ptr != NULL) {
        // 从Lua绑定层传递的结构体
        typedef struct {
            int up;
            int down;
            int left;
            int right;
            int ok;
            int back;
        } sdl_keypad_cfg_lua_t;
        
        const sdl_keypad_cfg_lua_t *cfg = (const sdl_keypad_cfg_lua_t *)cfg_ptr;
        g_keypad_cfg.up = (SDL_Keycode)cfg->up;
        g_keypad_cfg.down = (SDL_Keycode)cfg->down;
        g_keypad_cfg.left = (SDL_Keycode)cfg->left;
        g_keypad_cfg.right = (SDL_Keycode)cfg->right;
        g_keypad_cfg.ok = (SDL_Keycode)cfg->ok;
        g_keypad_cfg.back = (SDL_Keycode)cfg->back;
        LLOGD("SDL2 keypad config: up=%d down=%d left=%d right=%d ok=%d back=%d",
              g_keypad_cfg.up, g_keypad_cfg.down, g_keypad_cfg.left, 
              g_keypad_cfg.right, g_keypad_cfg.ok, g_keypad_cfg.back);
    } else {
        // 重置为默认配置
        g_keypad_cfg.up = SDLK_UP;
        g_keypad_cfg.down = SDLK_DOWN;
        g_keypad_cfg.left = SDLK_LEFT;
        g_keypad_cfg.right = SDLK_RIGHT;
        g_keypad_cfg.ok = SDLK_RETURN;
        g_keypad_cfg.back = SDLK_ESCAPE;
    }
    g_keypad_enabled = true;
}

/**
 * 清除当前 SDL 预编辑文本（如果存在）
 */
void airui_system_keyboard_clear_preedit(airui_ctx_t *ctx)
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
void airui_system_keyboard_set_preedit(airui_ctx_t *ctx, const char *text)
{
    if (ctx == NULL || ctx->focused_textarea == NULL) {
        return;
    }

    lv_obj_t *textarea = ctx->focused_textarea;
    // sdl完整返回预编辑文字，所以需要清空重填
    airui_system_keyboard_clear_preedit(ctx);

    if (text == NULL || text[0] == '\0') {
        return;
    }

    ctx->system_keyboard_preedit_pos = (int32_t)lv_textarea_get_cursor_pos(textarea);
    lv_textarea_add_text(textarea, text);
    ctx->system_keyboard_preedit_len = (int32_t)(lv_textarea_get_cursor_pos(textarea) - ctx->system_keyboard_preedit_pos);
    LLOGD("airui_system_keyboard_set_preedit: system_keyboard_preedit_len=%d", ctx->system_keyboard_preedit_len);
}

/**
 * 处理 SDL 键盘输入事件，将其转化为 LVGL 预编辑、按键或文本事件
 * @param event SDL 事件指针
 * @param ctx airui 上下文
 */
static void sdl_process_keyboard_event(const SDL_Event *event, airui_ctx_t *ctx)
{
    if (event == NULL || ctx == NULL) {
        return;
    }

    // LLOGD("sdl_process_keyboard_event: event->type=%d", event->type);

    switch (event->type) {
    case SDL_KEYUP:
    case SDL_KEYDOWN: {
        lv_indev_state_t key_state = (event->type == SDL_KEYDOWN) ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
        uint32_t keypad_key = sdl_map_to_lvgl_key(event->key.keysym.sym);
        if (g_keypad_enabled && keypad_key != 0) {
            airui_keypad_queue_push(keypad_key, key_state);
        }

        if (event->type != SDL_KEYDOWN) {
            break;
        }

        // 系统键盘映射（给 textarea 文本编辑使用）
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
            airui_system_keyboard_post_key(ctx, lv_key, true);
        }
        break;
    }
    case SDL_TEXTEDITING:
        // 进入预编辑阶段，保存 SIMD 编辑器反馈的未提交文本
        // LLOGD("SDL_TEXTEDITING text=%s cursor=%d length=%d", event->edit.text, event->edit.start, event->edit.length);
        airui_system_keyboard_set_preedit(ctx, event->edit.text);
        ctx->system_keyboard_preedit_active = true;
        break;
    case SDL_TEXTINPUT:
        // 文本输入完成，清理预编辑状态后提交最终字符串
        airui_system_keyboard_clear_preedit(ctx);
        ctx->system_keyboard_preedit_active = false;
        airui_system_keyboard_post_text(ctx, event->text.text);
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
static bool sdl_input_read_pointer(airui_ctx_t *ctx, lv_indev_data_t *data)
{
    if (ctx == NULL || ctx->platform_data == NULL || data == NULL) {
        return false;
    }
    
    // platform_data 被显示驱动使用，存储的是 sdl_display_data_t
    // 我们需要通过它来访问 SDL 窗口
    // 注意：这里需要与 luat_airui_display_sdl.c 中的结构体定义保持一致
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
            airui_deinit(ctx);
            SDL_Quit();
            exit(0);
        } else if (event.type == SDL_KEYDOWN || event.type == SDL_KEYUP || event.type == SDL_TEXTINPUT || event.type == SDL_TEXTEDITING) {
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
static bool sdl_input_read_keypad(airui_ctx_t *ctx, lv_indev_data_t *data)
{
    (void)ctx;
    if (!g_keypad_enabled) {
        return false;
    }
    return airui_keypad_queue_pop(data);
}

/**
 * SDL2 输入驱动校准
 * @param ctx 上下文指针
 * @param x X 坐标（输出）
 * @param y Y 坐标（输出）
 */
static void sdl_input_calibration(airui_ctx_t *ctx, int16_t *x, int16_t *y)
{
    // SDL 不需要校准
    (void)ctx;
    (void)x;
    (void)y;
}

/**
 * SDL2 平台同步文本输入矩形给 SDL
 */
void airui_platform_sdl2_set_text_input_rect(airui_ctx_t *ctx, lv_obj_t *target) 
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
    // LLOGD("airui_platform_sdl2_set_text_input_rect: rect=%d,%d,%d,%d", rect.x, rect.y, rect.w, rect.h);
    SDL_SetTextInputRect(&rect);
}

/** SDL2 输入驱动操作接口 */
static const airui_input_ops_t sdl_input_ops = {
    .read_pointer = sdl_input_read_pointer,
    .read_keypad = sdl_input_read_keypad,
    .calibration = sdl_input_calibration
};

/** 获取 SDL2 输入驱动操作接口 */
const airui_input_ops_t *airui_platform_sdl2_get_input_ops(void)
{
    return &sdl_input_ops;
}

/**
 * 初始化 SDL 输入驱动私有数据
 * @param ctx 上下文指针
 * @return 0 成功，<0 失败
 */
int airui_platform_sdl2_input_init(airui_ctx_t *ctx)
{
    if (ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    sdl_input_data_t *input_data = malloc(sizeof(sdl_input_data_t));
    if (input_data == NULL) {
        return AIRUI_ERR_NO_MEM;
    }
    
    memset(input_data, 0, sizeof(sdl_input_data_t));
    
    // 注意：这里假设 platform_data 已经被显示驱动使用
    // 实际应该使用独立的字段，阶段一先简化处理
    // TODO: 在 ctx 中添加 input_data 字段
    
    return AIRUI_OK;
}

#endif /* LUAT_USE_AIRUI_SDL2 */

