/**
 * @file luat_easylvgl_input_luatos.c
 * @summary LuatOS 触摸输入驱动实现
 * @responsible 读取 luat_tp 数据并映射为 LVGL pointer 输入
 */

 #include "luat_conf_bsp.h"
 #if defined(__BK72XX__)
     #include "luat_conf_bsp_air8101.h"
 #endif
 
 #if defined(LUAT_USE_EASYLVGL_LUATOS)

#include "luat_easylvgl.h"
#include "luat_tp.h"
#include "luat_log.h"
#include "luat_easylvgl_platform_luatos.h"

#define LUAT_LOG_TAG "easylvgl.luatos.input"
#include "luat_log.h"

/** 默认触摸配置绑定（由平台文件维护） */
extern luat_tp_config_t *easylvgl_platform_luatos_get_tp_bind(void);

/**
 * 读取指针输入
 */
static bool luatos_input_read_pointer(easylvgl_ctx_t *ctx, lv_indev_data_t *data)
{
    if (data == NULL) {
        return false;
    }

    luatos_platform_data_t *platform = easylvgl_luatos_get_data(ctx);
    luat_tp_config_t *tp_cfg = platform ? platform->tp_config : NULL;
    if (tp_cfg == NULL) {
        tp_cfg = easylvgl_platform_luatos_get_tp_bind();
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
        last_point.x = (lv_coord_t)tp_data[0].x_coordinate;
        last_point.y = (lv_coord_t)tp_data[0].y_coordinate;
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
static bool luatos_input_read_keypad(easylvgl_ctx_t *ctx, lv_indev_data_t *data)
{
    (void)ctx;
    (void)data;
    return false;
}

/**
 * 触摸校准占位
 */
static void luatos_input_calibration(easylvgl_ctx_t *ctx, int16_t *x, int16_t *y)
{
    (void)ctx;
    (void)x;
    (void)y;
}

/** LuatOS 输入驱动操作接口 */
static const easylvgl_input_ops_t luatos_input_ops = {
    .read_pointer = luatos_input_read_pointer,
    .read_keypad = luatos_input_read_keypad,
    .calibration = luatos_input_calibration
};

/** 获取 LuatOS 输入驱动操作接口 */
const easylvgl_input_ops_t *easylvgl_platform_luatos_get_input_ops(void)
{
    return &luatos_input_ops;
}

#endif /* LUAT_USE_EASYLVGL_LUATOS */


