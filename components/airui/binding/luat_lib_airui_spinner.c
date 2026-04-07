/*
@module  airui.spinner
@summary AIRUI Spinner 组件 Lua 绑定
@version 0.1.0
@date    2026.04.07
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define AIRUI_SPINNER_MT "airui.spinner"

/**
 * 创建 Spinner 组件
 * @api airui.spinner(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 40
 * @int config.h 高度，默认 40
 * @int config.duration 动画周期，默认 1000 毫秒
 * @int config.arc_angle 指示弧长，默认 200 度
 * @table config.style 样式表，可选
 * @int config.style.color 指示弧颜色（0xRRGGBB）
 * @int config.style.track_color 轨道弧颜色（0xRRGGBB）
 * @int config.style.line_width 弧线宽度
 * @int config.style.opa 不透明度（0-255）
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Spinner 对象，失败返回 nil
 */
static int l_airui_spinner(lua_State *L)
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
    lv_obj_t *spinner = airui_spinner_create_from_config(L, 1);
    if (spinner == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, spinner, AIRUI_SPINNER_MT);
    return 1;
}

/**
 * Spinner:set_style(style)
 * @api spinner:set_style(style)
 * @table style 样式表，仅覆盖传入字段
 * @return nil
 */
static int l_spinner_set_style(lua_State *L)
{
    lv_obj_t *spinner = airui_check_component(L, 1, AIRUI_SPINNER_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    airui_spinner_set_style(spinner, L, 2);
    return 0;
}

/**
 * Spinner:set_anim_params(duration, arc_angle)
 * @api spinner:set_anim_params(duration, arc_angle)
 * @int duration 动画周期，单位毫秒
 * @int arc_angle 指示弧长，单位度
 * @return nil
 */
static int l_spinner_set_anim_params(lua_State *L)
{
    lv_obj_t *spinner = airui_check_component(L, 1, AIRUI_SPINNER_MT);
    uint32_t duration = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t arc_angle = (uint32_t)luaL_checkinteger(L, 3);
    airui_spinner_set_anim_params(spinner, duration, arc_angle);
    return 0;
}

/**
 * Spinner:destroy（手动销毁）
 */
static int l_spinner_destroy(lua_State *L)
{
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_SPINNER_MT);
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

void airui_register_spinner_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_SPINNER_MT);
    static const luaL_Reg methods[] = {
        {"set_style", l_spinner_set_style},
        {"set_anim_params", l_spinner_set_anim_params},
        {"destroy", l_spinner_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_spinner_create(lua_State *L)
{
    return l_airui_spinner(L);
}
