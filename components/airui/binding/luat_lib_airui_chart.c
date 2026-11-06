/*
@module  airui.chart
@summary AIRUI Chart 图表组件 Lua 绑定
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
#include "lvgl9/src/widgets/chart/lv_chart.h"
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
 * @int config.y_min 初始 Y 轴最小值，默认 0；兼容旧配置，作为各纵轴的初始范围
 * @int config.y_max 初始 Y 轴最大值，默认 100；不能与 y_min 相等
 * @table config.y_axis 第一条纵轴的配置，可选，兼容旧的单轴写法
 * @boolean config.y_axis.enable 是否显示第一条轴的刻度和单位，配置该表时默认 true；不影响序列绘制
 * @int config.y_axis.min 第一条轴的最小值，未传时沿用 y_min；同时影响数据缩放
 * @int config.y_axis.max 第一条轴的最大值，未传时沿用 y_max；反向范围自动交换，相等范围无效
 * @int config.y_axis.ticks 刻度标签数量，限制为 2-16，未传时沿用 hdiv（至少 2）
 * @string config.y_axis.unit 单位文字，默认空字符串，最多保存 15 字节
 * @string config.y_axis.side 显示位置，"left" 或 "right"，默认 "left"
 * @int config.y_axis.offset 相对绘图区边缘向外偏移的像素，默认 0，负数按 0 处理
 * @int config.y_axis.color 刻度和单位文字颜色（0xRRGGBB），默认 0x6b7280
 * @table config.y_axes 独立纵轴配置数组，可选，最多 4 项，数组下标就是轴编号（1-4）
 * @table config.y_axes[i] 第 i 条纵轴的配置；第一条轴的范围按 y_min/y_max、y_axis、y_axes[1] 的顺序解析
 * @boolean config.y_axes[i].enable 是否显示该轴的刻度和单位，配置该项时默认 true；不影响序列绘制
 * @int config.y_axes[i].min 该轴的最小值，未传时保留已有范围；初始来自 y_min
 * @int config.y_axes[i].max 该轴的最大值，未传时保留已有范围；初始来自 y_max，不能与 min 相等
 * @int config.y_axes[i].ticks 刻度标签数量，限制为 2-16；第 1 轴默认沿用 hdiv（至少 2），其他轴默认 5
 * @string config.y_axes[i].unit 单位文字，默认空字符串，最多保存 15 字节
 * @string config.y_axes[i].side 显示位置，"left" 或 "right"；第 1 轴默认在左侧，其他轴默认在右侧
 * @int config.y_axes[i].offset 向绘图区外侧偏移的像素；第 1-4 轴默认分别为 0、0、64、128，负数按 0 处理
 * @int config.y_axes[i].color 刻度和单位文字颜色（0xRRGGBB），默认 0x6b7280
 * @int config.point_count 点数量，默认 120（适合 10Hz）
 * @string|int config.type 图表类型，"line"(默认) / "bar" / "stacked"
 * @string|int config.update_mode 更新模式，"shift" 或 "circular"
 * @int config.line_color 曲线颜色（Hex）
 * @int config.line_width 曲线宽度
 * @int config.point_radius 点半径，默认 0
 * @int config.hdiv 水平网格线数量，默认 4
 * @int config.vdiv 垂直网格线数量，默认 6
 * @boolean config.legend 是否显示序列图例，默认 false
 * @int config.bar_group_gap 柱状图分组间距，默认 2
 * @int config.bar_series_gap 柱状图组内序列间距，默认 2
 * @int config.bar_radius 柱状图圆角，默认 0
 * @int config.bg_color 图表背景色（Hex），可选
 * @int config.bg_opa 图表背景透明度，0-255，可选
 * @int config.border_color 图表边框颜色（Hex），可选
 * @int config.border_width 图表边框宽度，可选
 * @int config.grid_color 网格线颜色（Hex），可选
 * @int config.grid_opa 网格线透明度，0-255，可选
 * @boolean config.fill_fade 曲线下方渐变填充，默认 false
 * @table config.fill 全局渐变填充配置，可选，仅对折线序列生效；由未单独设置 fill 的序列继承
 * @boolean config.fill.enable 是否启用填充，未传时沿用 fill_fade 的值
 * @int config.fill.color 固定填充颜色（0xRRGGBB），未配置时使用各序列自身颜色
 * @int config.fill.opa_start 渐变起始不透明度，0-255，默认 255；0 为透明，255 为不透明
 * @int config.fill.opa_end 渐变结束不透明度，0-255，默认 0
 * @userdata config.parent 父对象，默认当前屏幕
 * @return userdata Chart 对象，创建失败或轴配置无效时返回 nil；创建时自动包含编号为 1 的首序列
 * 多纵轴的刻度和单位显示在绘图区外侧，调用方需要通过 x/y/w/h 和轴 offset 预留显示空间。
 * 未配置多轴或逐序列样式时，保留原来的单轴使用方式；单个图表最多包含 8 条序列。
 * @usage
 * local chart = airui.chart({
 *     x = 60, y = 60, w = 500, h = 240,
 *     y_axes = {
 *         { min = 0, max = 100, unit = "%", side = "left" },
 *         { min = 0, max = 45, unit = "mm", side = "right" }
 *     }
 * })
 * chart:add_series({ name = "rain", color = 0x237ab4, y_axis = 2, type = "bar" })
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

static lv_chart_type_t airui_chart_parse_type(lua_State *L, int idx)
{
    if (lua_type(L, idx) == LUA_TNUMBER) {
        int type = (int)lua_tointeger(L, idx);
        if (type == (int)LV_CHART_TYPE_BAR) {
            return LV_CHART_TYPE_BAR;
        }
        if (type == (int)LV_CHART_TYPE_STACKED) {
            return LV_CHART_TYPE_STACKED;
        }
        return LV_CHART_TYPE_LINE;
    }

    const char *type = luaL_optstring(L, idx, "line");
    if (strcmp(type, "bar") == 0) {
        return LV_CHART_TYPE_BAR;
    }
    if (strcmp(type, "stacked") == 0) {
        return LV_CHART_TYPE_STACKED;
    }
    return LV_CHART_TYPE_LINE;
}


static int32_t airui_chart_lua_value_to_point(lua_State *L, int idx)
{
    if (lua_isnoneornil(L, idx)) {
        return LV_CHART_POINT_NONE;
    }
    if (lua_type(L, idx) == LUA_TNUMBER) {
        return (int32_t)lua_tointeger(L, idx);
    }
    return LV_CHART_POINT_NONE;
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
        values[i] = airui_chart_lua_value_to_point(L, -1);
        lua_pop(L, 1);
    }
    return values;
}

/**
 * Chart:set_values(series_id, values)
 * @api chart:set_values(series_id, values)
 * @int series_id 曲线编号（从 1 开始）
 * @table values 数值数组，nil 项会显示为空点
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
        int32_t empty = LV_CHART_POINT_NONE;
        if (airui_chart_set_series_values(chart, (uint32_t)(id - 1), &empty, 1) != AIRUI_OK) {
            return luaL_error(L, "chart:set_values invalid series id");
        }
        return 0;
    }
    if (values == NULL) {
        return luaL_error(L, "chart:set_values out of memory");
    }

    int ret = airui_chart_set_series_values(chart, (uint32_t)(id - 1), values, (uint32_t)len);
    luat_heap_free(values);
    if (ret != AIRUI_OK) return luaL_error(L, "chart:set_values invalid series id");
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
    if (airui_chart_push_series_value(chart, (uint32_t)(id - 1), value) != AIRUI_OK) {
        return luaL_error(L, "chart:push invalid series id");
    }
    return 0;
}

/**
 * 添加序列并指定独立纵轴、图表类型和填充样式
 * @api chart:add_series(config)
 * @table config 新序列的配置表；旧的仅包含 color、name 的写法仍然有效
 * @int config.color 序列颜色（0xRRGGBB），默认 0x00b4ff
 * @string config.name 图例中的序列名称，默认 "series-N"，其中 N 为返回的序列编号
 * @int config.y_axis 使用的纵轴编号，范围 1-4，默认 1；对应创建参数 y_axes 的数组下标
 * @string config.type 序列类型，"line"、"bar" 或 "stacked"，未传时继承图表当前的全局类型
 * @boolean|table config.fill 该序列的独立填充配置；true 开启，false 关闭，未传时继承全局填充
 * @boolean config.fill.enable 表形式的填充开关，传入 fill 表时默认 true；仅对 "line" 类型生效
 * @int config.fill.color 填充颜色（0xRRGGBB），未传时沿用有效填充配色；无固定配色时使用序列颜色
 * @int config.fill.opa_start 渐变起始不透明度，0-255，未传时继承全局配置，初始为 255
 * @int config.fill.opa_end 渐变结束不透明度，0-255，未传时继承全局配置，初始为 0
 * @return int 序列编号，首序列已存在，新增编号从 2 开始；总数最多 8 条，无效配置或添加失败时抛出 Lua 错误
 * 面积图使用 type = "line" 配合 fill 实现，不支持单独的 "area" 类型。
 * 同轴柱状序列按类型分组或堆叠，跨轴柱状序列采用叠加显示。
 * @usage
 * local rain = chart:add_series({
 *     name = "rain", color = 0x237ab4,
 *     y_axis = 2, type = "bar", fill = false
 * })
 */
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
    if (airui_chart_set_series_config(chart, (uint32_t)(id - 1), L, 2) != AIRUI_OK) {
        airui_chart_remove_series(chart, (uint32_t)(id - 1));
        return luaL_error(L, "chart:add_series invalid configuration or out of memory");
    }
    lua_pushinteger(L, id);
    return 1;
}

