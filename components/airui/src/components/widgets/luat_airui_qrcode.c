/**
 * @file luat_airui_qrcode.c
 * @summary Qrcode 组件实现
 * @responsible Qrcode 组件创建与属性设置
 */

#include "luat_airui_component.h"
#include "lvgl9/src/libs/qrcode/lv_qrcode.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lua.h"
#include "lauxlib.h"
#include <string.h>
#include <stdint.h>

#define LUAT_LOG_TAG "airui.qrcode"
#include "luat_log.h"

// 创建二维码组件
lv_obj_t *airui_qrcode_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;

    airui_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);

    if (ctx == NULL) {
        return NULL;
    }

    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);
    int size = airui_marshal_integer(L, idx, "size", 160);
    const char *data = airui_marshal_string(L, idx, "data", NULL);
    bool quiet_zone = airui_marshal_bool(L, idx, "quiet_zone", true);

    lv_color_t dark_color = lv_color_black();
    lv_color_t light_color = lv_color_white();
    lv_color_t parsed_color;
    if (airui_marshal_color(L, idx, "dark_color", &parsed_color)) {
        dark_color = parsed_color;
    }
    if (airui_marshal_color(L, idx, "light_color", &parsed_color)) {
        light_color = parsed_color;
    }

    if (size <= 0) {
        size = 160;
    }

    lv_obj_t *qrcode = lv_qrcode_create(parent);
    if (qrcode == NULL) {
        return NULL;
    }

    lv_obj_set_pos(qrcode, x, y);
    lv_qrcode_set_size(qrcode, size);
    lv_qrcode_set_dark_color(qrcode, dark_color);
    lv_qrcode_set_light_color(qrcode, light_color);
    lv_qrcode_set_quiet_zone(qrcode, quiet_zone);

    if (data != NULL && data[0] != '\0') {
        lv_result_t ret = lv_qrcode_update(qrcode, data, (uint32_t)strlen(data));
        if (ret != LV_RESULT_OK) {
            LLOGW("qrcode init data too long or invalid");
        }
    }

    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, qrcode, AIRUI_COMPONENT_QRCODE);
    if (meta == NULL) {
        lv_obj_delete(qrcode);
        return NULL;
    }

    return qrcode;
}

// 设置二维码数据
int airui_qrcode_set_data(lv_obj_t *qrcode, const void *data, size_t len)
{
    if (qrcode == NULL || data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_result_t ret = lv_qrcode_update(qrcode, data, (uint32_t)len);
    if (ret != LV_RESULT_OK) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    return AIRUI_OK;
}

// 设置二维码尺寸
int airui_qrcode_set_size(lv_obj_t *qrcode, int size)
{
    if (qrcode == NULL || size <= 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_qrcode_set_size(qrcode, size);
    return AIRUI_OK;
}

// 设置二维码前景/背景色
int airui_qrcode_set_colors(lv_obj_t *qrcode, lv_color_t dark_color, lv_color_t light_color)
{
    if (qrcode == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_qrcode_set_dark_color(qrcode, dark_color);
    lv_qrcode_set_light_color(qrcode, light_color);
    return AIRUI_OK;
}

// 设置静区开关
int airui_qrcode_set_quiet_zone(lv_obj_t *qrcode, bool enable)
{
    if (qrcode == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_qrcode_set_quiet_zone(qrcode, enable);
    return AIRUI_OK;
}
