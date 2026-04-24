/*
@module  airui.qrcode
@summary AIRUI Qrcode 组件 Lua 绑定
@version 0.1.0
@date    2026.03.05
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define LUAT_LOG_TAG "airui.qrcode"
#include "luat_log.h"

#define AIRUI_QRCODE_MT "airui.qrcode"

/**
 * 创建 Qrcode 组件
 * @api airui.qrcode(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.size 二维码尺寸（正方形边长），默认 160
 * @string config.data 二维码内容，可选
 * @int config.dark_color 深色模块颜色，默认 0x000000
 * @int config.light_color 浅色背景颜色，默认 0xFFFFFF
 * @boolean config.quiet_zone 是否启用静区，默认 true
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Qrcode 对象
 */
static int l_airui_qrcode(lua_State *L)
{
    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);

    if (ctx == NULL) {
        luaL_error(L, "airui not initialized, call airui.init() first");
        return 0;
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lv_obj_t *qrcode = airui_qrcode_create_from_config(L, 1);
    if (qrcode == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, qrcode, AIRUI_QRCODE_MT);
    return 1;
}

/**
 * Qrcode:set_data(data)
 * @api qrcode:set_data(data)
 * @string data 二维码内容
 * @return bool 设置成功返回 true
 */
static int l_qrcode_set_data(lua_State *L)
{
    lv_obj_t *qrcode = airui_check_component(L, 1, AIRUI_QRCODE_MT);
    size_t len = 0;
    const char *data = luaL_checklstring(L, 2, &len);
    int ret = airui_qrcode_set_data(qrcode, data, len);
    lua_pushboolean(L, ret == AIRUI_OK);
    return 1;
}

/**
 * Qrcode:set_size(size)
 * @api qrcode:set_size(size)
 * @int size 二维码尺寸
 * @return nil
 */
static int l_qrcode_set_size(lua_State *L)
{
    lv_obj_t *qrcode = airui_check_component(L, 1, AIRUI_QRCODE_MT);
    int size = luaL_checkinteger(L, 2);
    airui_qrcode_set_size(qrcode, size);
    return 0;
}

/**
 * Qrcode:set_colors(dark_color, light_color)
 * @api qrcode:set_colors(dark_color, light_color)
 * @int dark_color 深色模块颜色（RGB Hex）
 * @int light_color 浅色背景颜色（RGB Hex）
 * @return nil
 */
static int l_qrcode_set_colors(lua_State *L)
{
    lv_obj_t *qrcode = airui_check_component(L, 1, AIRUI_QRCODE_MT);
    uint32_t dark_color = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t light_color = (uint32_t)luaL_checkinteger(L, 3);
    airui_qrcode_set_colors(qrcode, lv_color_hex(dark_color), lv_color_hex(light_color));
    return 0;
}

/**
 * Qrcode:set_quiet_zone(enable)
 * @api qrcode:set_quiet_zone(enable)
 * @boolean enable 是否启用静区
 * @return nil
 */
static int l_qrcode_set_quiet_zone(lua_State *L)
{
    lv_obj_t *qrcode = airui_check_component(L, 1, AIRUI_QRCODE_MT);
    bool enable = lua_toboolean(L, 2) != 0;
    airui_qrcode_set_quiet_zone(qrcode, enable);
    return 0;
}

/**
 * Qrcode:destroy（手动销毁）
 */
static int l_qrcode_destroy(lua_State *L)
{
    return airui_component_destroy_userdata(L, 1, AIRUI_QRCODE_MT);
}

void airui_register_qrcode_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_QRCODE_MT);

    static const luaL_Reg methods[] = {
        {"set_data", l_qrcode_set_data},
        {"set_size", l_qrcode_set_size},
        {"set_colors", l_qrcode_set_colors},
        {"set_quiet_zone", l_qrcode_set_quiet_zone},
        {"destroy", l_qrcode_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");

    lua_pop(L, 1);
}

int airui_qrcode_create(lua_State *L)
{
    return l_airui_qrcode(L);
}
