/*
@module  airui.chart
@summary AIRUI Chart 曲线图组件 Lua 绑定
@version 0.1.0
@date    2026.02.28
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"
#include <string.h>

#define AIRUI_CHART_MT "airui.chart"

static lv_chart_update_mode_t airui_chart_parse_mode(lua_State *L, int idx)
{
    if (lua_type(L, idx) == LUA_TNUMBER) {
        int mode = (int)lua_tointeger(L, idx);
        if (mode == (int)LV_CHART_UPDATE_MODE_CIRCULAR) {
            return LV_CHART_UPDATE_MODE_CIRCULAR;
        }
        return LV_CHART_UPDATE_MODE_SHIFT;
    }

    const char *mode = luaL_optstring(L, idx, "shift");
    if (strcmp(mode, "circular") == 0) {
        return LV_CHART_UPDATE_MODE_CIRCULAR;
    }
    return LV_CHART_UPDATE_MODE_SHIFT;
}

/**
 * 创建 Chart 组件
 * @api airui.chart(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 240
 * @int config.h 高度，默认 120
 * @int config.y_min Y 轴最小值，默认 0
 * @int config.y_max Y 轴最大值，默认 100
 * @int config.point_count 点数量，默认 120（适合 10Hz）
 * @string|int config.update_mode 更新模式，"shift" 或 "circular"
 * @int config.line_color 曲线颜色（Hex）
 * @int config.line_width 曲线宽度
 * @int config.point_radius 点半径，默认 0
 * @function config.on_point 点击图表点时回调（参数：chart）
 * @userdata config.parent 父对象，默认当前屏幕
 * @return userdata Chart 对象
 */
static int l_airui_chart(lua_State *L)
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

    lv_obj_t *chart = airui_chart_create_from_config(L, 1);
    if (chart == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, chart, AIRUI_CHART_MT);
    return 1;
}

/**
 * Chart:set_values(values)
 * @api chart:set_values(values)
 * @table values 数值数组
 * @return nil
 */
static int l_chart_set_values(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    luaL_checktype(L, 2, LUA_TTABLE);

    size_t len = lua_rawlen(L, 2);
    if (len == 0) {
        airui_chart_clear(chart, 0);
        return 0;
    }

    int32_t *values = (int32_t *)luat_heap_malloc(sizeof(int32_t) * len);
    if (values == NULL) {
        return luaL_error(L, "chart:set_values out of memory");
    }

    for (size_t i = 0; i < len; i++) {
        lua_rawgeti(L, 2, (lua_Integer)(i + 1));
        values[i] = lua_type(L, -1) == LUA_TNUMBER ? (int32_t)lua_tointeger(L, -1) : 0;
        lua_pop(L, 1);
    }

    airui_chart_set_values(chart, values, (uint32_t)len);
    luat_heap_free(values);
    return 0;
}

/**
 * Chart:push(value)
 * @api chart:push(value)
 * @int value 新值
 * @return nil
 */
static int l_chart_push(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int32_t value = (int32_t)luaL_checkinteger(L, 2);
    airui_chart_push_value(chart, value);
    return 0;
}

/**
 * Chart:clear(value)
 * @api chart:clear(value)
 * @int value 可选，默认 0
 * @return nil
 */
static int l_chart_clear(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int32_t value = (int32_t)luaL_optinteger(L, 2, 0);
    airui_chart_clear(chart, value);
    return 0;
}

/**
 * Chart:set_range(min, max)
 * @api chart:set_range(min, max)
 * @int min 最小值
 * @int max 最大值
 * @return nil
 */
static int l_chart_set_range(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int32_t min = (int32_t)luaL_checkinteger(L, 2);
    int32_t max = (int32_t)luaL_checkinteger(L, 3);
    airui_chart_set_range(chart, min, max);
    return 0;
}

/**
 * Chart:set_point_count(count)
 * @api chart:set_point_count(count)
 * @int count 点数量
 * @return nil
 */
static int l_chart_set_point_count(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    uint32_t count = (uint32_t)luaL_checkinteger(L, 2);
    airui_chart_set_point_count(chart, count);
    return 0;
}

/**
 * Chart:set_update_mode(mode)
 * @api chart:set_update_mode(mode)
 * @string|int mode "shift" 或 "circular"
 * @return nil
 */
static int l_chart_set_update_mode(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    lv_chart_update_mode_t mode = airui_chart_parse_mode(L, 2);
    airui_chart_set_update_mode(chart, mode);
    return 0;
}

/**
 * Chart:set_line_color(color)
 * @api chart:set_line_color(color)
 * @int color 16 进制颜色整数
 * @return nil
 */
static int l_chart_set_line_color(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    lv_color_t color = lv_color_hex((uint32_t)luaL_checkinteger(L, 2));
    airui_chart_set_line_color(chart, color);
    return 0;
}

/**
 * Chart:get_pressed_point()
 * @api chart:get_pressed_point()
 * @return int 点索引，未命中返回 -1
 */
static int l_chart_get_pressed_point(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    lua_pushinteger(L, airui_chart_get_pressed_point(chart));
    return 1;
}

/**
 * Chart:set_on_point(cb)
 * @api chart:set_on_point(cb)
 * @function cb 回调（参数：chart）
 * @return nil
 */
static int l_chart_set_on_point(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    airui_chart_set_on_point(chart, ref);
    return 0;
}

/**
 * Chart:destroy()
 * @api chart:destroy()
 * @return nil
 */
static int l_chart_destroy(lua_State *L)
{
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_CHART_MT);
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

void airui_register_chart_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_CHART_MT);
    static const luaL_Reg methods[] = {
        {"set_values", l_chart_set_values},
        {"push", l_chart_push},
        {"clear", l_chart_clear},
        {"set_range", l_chart_set_range},
        {"set_point_count", l_chart_set_point_count},
        {"set_update_mode", l_chart_set_update_mode},
        {"set_line_color", l_chart_set_line_color},
        {"get_pressed_point", l_chart_get_pressed_point},
        {"set_on_point", l_chart_set_on_point},
        {"destroy", l_chart_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_chart_create(lua_State *L)
{
    return l_airui_chart(L);
}
