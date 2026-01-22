/*
@module  easylvgl.bar
@summary EasyLVGL Bar/进度条组件 Lua 绑定
@version 0.1.0
@date    2026.01.16
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"

#define EASYLVGL_BAR_MT "easylvgl.bar"

/**
 * 创建 Bar 组件
 * @api easylvgl.bar(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 200
 * @int config.h 高度，默认 20
 * @int config.min 最小值，默认 0
 * @int config.max 最大值，默认 100
 * @int config.value 当前值，默认 min
 * @int config.radius 圆角，默认 4
 * @int config.border_width 边框宽度
 * @int config.bg_color 背景颜色（Hex）
 * @int config.indicator_color 指示器颜色（Hex）
 * @int config.border_color 边框颜色（Hex）
 * @userdata config.parent 父对象，默认当前屏幕
 * @return userdata Bar 对象
 */
static int l_easylvgl_bar(lua_State *L) {
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);

    if (ctx == NULL) {
        luaL_error(L, "easylvgl not initialized, call easylvgl.init() first");
        return 0;
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lv_obj_t *bar = easylvgl_bar_create_from_config(L, 1);
    if (bar == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, bar, EASYLVGL_BAR_MT);
    return 1;
}

/**
 * Bar:set_value(value, anim)
 * @api bar:set_value(value, anim)
 * @int value 目标值
 * @boolean anim 是否动画
 * @return nil
 */
static int l_bar_set_value(lua_State *L) {
    lv_obj_t *bar = easylvgl_check_component(L, 1, EASYLVGL_BAR_MT);
    int value = (int)luaL_checkinteger(L, 2);
    bool anim = lua_toboolean(L, 3);
    easylvgl_bar_set_value(bar, value, anim);
    return 0;
}

/**
 * Bar:set_range(min, max)
 * @api bar:set_range(min, max)
 * @int min 最小值
 * @int max 最大值
 * @return nil
 */
static int l_bar_set_range(lua_State *L) {
    lv_obj_t *bar = easylvgl_check_component(L, 1, EASYLVGL_BAR_MT);
    lv_coord_t min = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t max = (lv_coord_t)luaL_checkinteger(L, 3);
    easylvgl_bar_set_range(bar, min, max);
    return 0;
}

/**
 * Bar:set_indicator_color(color)
 * @api bar:set_indicator_color(color)
 * @int color 16 进制值
 * @return nil
 */
static int l_bar_set_indicator_color(lua_State *L) {
    lv_obj_t *bar = easylvgl_check_component(L, 1, EASYLVGL_BAR_MT);
    lv_color_t color = lv_color_hex((uint32_t)luaL_checkinteger(L, 2));
    easylvgl_bar_set_indicator_color(bar, color);
    return 0;
}

/**
 * Bar:set_bg_color(color)
 * @api bar:set_bg_color(color)
 * @int color 16 进制值
 * @return nil
 */
static int l_bar_set_bg_color(lua_State *L) {
    lv_obj_t *bar = easylvgl_check_component(L, 1, EASYLVGL_BAR_MT);
    lv_color_t color = lv_color_hex((uint32_t)luaL_checkinteger(L, 2));
    easylvgl_bar_set_bg_color(bar, color);
    return 0;
}

/**
 * Bar:destroy()
 * @api bar:destroy()
 * @return nil
 */
static int l_bar_destroy(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_BAR_MT);
    if (ud != NULL && ud->obj != NULL) {
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
        if (meta != NULL) {
            easylvgl_component_meta_free(meta);
        }
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

/**
 * Bar:get_value()
 * @api bar:get_value()
 * @return int 当前值
 */
static int l_bar_get_value(lua_State *L) {
    lv_obj_t *bar = easylvgl_check_component(L, 1, EASYLVGL_BAR_MT);
    int value = easylvgl_bar_get_value(bar);
    lua_pushinteger(L, value);
    return 1;
}

void easylvgl_register_bar_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_BAR_MT);
    static const luaL_Reg methods[] = {
        {"set_value", l_bar_set_value},
        {"get_value", l_bar_get_value},
        {"set_range", l_bar_set_range},
        {"set_indicator_color", l_bar_set_indicator_color},
        {"set_bg_color", l_bar_set_bg_color},
        {"destroy", l_bar_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int easylvgl_bar_create(lua_State *L) {
    return l_easylvgl_bar(L);
}

