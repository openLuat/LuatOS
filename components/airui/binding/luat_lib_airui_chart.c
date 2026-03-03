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
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#define AIRUI_CHART_MT "airui.chart"

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

static int32_t *airui_chart_values_from_table(lua_State *L, int table_idx, size_t *out_len)
{
    size_t len = lua_rawlen(L, table_idx);
    if (out_len != NULL) {
        *out_len = len;
    }
    if (len == 0) {
        return NULL;
    }

    int32_t *values = (int32_t *)luat_heap_malloc(sizeof(int32_t) * len);
    if (values == NULL) {
        return NULL;
    }

    for (size_t i = 0; i < len; i++) {
        lua_rawgeti(L, table_idx, (lua_Integer)(i + 1));
        values[i] = lua_type(L, -1) == LUA_TNUMBER ? (int32_t)lua_tointeger(L, -1) : 0;
        lua_pop(L, 1);
    }
    return values;
}

/**
 * Chart:set_values(series_id, values)
 * @api chart:set_values(series_id, values)
 * @int series_id 曲线编号（从 1 开始）
 * @table values 数值数组
 * @return nil
 */
static int l_chart_set_values(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int id = (int)luaL_checkinteger(L, 2);
    luaL_checktype(L, 3, LUA_TTABLE);
    if (id < 1) {
        return luaL_error(L, "chart:set_values invalid series id");
    }

    size_t len = 0;
    int32_t *values = airui_chart_values_from_table(L, 3, &len);
    if (len == 0) {
        int32_t zero = 0;
        airui_chart_set_series_values(chart, (uint32_t)(id - 1), &zero, 1);
        return 0;
    }
    if (values == NULL) {
        return luaL_error(L, "chart:set_values out of memory");
    }

    airui_chart_set_series_values(chart, (uint32_t)(id - 1), values, (uint32_t)len);
    luat_heap_free(values);
    return 0;
}

/**
 * Chart:push(series_id, value)
 * @api chart:push(series_id, value)
 * @int series_id 曲线编号（从 1 开始）
 * @int value 新值
 * @return nil
 */
static int l_chart_push(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int id = (int)luaL_checkinteger(L, 2);
    int32_t value = (int32_t)luaL_checkinteger(L, 3);
    if (id < 1) {
        return luaL_error(L, "chart:push invalid series id");
    }
    airui_chart_push_series_value(chart, (uint32_t)(id - 1), value);
    return 0;
}

static int l_chart_add_series(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    luaL_checktype(L, 2, LUA_TTABLE);

    uint32_t color_hex = 0x00b4ff;
    const char *name = NULL;

    lua_getfield(L, 2, "color");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        color_hex = (uint32_t)lua_tointeger(L, -1);
    }
    lua_pop(L, 1);

    lua_getfield(L, 2, "name");
    if (lua_type(L, -1) == LUA_TSTRING) {
        name = lua_tostring(L, -1);
    }
    lua_pop(L, 1);

    int id = airui_chart_add_series(chart, lv_color_hex(color_hex), name);
    if (id < 1) {
        return luaL_error(L, "chart:add_series failed");
    }
    lua_pushinteger(L, id);
    return 1;
}

static int l_chart_remove_series(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int ret = AIRUI_ERR_INVALID_PARAM;

    if (lua_isnoneornil(L, 2)) {
        ret = airui_chart_remove_last_series(chart);
    } else {
        int id = (int)luaL_checkinteger(L, 2);
        if (id < 2) {
            return luaL_error(L, "chart:remove_series id must be >= 2");
        }
        ret = airui_chart_remove_series(chart, (uint32_t)(id - 1));
    }

    if (ret != AIRUI_OK) {
        return luaL_error(L, "chart:remove_series failed");
    }
    return 0;
}

static int l_chart_set_series_name(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int id = (int)luaL_checkinteger(L, 2);
    const char *name = luaL_checkstring(L, 3);
    if (id < 1) {
        return luaL_error(L, "chart:set_series_name invalid series id");
    }
    airui_chart_set_series_name(chart, (uint32_t)(id - 1), name);
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
 * Chart:set_line_color(series_id, color)
 * @api chart:set_line_color(series_id, color)
 * @int series_id 曲线编号（从 1 开始）
 * @int color 16 进制颜色整数
 * @return nil
 */
static int l_chart_set_line_color(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int id = (int)luaL_checkinteger(L, 2);
    lv_color_t color = lv_color_hex((uint32_t)luaL_checkinteger(L, 3));
    if (id < 1) {
        return luaL_error(L, "chart:set_line_color invalid series id");
    }
    airui_chart_set_series_color(chart, (uint32_t)(id - 1), color);
    return 0;
}

static int l_chart_set_axis(lua_State *L, bool is_x)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    luaL_checktype(L, 2, LUA_TTABLE);

    bool enable = true;
    int32_t min = 0;
    int32_t max = is_x ? 100 : 100;
    uint32_t ticks = 6;
    const char *unit = NULL;

    lua_getfield(L, 2, "enable");
    if (lua_type(L, -1) == LUA_TBOOLEAN) {
        enable = lua_toboolean(L, -1);
    }
    lua_pop(L, 1);

    lua_getfield(L, 2, "min");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        min = (int32_t)lua_tointeger(L, -1);
    }
    lua_pop(L, 1);

    lua_getfield(L, 2, "max");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        max = (int32_t)lua_tointeger(L, -1);
    }
    lua_pop(L, 1);

    lua_getfield(L, 2, "ticks");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        ticks = (uint32_t)lua_tointeger(L, -1);
    }
    lua_pop(L, 1);

    lua_getfield(L, 2, "unit");
    if (lua_type(L, -1) == LUA_TSTRING) {
        unit = lua_tostring(L, -1);
    }
    lua_pop(L, 1);

    airui_chart_set_axis_config(chart, is_x, enable, min, max, ticks, unit);
    return 0;
}

static int l_chart_set_x_axis(lua_State *L)
{
    return l_chart_set_axis(L, true);
}

static int l_chart_set_y_axis(lua_State *L)
{
    return l_chart_set_axis(L, false);
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
        {"add_series", l_chart_add_series},
        {"remove_series", l_chart_remove_series},
        {"set_series_name", l_chart_set_series_name},
        {"clear", l_chart_clear},
        {"set_point_count", l_chart_set_point_count},
        {"set_update_mode", l_chart_set_update_mode},
        {"set_line_color", l_chart_set_line_color},
        {"set_x_axis", l_chart_set_x_axis},
        {"set_y_axis", l_chart_set_y_axis},
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
