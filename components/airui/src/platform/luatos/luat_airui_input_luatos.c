/**
 * @file luat_airui_input_luatos.c
 * @summary LuatOS 触摸输入驱动实现
 * @responsible 读取 luat_tp 数据并映射为 LVGL pointer 输入
 */

 #include "luat_conf_bsp.h"
 #if defined(__BK72XX__)
     #include "luat_conf_bsp_air8101.h"
 #endif
 
 #if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui.h"
#include "luat_tp.h"
#include "luat_gpio.h"
#include "luat_log.h"
#include "luat_airui_platform_luatos.h"

#include <string.h>

#define LUAT_LOG_TAG "airui.luatos.input"
#include "luat_log.h"

/** 默认触摸配置绑定（由平台文件维护） */
extern luat_tp_config_t *airui_platform_luatos_get_tp_bind(void);

/** 按键队列大小 */
#define AIRUI_KEYPAD_QUEUE_SIZE 16

/** 按键事件结构体 */
typedef struct {
    uint32_t key; // 按键值
    lv_indev_state_t state; // 按键状态
} airui_keypad_event_t;

static airui_keypad_event_t g_keypad_queue[AIRUI_KEYPAD_QUEUE_SIZE];
static uint8_t g_keypad_head = 0; // 按键队列头
static uint8_t g_keypad_tail = 0; // 按键队列尾
static uint8_t g_keypad_state_mask = 0; // 按键状态掩码
static uint8_t g_keypad_has_state = 0; // 按键状态是否有效
static uint8_t g_keypad_gpio_inited = 0; // 按键GPIO是否初始化
static uint8_t g_tp_dir_warned = 0; // TP/LCD 方向不一致告警是否已打印


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

// 根据索引获取按键GPIO引脚
static int airui_keypad_get_pin_by_idx(const airui_luatos_keypad_cfg_t *cfg, uint8_t idx)
{
    if (cfg == NULL) {
        return -1;
    }
    switch (idx) {
        case 0: return cfg->up;
        case 1: return cfg->down;
        case 2: return cfg->left;
        case 3: return cfg->right;
        case 4: return cfg->ok;
        case 5: return cfg->back;
        default: return -1;
    }
}

// 根据索引获取按键LVGL键值
static uint32_t airui_keypad_get_lv_key_by_idx(uint8_t idx)
{
    switch (idx) {
        // 与 SDL 路径保持一致：方向键使用 NEXT/PREV 进行焦点导航
        // up/left -> PREV, down/right -> NEXT
        case 0: return LV_KEY_PREV;
        case 1: return LV_KEY_NEXT;
        case 2: return LV_KEY_PREV;
        case 3: return LV_KEY_NEXT;
        case 4: return LV_KEY_ENTER;
        case 5: return LV_KEY_ESC;
        default: return 0;
    }
}

// 初始化按键GPIO一次
static void airui_luatos_keypad_init_gpio_once(const airui_luatos_keypad_cfg_t *cfg)
{
    if (cfg == NULL || cfg->enabled == 0 || g_keypad_gpio_inited) {
        return;
    }

    for (uint8_t i = 0; i < 6; i++) {
        int pin = airui_keypad_get_pin_by_idx(cfg, i);
        if (pin >= 0) {
            luat_gpio_mode(pin, LUAT_GPIO_INPUT, cfg->pull_mode, LUAT_GPIO_LOW);
        }
    }

    g_keypad_gpio_inited = 1;
}

// 读取按键状态掩码
static uint8_t airui_luatos_keypad_read_state_mask(const airui_luatos_keypad_cfg_t *cfg)
{
    uint8_t mask = 0;
    if (cfg == NULL || cfg->enabled == 0) {
        return 0;
    }

    for (uint8_t i = 0; i < 6; i++) {
        int pin = airui_keypad_get_pin_by_idx(cfg, i);
        if (pin < 0) {
            continue;
        }

        int level = luat_gpio_get(pin);
        bool pressed = (cfg->active_low != 0) ? (level == 0) : (level != 0);
        if (pressed) {
            mask |= (uint8_t)(1U << i);
        }
    }

    return mask;
}

// 收集按键事件
static void airui_luatos_keypad_collect_events(const airui_luatos_keypad_cfg_t *cfg)
{
    if (cfg == NULL || cfg->enabled == 0) {
        return;
    }

    airui_luatos_keypad_init_gpio_once(cfg);
    uint8_t curr_mask = airui_luatos_keypad_read_state_mask(cfg);

    if (!g_keypad_has_state) {
        g_keypad_state_mask = curr_mask;
        g_keypad_has_state = 1;
        return;
    }

    uint8_t changed = (uint8_t)(curr_mask ^ g_keypad_state_mask);
    if (changed == 0) {
        return;
    }

    for (uint8_t i = 0; i < 6; i++) {
        uint8_t bit = (uint8_t)(1U << i);
        if ((changed & bit) == 0) {
            continue;
        }

        uint32_t key = airui_keypad_get_lv_key_by_idx(i);
        if (key == 0) {
            continue;
        }

        lv_indev_state_t state = (curr_mask & bit) ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
        airui_keypad_queue_push(key, state);
    }

    g_keypad_state_mask = curr_mask;
}

