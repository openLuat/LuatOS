/*
@module  airui.switch
@summary AIRUI Switch 组件
@version 0.2.0
@date    2025.12.12
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define LUAT_LOG_TAG "airui.switch"
#include "luat_log.h"

#define AIRUI_SWITCH_MT "airui.switch"

/**
 * 创建 Switch 组件
 * @api airui.switch(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 70
 * @int config.h 高度，默认 40
 * @boolean config.checked 初始状态，默认 false
 * @string config.style 预设样式，如 "danger"/"success"
 * @function config.on_change 状态变更回调
 * @userdata config.parent 父对象，可选
 * @return userdata Switch 对象，失败返回 nil
 */
static int l_airui_switch(lua_State *L)
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
    lv_obj_t *sw = airui_switch_create_from_config(L, 1);
    if (sw == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, sw, AIRUI_SWITCH_MT);
    return 1;
}

/**
 * Switch:set_state(state)
 * @api switch:set_state(state)
 * @boolean state 勾选状态
 * @return nil
 */
static int l_switch_set_state(lua_State *L)
{
    lv_obj_t *sw = airui_check_component(L, 1, AIRUI_SWITCH_MT);
    bool checked = lua_toboolean(L, 2);
    airui_switch_set_state(sw, checked);
    return 0;
}

/**
 * Switch:get_state()
 * @api switch:get_state()
 * @return boolean 当前状态
 */
static int l_switch_get_state(lua_State *L)
{
    lv_obj_t *sw = airui_check_component(L, 1, AIRUI_SWITCH_MT);
    bool checked = airui_switch_get_state(sw);
    lua_pushboolean(L, checked);
    return 1;
}

/**
 * Switch:set_on_change(callback)
 * @api switch:set_on_change(callback)
 * @function callback 状态变化回调
 * @return nil
 */
static int l_switch_set_on_change(lua_State *L)
{
    lv_obj_t *sw = airui_check_component(L, 1, AIRUI_SWITCH_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    airui_switch_set_on_change(sw, ref);
    return 0;
}

/**
 * Switch:destroy（手动销毁）
 */
static int l_switch_destroy(lua_State *L)
{
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_SWITCH_MT);
    if (ud != NULL && ud->obj != NULL) {
        airui_component_meta_t *meta = airui_component_meta_get(ud->obj);
        if (meta != NULL) {
            airui_component_meta_free(meta);
        }
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

/**
 * 注册 Switch 元表
 * @param L Lua 状态
 */
void airui_register_switch_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_SWITCH_MT);

    static const luaL_Reg methods[] = {
        {"set_state", l_switch_set_state},
        {"get_state", l_switch_get_state},
        {"set_on_change", l_switch_set_on_change},
        {"destroy", l_switch_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Switch 创建函数（供主模块注册）
 */
int airui_switch_create(lua_State *L)
{
    return l_airui_switch(L);
}