/**
 * 修改已有序列的轴绑定、类型和填充，保留已有数据及环形更新位置
 * @api chart:set_series(series_id, config)
 * @int series_id 已存在的序列编号，从 1 开始
 * @table config 要修改的序列配置表，未传的字段保留原值
 * @int config.y_axis 目标纵轴编号，范围 1-4，未传时保留当前绑定
 * @string config.type 序列类型，"line"、"bar" 或 "stacked"，未传时保留当前类型
 * @boolean|table config.fill 独立填充配置；true 开启，false 关闭，未传时保留已有覆盖或继承关系
 * @boolean config.fill.enable 表形式的填充开关，传入 fill 表时默认 true；仅对 "line" 类型生效
 * @int config.fill.color 填充颜色（0xRRGGBB），未传时保留有效配色；无固定配色时使用序列颜色
 * @int config.fill.opa_start 渐变起始不透明度，0-255，未传时保留该序列当前有效值
 * @int config.fill.opa_end 渐变结束不透明度，0-255，未传时保留该序列当前有效值
 * @return nil 序列不存在或配置无效时抛出 Lua 错误
 * 显式设置 fill 后，该序列不再跟随 set_fill_fade() 的全局填充修改。
 * 颜色和图例名称分别使用 set_line_color(series_id, color) 和 set_series_name(series_id, name) 修改。
 * @usage
 * chart:set_series(1, { y_axis = 3 })
 * chart:set_series(1, { type = "line", fill = { enable = true, opa_start = 80, opa_end = 0 } })
 */
