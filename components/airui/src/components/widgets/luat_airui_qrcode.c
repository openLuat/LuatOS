/**
 * @file luat_airui_qrcode.c
 * @summary Qrcode 组件实现
 * @responsible Qrcode 组件创建与属性设置
 */

#include "luat_airui_component.h"
#include "lvgl9/src/libs/qrcode/lv_qrcode.h"
#include "lvgl9/src/core/lv_obj.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include <string.h>
#include <stdint.h>

#define LUAT_LOG_TAG "airui.qrcode"
#include "luat_log.h"

typedef struct {
    char *data;
    size_t len;
} airui_qrcode_data_t;

static airui_qrcode_data_t *airui_qrcode_get_data(lv_obj_t *qrcode);
static int airui_qrcode_cache_data(lv_obj_t *qrcode, const void *data, size_t len);
static int airui_qrcode_refresh_cached(lv_obj_t *qrcode);
void airui_qrcode_release_data(airui_component_meta_t *meta);


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

    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, qrcode, AIRUI_COMPONENT_QRCODE);
    if (meta == NULL) {
        lv_obj_delete(qrcode);
        return NULL;
    }

    airui_qrcode_data_t *qrcode_data = (airui_qrcode_data_t *)luat_heap_malloc(sizeof(airui_qrcode_data_t));
    if (qrcode_data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(qrcode);
        return NULL;
    }
    memset(qrcode_data, 0, sizeof(airui_qrcode_data_t));
    meta->user_data = qrcode_data;

    if (data != NULL && data[0] != '\0') {
        size_t data_len = strlen(data);
        if (airui_qrcode_cache_data(qrcode, data, data_len) != AIRUI_OK ||
            airui_qrcode_refresh_cached(qrcode) != AIRUI_OK) {
            LLOGW("qrcode init data too long or invalid");
        }
    }

    return qrcode;
}

// 获取二维码数据
static airui_qrcode_data_t *airui_qrcode_get_data(lv_obj_t *qrcode)
{
    airui_component_meta_t *meta = airui_component_meta_get(qrcode);
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }

    return (airui_qrcode_data_t *)meta->user_data;
}

// 缓存二维码数据
static int airui_qrcode_cache_data(lv_obj_t *qrcode, const void *data, size_t len)
{
    airui_qrcode_data_t *qrcode_data = airui_qrcode_get_data(qrcode);
    char *new_data = NULL;

    if (qrcode_data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (data != NULL && len > 0) {
        new_data = (char *)luat_heap_malloc(len + 1);
        if (new_data == NULL) {
            return AIRUI_ERR_NO_MEM;
        }
        memcpy(new_data, data, len);
        new_data[len] = '\0';
    }

    if (qrcode_data->data != NULL) {
        luat_heap_free(qrcode_data->data);
    }

    qrcode_data->data = new_data;
    qrcode_data->len = (new_data != NULL) ? len : 0;
    return AIRUI_OK;
}

// 刷新缓存数据
static int airui_qrcode_refresh_cached(lv_obj_t *qrcode)
{
    airui_qrcode_data_t *qrcode_data = airui_qrcode_get_data(qrcode);
    if (qrcode_data == NULL || qrcode_data->data == NULL || qrcode_data->len == 0) {
        return AIRUI_OK;
    }

    lv_result_t ret = lv_qrcode_update(qrcode, qrcode_data->data, (uint32_t)qrcode_data->len);
    return ret == LV_RESULT_OK ? AIRUI_OK : AIRUI_ERR_INVALID_PARAM;
}

// 释放二维码数据
void airui_qrcode_release_data(airui_component_meta_t *meta)
{
    if (meta == NULL || meta->user_data == NULL) {
        return;
    }

    airui_qrcode_data_t *qrcode_data = (airui_qrcode_data_t *)meta->user_data;
    if (qrcode_data->data != NULL) {
        luat_heap_free(qrcode_data->data);
    }
    luat_heap_free(qrcode_data);
    meta->user_data = NULL;
}

// 设置二维码数据
int airui_qrcode_set_data(lv_obj_t *qrcode, const void *data, size_t len)
{
    if (qrcode == NULL || data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    int cache_ret = airui_qrcode_cache_data(qrcode, data, len);
    if (cache_ret != AIRUI_OK) {
        return cache_ret;
    }

    lv_result_t update_ret = lv_qrcode_update(qrcode, data, (uint32_t)len);
    if (update_ret != LV_RESULT_OK) {
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
    return airui_qrcode_refresh_cached(qrcode);
}

// 设置二维码前景/背景色
int airui_qrcode_set_colors(lv_obj_t *qrcode, lv_color_t dark_color, lv_color_t light_color)
{
    if (qrcode == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_qrcode_set_dark_color(qrcode, dark_color);
    lv_qrcode_set_light_color(qrcode, light_color);
    return airui_qrcode_refresh_cached(qrcode);
}

// 设置静区开关
int airui_qrcode_set_quiet_zone(lv_obj_t *qrcode, bool enable)
{
    if (qrcode == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_qrcode_set_quiet_zone(qrcode, enable);
    return airui_qrcode_refresh_cached(qrcode);
}
