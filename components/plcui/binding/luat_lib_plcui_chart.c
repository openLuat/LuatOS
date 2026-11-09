/*
@module plcui.chart
@summary XML 折线图和柱状图
@version 0.1.0
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include <stdlib.h>
#include <string.h>

static plcui_chart_series_t *check_series(lua_State *L, plcui_widget_t *widget)
{
    return luat_plcui_chart_series(widget, luaL_checkstring(L, 2));
}

/**
 * 覆盖一个系列的数据，按从左到右的顺序排列。
 * @api chart:set_values(series_id, values)
 * @string series_id XML 中声明的系列 ID
 * @table values 连续数字数组，长度等于 XML 的 point-count
 * @return bool|nil 成功返回 true，失败返回 nil
 * @return table|nil 失败时返回错误表
 * @note 数值范围 -1000～1000，内部精度为两位小数；完整校验后统一更新。
 * @note 超出坐标轴范围的值按轴边界绘制，get_values 保留原值。
 */
static int chart_set_values(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_CHART, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    plcui_chart_series_t *series = check_series(L, widget);
    if (!series) return luat_plcui_binding_error(L, "E_RESOURCE", "Chart series does not exist");
    luaL_checktype(L, 3, LUA_TTABLE);
    unsigned count = widget->chart->points;
    if (lua_rawlen(L, 3) != count) return luat_plcui_binding_error(L, "E_SCHEMA", "Values length must equal point-count");
    /* A bounded temporary array makes rejection atomic for the visible series. */
    int32_t *values = malloc(count * sizeof(*values));
    if (!values) return luat_plcui_binding_error(L, "E_MEMORY", "Cannot allocate chart update buffer");
    for (unsigned i = 0; i < count; ++i) {
        lua_rawgeti(L, 3, (lua_Integer)i + 1);
        bool valid = lua_type(L, -1) == LUA_TNUMBER && luat_plcui_chart_number(lua_tonumber(L, -1), &values[i]);
        lua_pop(L, 1);
        if (!valid) {
            free(values);
            return luat_plcui_binding_error(L, "E_SCHEMA", "Chart values must be finite numbers between -1000 and 1000");
        }
    }
    memcpy(series->values, values, count * sizeof(*values));
    free(values);
    series->start = 0;
    luat_plcui_chart_sync_series(widget, series);
    lv_chart_refresh(widget->obj);
    return luat_plcui_binding_success(L);
}

/**
 * 追加一个数据点，最旧的数据从左侧移出。
 * @api chart:add_point(series_id, value)
 * @string series_id XML 中声明的系列 ID
 * @number value 数值，范围 -1000～1000，精度两位小数
 * @return bool|nil 成功返回 true，失败返回 nil
 * @return table|nil 失败时返回错误表
 */
static int chart_add_point(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_CHART, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    plcui_chart_series_t *series = check_series(L, widget);
    if (!series) return luat_plcui_binding_error(L, "E_RESOURCE", "Chart series does not exist");
    int32_t value;
    if (!luat_plcui_chart_number(luaL_checknumber(L, 3), &value)) return luat_plcui_binding_error(L, "E_SCHEMA", "Chart value must be between -1000 and 1000");
    series->values[series->start] = value;
    series->start = (series->start + 1U) % widget->chart->points;
    lv_chart_set_next_value(widget->obj, series->native, luat_plcui_chart_display_value(widget, value));
    return luat_plcui_binding_success(L);
}

/**
 * 读取系列当前从左到右的全部数据。
 * @api chart:get_values(series_id)
 * @string series_id XML 中声明的系列 ID
 * @return table|nil 数字数组，失败返回 nil
 * @return table|nil 失败时返回错误表
 */
static int chart_get_values(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_CHART, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    plcui_chart_series_t *series = check_series(L, widget);
    if (!series) return luat_plcui_binding_error(L, "E_RESOURCE", "Chart series does not exist");
    unsigned count = widget->chart->points;
    lua_createtable(L, (int)count, 0);
    for (unsigned i = 0; i < count; ++i) {
        lua_pushnumber(L, (lua_Number)series->values[(series->start + i) % count] / PLCUI_CHART_SCALE);
        lua_rawseti(L, -2, (lua_Integer)i + 1);
    }
    return 1;
}

/**
 * 设置主 Y 轴范围。
 * @api chart:set_range(minimum, maximum)
 * @number minimum 下限，范围 -1000～1000
 * @number maximum 上限，范围 -1000～1000，须大于下限
 * @return bool|nil 成功返回 true，失败返回 nil
 * @return table|nil 失败时返回错误表
 * @note 数值保留两位小数，刻度文字由外围 label 或背景图提供。
 */
static int chart_set_range(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_CHART, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    int32_t minimum, maximum;
    if (!luat_plcui_chart_number(luaL_checknumber(L, 2), &minimum)
        || !luat_plcui_chart_number(luaL_checknumber(L, 3), &maximum) || minimum >= maximum) {
        return luat_plcui_binding_error(L, "E_SCHEMA", "Chart range must satisfy -1000 <= min < max <= 1000");
    }
    widget->chart->minimum = minimum;
    widget->chart->maximum = maximum;
    lv_chart_set_axis_range(widget->obj, LV_CHART_AXIS_PRIMARY_Y, minimum, maximum);
    for (unsigned i = 0; i < widget->chart->count; ++i) {
        luat_plcui_chart_sync_series(widget, &widget->chart->series[i]);
    }
    lv_chart_refresh(widget->obj);
    return luat_plcui_binding_success(L);
}

/**
 * 显示或隐藏一条曲线。
 * @api chart:set_series_hidden(series_id, hidden)
 * @string series_id XML 中声明的系列 ID
 * @bool hidden true 隐藏，false 显示
 * @return bool|nil 成功返回 true，失败返回 nil
 * @return table|nil 失败时返回错误表
 */
static int chart_set_series_hidden(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_CHART, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    plcui_chart_series_t *series = check_series(L, widget);
    if (!series) return luat_plcui_binding_error(L, "E_RESOURCE", "Chart series does not exist");
    luaL_checktype(L, 3, LUA_TBOOLEAN);
    series->hidden = lua_toboolean(L, 3) != 0;
    lv_chart_hide_series(widget->obj, series->native, series->hidden);
    return luat_plcui_binding_success(L);
}

void luat_plcui_register_chart_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_values", chart_set_values},
        {"get_values", chart_get_values},
        {"add_point", chart_add_point},
        {"set_range", chart_set_range},
        {"set_series_hidden", chart_set_series_hidden},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_CHART_MT);
    luaL_setfuncs(L, methods, 0);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
