/*
@module plcui.chart
@summary XML 折线图与柱状图的系列数据、坐标范围和显隐操作
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include <stdlib.h>
#include <string.h>

/**
 * 根据 Lua 方法的第二个参数查找当前 chart 中的系列。
 * @param L Lua 状态机；栈索引 2 为系列 ID 字符串。
 * @param widget 已通过类型和生命周期检查的 chart 组件。
 * @return 找到时返回系列描述指针，未知系列返回 NULL。
 * @note 参数类型检查沿用 luaL_checkstring；调用方负责将未知系列转换为 Lua 错误返回值。
 */
static plcui_chart_series_t *check_series(lua_State *L, plcui_widget_t *widget)
{
    return luat_plcui_chart_series(widget, luaL_checkstring(L, 2));
}

/**
 * 一次替换指定系列的全部数据，数组顺序对应图表从左到右的顺序。
 * @api chart:set_values(series_id, values)
 * @string series_id XML 的 series 节点中已声明的系列 ID，区分大小写。
 * @table values 从索引 1 开始的连续数字数组，长度必须等于 XML 的 point-count（2～1024）。
 * @return bool|nil 成功返回 true，运行错误返回 nil。
 * @return table|nil 失败时返回包含 code、message 的错误表，成功时不返回。
 * @note 每个值必须是 -1000～1000 的有限数字，按两位小数四舍五入保存；不接受 NaN 或无穷大。
 * @note 完整校验和临时缓冲分配成功后才更新；非法数据或内存不足时保留该系列原有数据。
 * @note 成功后重置该系列的环形游标，不改变其他系列、坐标轴范围或显隐状态。
 * @note 超出 Y 轴范围的值按轴边界绘制，get_values 仍返回两位小数精度的保存值。
 * @note 未声明的系列返回 E_RESOURCE；本方法只更新数据，不触发 Lua 业务事件。
 * @usage
 * local chart = xml:find("main", "trend")
 * local values = {}
 * for i = 1, chart:state().point_count do values[i] = 25.5 end
 * chart:set_values("temperature", values) -- XML 已声明 temperature 系列
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
    /* 先写入有界临时数组，全部校验成功后再覆盖系列，保证失败时旧数据不变。 */
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
 * 向指定系列末尾追加一个数据点，并移出当前最旧的数据点。
 * @api chart:add_point(series_id, value)
 * @string series_id XML 的 series 节点中已声明的系列 ID，区分大小写。
 * @number value -1000～1000 的有限数字，按两位小数四舍五入保存。
 * @return bool|nil 成功返回 true，运行错误返回 nil。
 * @return table|nil 失败时返回包含 code、message 的错误表，成功时不返回。
 * @note 使用固定长度环形数据，不改变 point-count；新点绘制在最右侧，其余点向左推进。
 * @note 超出 Y 轴范围只限制绘制位置，get_values 仍可读取保存值；隐藏系列也可以追加数据。
 * @note 未声明的系列返回 E_RESOURCE，非法数值返回 E_SCHEMA；本方法不触发 Lua 业务事件。
 * @usage
 * local chart = xml:find("main", "trend")
 * chart:add_point("temperature", 26.75)
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
 * 按当前从左到右的逻辑顺序读取指定系列的全部数据。
 * @api chart:get_values(series_id)
 * @string series_id XML 的 series 节点中已声明的系列 ID，区分大小写。
 * @return table|nil 成功返回从索引 1 开始的数字数组，长度等于 point-count；运行错误返回 nil。
 * @return table|nil 失败时返回包含 code、message 的错误表，成功时不返回。
 * @note 已处理 add_point 的环形游标：索引 1 为当前最左侧数据，末项为最右侧数据。
 * @note 返回按两位小数保存的值，不返回按坐标轴边界裁剪后的绘制值；隐藏不影响读取。
 * @note 返回独立的 Lua 数组；修改此数组不会修改图表，须再调用 set_values 才会更新。
 * @note 未声明的系列返回 E_RESOURCE。
 * @usage
 * local chart = xml:find("main", "trend")
 * local values = chart:get_values("temperature")
 * log.info("trend", "latest", values[#values])
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
 * 设置所有系列共用的主 Y 轴范围，并重新计算当前数据的绘制位置。
 * @api chart:set_range(minimum, maximum)
 * @number minimum Y 轴下限，-1000～1000 的有限数字，按两位小数处理。
 * @number maximum Y 轴上限，-1000～1000 的有限数字，按两位小数处理后仍须大于 minimum。
 * @return bool|nil 成功返回 true，运行错误返回 nil。
 * @return table|nil 失败时返回包含 code、message 的错误表，成功时不返回。
 * @note 两个边界完整校验后统一更新；非法范围返回 E_SCHEMA，旧坐标轴和数据保持不变。
 * @note 只改变绘制范围，不修改保存数据、各系列的环形顺序或 point-count；扩大范围可重新显示原先被裁到边界的值。
 * @note 不自动生成刻度文字或图例，需要时由外围 label 或背景图提供；本方法不触发 Lua 业务事件。
 * @usage
 * local chart = xml:find("main", "trend")
 * chart:set_range(-20, 120)
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
 * 显示或隐藏指定的一条折线或一组柱状数据。
 * @api chart:set_series_hidden(series_id, hidden)
 * @string series_id XML 的 series 节点中已声明的系列 ID，区分大小写。
 * @bool hidden true 为隐藏该系列，false 为显示该系列。
 * @return bool|nil 成功返回 true，运行错误返回 nil。
 * @return table|nil 失败时返回包含 code、message 的错误表，成功时不返回。
 * @note 只影响指定系列，不隐藏整个 chart；公共 set_hidden 用于整个组件的显隐。
 * @note 隐藏时保留数据和环形顺序，仍允许 set_values、add_point 和 get_values；重新显示时使用当前保存的数据。
 * @note 未声明的系列返回 E_RESOURCE；本方法不触发 Lua 业务事件。
 * @usage
 * local chart = xml:find("main", "trend")
 * chart:set_series_hidden("temperature", true)
 * chart:set_series_hidden("temperature", false)
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

/**
 * 注册 chart 专属方法，并继承公共组件方法、索引表和句柄回收规则。
 * @param L Lua 状态机；调用结束后保持原栈高度。
 * @note 只注册元表，不创建图表；Lua 通过 xml:find 获取 XML 已声明的 chart 句柄。
 */
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
    luat_plcui_binding_register_methods(L, methods);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