static int l_chart_set_series(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    lua_Integer id = luaL_checkinteger(L, 2);
    luaL_checktype(L, 3, LUA_TTABLE);
    if (id < 1 || id > 8 || airui_chart_set_series_config(chart, (uint32_t)(id - 1), L, 3) != AIRUI_OK) {
        return luaL_error(L, "chart:set_series invalid configuration or series id");
    }
    return 0;
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
 * @int value 可选，默认清为空点
 * @return nil
 */
static int l_chart_clear(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int32_t value = lua_isnoneornil(L, 2) ? LV_CHART_POINT_NONE : (int32_t)luaL_checkinteger(L, 2);
    airui_chart_clear(chart, value);
    return 0;
}

/**
 * Chart:set_point_count(count)
 * @api chart:set_point_count(count)
 * @int count 点数量，范围 1-65535；多轴和混合图的所有图层同步修改，超出范围时抛出 Lua 错误
 * @return nil
 */
static int l_chart_set_point_count(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    lua_Integer count = luaL_checkinteger(L, 2);
    if (count < 1 || count > 65535) return luaL_error(L, "chart:set_point_count expected 1..65535");
    airui_chart_set_point_count(chart, (uint32_t)count);
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
 * Chart:set_type(type)
 * @api chart:set_type(type)
 * @string|int type "line" / "bar" / "stacked"，作用于图表内全部序列；仅修改某条序列时使用 set_series()
 * @return nil
 */
static int l_chart_set_type(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    lv_chart_type_t type = airui_chart_parse_type(L, 2);
    if (airui_chart_set_type(chart, type) != AIRUI_OK) {
        return luaL_error(L, "chart:set_type invalid type");
    }
    return 0;
}

/**
 * Chart:set_bar_gap(group_gap, series_gap)
 * @api chart:set_bar_gap(group_gap, series_gap)
 * @int group_gap 分组间距
 * @int series_gap 组内序列间距
 * @return nil
 */
static int l_chart_set_bar_gap(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int32_t group_gap = (int32_t)luaL_checkinteger(L, 2);
    int32_t series_gap = (int32_t)luaL_optinteger(L, 3, 0);
    airui_chart_set_bar_gap(chart, group_gap, series_gap);
    return 0;
}

/**
 * Chart:set_bar_radius(radius)
 * @api chart:set_bar_radius(radius)
 * @int radius 圆角
 * @return nil
 */
static int l_chart_set_bar_radius(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    int32_t radius = (int32_t)luaL_checkinteger(L, 2);
    airui_chart_set_bar_radius(chart, radius);
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

/**
 * 设置 X 轴刻度标签
 * @api chart:set_x_axis(config)
 * @table config X 轴配置表，用于等距样本的刻度和单位显示
 * @boolean config.enable 是否显示刻度和单位，默认 true
 * @int config.min 刻度标签最小值，默认 0
 * @int config.max 刻度标签最大值，默认 100；数据仍按等距样本位置绘制
 * @int config.ticks 刻度标签数量，默认 6，最多显示 16 个
 * @string config.unit 单位文字，未传时清空，最多保存 15 字节
 * @return nil
 */
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

/**
 * 设置指定 Y 轴；兼容省略轴编号的 set_y_axis(config) 写法
 * @api chart:set_y_axis(axis_id, config)
 * @int axis_id 纵轴编号，范围 1-4；省略该参数时配置第一条轴
 * @table config 该轴的配置表，修改范围会同步缩放绑定到该轴的所有序列
 * @boolean config.enable 是否显示该轴的刻度和单位，默认 true；false 不隐藏序列，也不取消轴范围
 * @int config.min 最小值，未传时保留该轴当前值；不能与 max 相等
 * @int config.max 最大值，未传时保留该轴当前值；小于 min 时自动交换
 * @int config.ticks 刻度标签数量，限制为 2-16，未传时保留该轴当前值
 * @string config.unit 单位文字，最多保存 15 字节；未传时保留当前值，空字符串可清除单位
 * @string config.side 显示位置，"left" 或 "right"，未传时保留当前值
 * @int config.offset 向绘图区外侧偏移的像素，未传时保留当前值，负数按 0 处理
 * @int config.color 刻度和单位文字颜色（0xRRGGBB），未传时保留当前值
 * @return nil 轴编号、范围或配置无效时抛出 Lua 错误
 * 第 1 轴对应旧的 y_min/y_max 和 y_axis 配置；无需修改旧的单轴调用代码。
 * 与旧版仅修改标签的行为相比，当前 min/max 同时决定实际绘图范围。
 * @usage
 * chart:set_y_axis({ min = 0, max = 100, unit = "%" })
 * chart:set_y_axis(2, { max = 90 })
 * chart:set_y_axis(3, { side = "right", offset = 80, color = 0x2b8a3e })
 */
static int l_chart_set_y_axis(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    lua_Integer axis = 1;
    int config_idx = 2;
    if (lua_type(L, 2) == LUA_TNUMBER) {
        axis = luaL_checkinteger(L, 2);
        config_idx = 3;
    }
    luaL_checktype(L, config_idx, LUA_TTABLE);
    /* 转换索引前检查整数范围，具体纵轴上限由控件实现校验。 */
    if (axis < 1 || (uint64_t)axis > UINT32_MAX ||
        airui_chart_set_y_axis_from_config(chart, (uint32_t)(axis - 1), L, config_idx) != AIRUI_OK) {
        return luaL_error(L, "chart:set_y_axis invalid axis, range or configuration");
    }
    return 0;
}

/**
 * Chart:set_fill_fade(enable|config)
 * @api chart:set_fill_fade(enable|config)
 * @boolean|table enable 全局填充开关；true 开启、false 关闭，也可传入下述 config 配置表
 * @table config 全局渐变填充配置，与布尔开关二选一传入，仅影响继承全局填充的折线序列
 * @boolean config.enable 是否开启全局填充，使用表形式时默认 true
 * @int config.color 固定填充颜色（0xRRGGBB），未传时保留已有配色；关闭且未传颜色时清除固定配色
 * @int config.opa_start 渐变起始不透明度，0-255，未传时保留当前值，初始为 255
 * @int config.opa_end 渐变结束不透明度，0-255，未传时保留当前值，初始为 0
 * @return nil
 * @usage
 * chart:set_fill_fade(true)
 * chart:set_fill_fade({ enable = true, opa_start = 100, opa_end = 0 })
 */
static int l_chart_set_fill_fade(lua_State *L)
{
    lv_obj_t *chart = airui_check_component(L, 1, AIRUI_CHART_MT);
    bool enable = true;
    lv_color_t color;
    const lv_color_t *color_ptr = NULL;
    int opa_start = -1;
    int opa_end = -1;

    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "enable");
        if (lua_type(L, -1) == LUA_TBOOLEAN) {
            enable = lua_toboolean(L, -1);
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "color");
        if (lua_type(L, -1) == LUA_TNUMBER) {
            color = lv_color_hex((uint32_t)lua_tointeger(L, -1));
            color_ptr = &color;
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "opa_start");
        if (lua_type(L, -1) == LUA_TNUMBER) {
            opa_start = (int)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "opa_end");
        if (lua_type(L, -1) == LUA_TNUMBER) {
            opa_end = (int)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
    }
    else {
        enable = lua_toboolean(L, 2);
    }

    airui_chart_set_fill_fade(chart, enable, color_ptr, opa_start, opa_end);
    return 0;
}

/**
 * Chart:destroy()
 * @api chart:destroy()
 * @return nil
 */
static int l_chart_destroy(lua_State *L)
{
    return airui_component_destroy_userdata(L, 1, AIRUI_CHART_MT);
}

void airui_register_chart_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_CHART_MT);
    airui_component_set_metatable_gc(L);
    static const luaL_Reg methods[] = {
        {"set_values", l_chart_set_values},
        {"push", l_chart_push},
        {"add_series", l_chart_add_series},
        {"set_series", l_chart_set_series},
        {"remove_series", l_chart_remove_series},
        {"set_series_name", l_chart_set_series_name},
        {"clear", l_chart_clear},
        {"set_point_count", l_chart_set_point_count},
        {"set_type", l_chart_set_type},
        {"set_update_mode", l_chart_set_update_mode},
        {"set_bar_gap", l_chart_set_bar_gap},
        {"set_bar_radius", l_chart_set_bar_radius},
        {"set_line_color", l_chart_set_line_color},
        {"set_x_axis", l_chart_set_x_axis},
        {"set_y_axis", l_chart_set_y_axis},
        {"set_fill_fade", l_chart_set_fill_fade},
        {"destroy", l_chart_destroy},
        {"is_destroyed", airui_component_is_destroyed},
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
