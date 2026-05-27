/*
@module  airui.checkbox
@summary AIRUI Checkbox 组件
@version 0.1.0
@date    2026.05.20
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define LUAT_LOG_TAG "airui.checkbox"
#include "luat_log.h"

#define AIRUI_CHECKBOX_MT "airui.checkbox"

/**
 * 创建 Checkbox 组件
 * @api airui.checkbox(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 24
 * @int config.h 高度，默认 24
 * @boolean config.checked 初始勾选状态，默认 false
 * @string config.text 标签文本，可选
 * @table config.style 样式表，可选
 * @int config.style.text_color 默认态文字颜色（0xRRGGBB）
 * @int config.style.checked_text_color 选中态文字颜色（0xRRGGBB）
 * @int config.style.text_font_size 文字字号，单位像素
 * @function config.on_change 状态变更回调
 * @userdata config.parent 父对象，可选
 * @return userdata Checkbox 对象，失败返回 nil
 */
static int l_airui_checkbox(lua_State *L)
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
    lv_obj_t *cb = airui_checkbox_create_from_config(L, 1);
    if (cb == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, cb, AIRUI_CHECKBOX_MT);
    return 1;
}

/**
 * Checkbox:set_checked(checked)
 * @api checkbox:set_checked(checked)
 * @boolean checked 勾选状态
 * @return nil
 */
static int l_checkbox_set_checked(lua_State *L)
{
    lv_obj_t *cb = airui_check_component(L, 1, AIRUI_CHECKBOX_MT);
    bool checked = lua_toboolean(L, 2);
    airui_checkbox_set_checked(cb, checked);
    return 0;
}

/**
 * Checkbox:get_checked()
 * @api checkbox:get_checked()
 * @return boolean 当前勾选状态
 */
static int l_checkbox_get_checked(lua_State *L)
{
    lv_obj_t *cb = airui_check_component(L, 1, AIRUI_CHECKBOX_MT);
    bool checked = airui_checkbox_get_checked(cb);
    lua_pushboolean(L, checked);
    return 1;
}

/**
 * Checkbox:set_text(text)
 * @api checkbox:set_text(text)
 * @string text 标签文本
 * @return nil
 */
static int l_checkbox_set_text(lua_State *L)
{
    lv_obj_t *cb = airui_check_component(L, 1, AIRUI_CHECKBOX_MT);
    const char *text = luaL_checkstring(L, 2);
    airui_checkbox_set_text(cb, text);
    return 0;
}

/**
 * Checkbox:get_text()
 * @api checkbox:get_text()
 * @return string 当前标签文本
 */
static int l_checkbox_get_text(lua_State *L)
{
    lv_obj_t *cb = airui_check_component(L, 1, AIRUI_CHECKBOX_MT);
    const char *text = airui_checkbox_get_text(cb);
    lua_pushstring(L, text ? text : "");
    return 1;
}

/**
 * Checkbox:set_style(style)
 * @api checkbox:set_style(style)
 * @table style 样式表，仅覆盖传入字段
 * @return nil
 */
static int l_checkbox_set_style(lua_State *L)
{
    lv_obj_t *cb = airui_check_component(L, 1, AIRUI_CHECKBOX_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    airui_checkbox_set_style(cb, L, 2);
    return 0;
}

/**
 * Checkbox:set_on_change(callback)
 * @api checkbox:set_on_change(callback)
 * @function callback 状态变化回调
 * @return nil
 */
static int l_checkbox_set_on_change(lua_State *L)
{
    lv_obj_t *cb = airui_check_component(L, 1, AIRUI_CHECKBOX_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    airui_checkbox_set_on_change(cb, ref);
    return 0;
}

/**
 * Checkbox:destroy（手动销毁）
 */
static int l_checkbox_destroy(lua_State *L)
{
    return airui_component_destroy_userdata(L, 1, AIRUI_CHECKBOX_MT);
}

/**
 * 注册 Checkbox 元表
 * @param L Lua 状态
 */
void airui_register_checkbox_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_CHECKBOX_MT);
    airui_component_set_metatable_gc(L);

    static const luaL_Reg methods[] = {
        {"set_checked", l_checkbox_set_checked},
        {"get_checked", l_checkbox_get_checked},
        {"set_text", l_checkbox_set_text},
        {"get_text", l_checkbox_get_text},
        {"set_style", l_checkbox_set_style},
        {"set_on_change", l_checkbox_set_on_change},
        {"destroy", l_checkbox_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Checkbox 创建函数（供主模块注册）
 */
int airui_checkbox_create(lua_State *L)
{
    return l_airui_checkbox(L);
}