// 对齐 tp 库：按 tp.direction + swap_xy 处理触摸坐标
static void airui_luatos_apply_tp_transform(int32_t *x, int32_t *y, int32_t w, int32_t h, uint8_t tp_dir, uint8_t swap_xy)
{
    if (x == NULL || y == NULL || w <= 0 || h <= 0) {
        return;
    }

    int32_t src_x = *x;
    int32_t src_y = *y;

    // 旋转
    switch (tp_dir & 0x03) {
        case LUAT_TP_ROTATE_90:
            *x = src_y;
            *y = w - src_x;
            break;
        case LUAT_TP_ROTATE_180:
            *x = w - src_x;
            *y = h - src_y;
            break;
        case LUAT_TP_ROTATE_270:
            *x = h - src_y;
            *y = src_x;
            break;
        default:
            break;
    }

    // 交换
    if (swap_xy & LUAT_TP_SWAP_X) {
        *x = w - *x;
    }
    if (swap_xy & LUAT_TP_SWAP_Y) {
        *y = h - *y;
    }
}

/**
 * 读取指针输入
 */
static bool luatos_input_read_pointer(airui_ctx_t *ctx, lv_indev_data_t *data)
{
    if (data == NULL) {
        return false;
    }

    luatos_platform_data_t *platform = airui_luatos_get_data(ctx);
    luat_tp_config_t *tp_cfg = platform ? platform->tp_config : NULL;
    if (tp_cfg == NULL) {
        tp_cfg = airui_platform_luatos_get_tp_bind();
    }
    if (tp_cfg == NULL) {
        return false;
    }

    luat_tp_data_t *tp_data = tp_cfg->tp_data;
    if (tp_data == NULL) {
        return false;
    }

    static lv_point_t last_point = {0, 0};
    bool pressed = (tp_data[0].event == TP_EVENT_TYPE_DOWN || tp_data[0].event == TP_EVENT_TYPE_MOVE);

    if (pressed) {
        // 获取初始触摸坐标
        int32_t x = (int32_t)tp_data[0].x_coordinate;
        int32_t y = (int32_t)tp_data[0].y_coordinate;

        // 获取触摸方向和lcd旋转方向， 以lcd方向为准
        uint8_t tp_dir = tp_cfg->direction & 0x03;
        uint8_t lcd_dir = 0;
        if (platform != NULL && platform->lcd_conf != NULL) {
            lcd_dir = platform->lcd_conf->direction & 0x03;
        }

        // 应用触摸方向和lcd旋转方向
        int32_t tp_w = tp_cfg->w > 0 ? tp_cfg->w : ctx->width;
        int32_t tp_h = tp_cfg->h > 0 ? tp_cfg->h : ctx->height;
        airui_luatos_apply_tp_transform(&x, &y, tp_w, tp_h, tp_dir, tp_cfg->swap_xy);

        // 检查触摸方向和lcd旋转方向是否一致
        if (!g_tp_dir_warned && tp_dir != lcd_dir) {
            LLOGW("tp direction(%d) != lcd direction(%d), check tp.init/lcd.init direction consistency", tp_dir, lcd_dir);
            g_tp_dir_warned = 1;
        }

        if (x < 0) {
            x = 0;
        } else if (x >= ctx->width) {
            x = ctx->width - 1;
        }

        if (y < 0) {
            y = 0;
        } else if (y >= ctx->height) {
            y = ctx->height - 1;
        }

        last_point.x = (lv_coord_t)x;
        last_point.y = (lv_coord_t)y;
        data->state = LV_INDEV_STATE_PRESSED;
    } else {
        data->state = LV_INDEV_STATE_RELEASED;
    }
    data->point = last_point;
    return pressed;
}

/**
 * 键盘输入占位
 */
static bool luatos_input_read_keypad(airui_ctx_t *ctx, lv_indev_data_t *data)
{
    if (ctx == NULL || data == NULL) {
        return false;
    }

    // 获取平台数据
    luatos_platform_data_t *platform = airui_luatos_get_data(ctx);
    if (platform == NULL || platform->keypad_cfg.enabled == 0) {
        return false;
    }

    // 收集按键事件
    airui_luatos_keypad_collect_events(&platform->keypad_cfg);
    return airui_keypad_queue_pop(data);
}

/**
 * 触摸校准占位
 */
static void luatos_input_calibration(airui_ctx_t *ctx, int16_t *x, int16_t *y)
{
    (void)ctx;
    (void)x;
    (void)y;
}

/** LuatOS 输入驱动操作接口 */
static const airui_input_ops_t luatos_input_ops = {
    .read_pointer = luatos_input_read_pointer,
    .read_keypad = luatos_input_read_keypad,
    .calibration = luatos_input_calibration
};

/** 获取 LuatOS 输入驱动操作接口 */
const airui_input_ops_t *airui_platform_luatos_get_input_ops(void)
{
    return &luatos_input_ops;
}

#endif /* LUAT_USE_AIRUI_LUATOS */


