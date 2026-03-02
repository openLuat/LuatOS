/**
 * @file luat_airui_chart.c
 * @summary Chart 曲线图组件实现
 * @responsible Chart 创建、数据更新、样式与回调绑定
 */

#include "luat_airui_component.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/widgets/chart/lv_chart.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_color.h"
#include <string.h>

static airui_ctx_t *airui_chart_get_ctx(lua_State *L);
static lv_chart_series_t *airui_chart_get_series(lv_obj_t *chart);
static lv_chart_update_mode_t airui_chart_parse_update_mode(lua_State *L, int idx);

/**
 * 从配置表创建 Chart 组件
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL Chart 对象指针，失败返回 NULL
 */
lv_obj_t *airui_chart_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_chart_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);
    int w = airui_marshal_integer(L, idx, "w", 240);
    int h = airui_marshal_integer(L, idx, "h", 120);

    int y_min = airui_marshal_integer(L, idx, "y_min", 0);
    int y_max = airui_marshal_integer(L, idx, "y_max", 100);
    if (y_max < y_min) {
        int tmp = y_min;
        y_min = y_max;
        y_max = tmp;
    }

    uint32_t point_count = (uint32_t)airui_marshal_integer(L, idx, "point_count", 120);
    if (point_count < 1) {
        point_count = 1;
    }

    uint32_t hdiv = (uint32_t)airui_marshal_integer(L, idx, "hdiv", 4);
    uint32_t vdiv = (uint32_t)airui_marshal_integer(L, idx, "vdiv", 6);
    int line_width = airui_marshal_integer(L, idx, "line_width", 2);
    int point_radius = airui_marshal_integer(L, idx, "point_radius", 0);

    lv_color_t line_color = lv_color_make(0x00, 0xb4, 0xff);
    lv_color_t parsed_color;
    if (airui_marshal_color(L, idx, "line_color", &parsed_color)) {
        line_color = parsed_color;
    }

    lv_obj_t *chart = lv_chart_create(parent);
    if (chart == NULL) {
        return NULL;
    }

    lv_obj_set_pos(chart, x, y);
    lv_obj_set_size(chart, w, h);
    lv_chart_set_type(chart, LV_CHART_TYPE_LINE);
    lv_chart_set_point_count(chart, point_count);
    lv_chart_set_axis_range(chart, LV_CHART_AXIS_PRIMARY_Y, y_min, y_max);
    lv_chart_set_update_mode(chart, airui_chart_parse_update_mode(L_state, idx));
    lv_chart_set_div_line_count(chart, hdiv, vdiv);

    lv_chart_series_t *series = lv_chart_add_series(chart, line_color, LV_CHART_AXIS_PRIMARY_Y);
    if (series == NULL) {
        lv_obj_delete(chart);
        return NULL;
    }

    if (line_width < 1) {
        line_width = 1;
    }
    if (point_radius < 0) {
        point_radius = 0;
    }

    lv_style_selector_t items_sel = (lv_style_selector_t)((uint32_t)LV_PART_ITEMS | (uint32_t)LV_STATE_DEFAULT);
    lv_style_selector_t indicator_sel = (lv_style_selector_t)((uint32_t)LV_PART_INDICATOR | (uint32_t)LV_STATE_DEFAULT);
    lv_obj_set_style_line_width(chart, line_width, items_sel);
    lv_obj_set_style_size(chart, point_radius, point_radius, indicator_sel);
    lv_chart_set_all_values(chart, series, y_min);
    lv_chart_refresh(chart);

    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, chart, AIRUI_COMPONENT_CHART);
    if (meta == NULL) {
        lv_obj_delete(chart);
        return NULL;
    }
    meta->user_data = series;

    int on_point_ref = airui_component_capture_callback(L, idx, "on_point");
    if (on_point_ref != LUA_NOREF) {
        airui_chart_set_on_point(chart, on_point_ref);
    }

    return chart;
}


/**
 * 从 Lua 注册表中获取 AIRUI 上下文
 * @param L Lua 状态
 * @return AIRUI 上下文，失败返回 NULL
 */
static airui_ctx_t *airui_chart_get_ctx(lua_State *L)
{
    if (L == NULL) {
        return NULL;
    }

    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return ctx;
}

/**
 * 获取 Chart 组件绑定的数据序列
 * @param chart Chart 对象指针
 * @return 图表序列指针，失败返回 NULL
 */
static lv_chart_series_t *airui_chart_get_series(lv_obj_t *chart)
{
    if (chart == NULL) {
        return NULL;
    }

    airui_component_meta_t *meta = airui_component_meta_get(chart);
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }

    return (lv_chart_series_t *)meta->user_data;
}

/**
 * 解析配置中的更新模式
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL 图表更新模式（shift 或 circular）
 */
static lv_chart_update_mode_t airui_chart_parse_update_mode(lua_State *L, int idx)
{
    lua_getfield(L, idx, "update_mode");
    lv_chart_update_mode_t mode = LV_CHART_UPDATE_MODE_SHIFT;
    if (lua_type(L, -1) == LUA_TNUMBER) {
        int mode_int = (int)lua_tointeger(L, -1);
        mode = (mode_int == (int)LV_CHART_UPDATE_MODE_CIRCULAR) ?
            LV_CHART_UPDATE_MODE_CIRCULAR :
            LV_CHART_UPDATE_MODE_SHIFT;
    }
    else if (lua_type(L, -1) == LUA_TSTRING) {
        const char *mode_str = lua_tostring(L, -1);
        if (mode_str != NULL && strcmp(mode_str, "circular") == 0) {
            mode = LV_CHART_UPDATE_MODE_CIRCULAR;
        }
    }
    lua_pop(L, 1);
    return mode;
}


/**
 * 一次设置全部数据点
 * @param chart Chart 对象指针
 * @param values 数据数组
 * @param count 数据长度
 * @return 0 成功，<0 失败
 */
int airui_chart_set_values(lv_obj_t *chart, const int32_t *values, uint32_t count)
{
    if (chart == NULL || values == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_series_t *series = airui_chart_get_series(chart);
    if (series == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    uint32_t point_count = lv_chart_get_point_count(chart);
    int32_t fill = count > 0 ? values[count - 1] : 0;
    for (uint32_t i = 0; i < point_count; i++) {
        int32_t value = (i < count) ? values[i] : fill;
        lv_chart_set_series_value_by_id(chart, series, i, value);
    }

    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 推送单个数据点（会刷新曲线）
 * @param chart Chart 对象指针
 * @param value 数据值
 * @return 0 成功，<0 失败
 */
int airui_chart_push_value(lv_obj_t *chart, int32_t value)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_series_t *series = airui_chart_get_series(chart);
    if (series == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_set_next_value(chart, series, value);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 清空图表并填充固定值
 * @param chart Chart 对象指针
 * @param value 填充值
 * @return 0 成功，<0 失败
 */
int airui_chart_clear(lv_obj_t *chart, int32_t value)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_series_t *series = airui_chart_get_series(chart);
    if (series == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_set_all_values(chart, series, value);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 设置 Y 轴坐标范围
 * @param chart Chart 对象指针
 * @param min 最小值
 * @param max 最大值（若小于 min 会自动交换）
 * @return 0 成功，<0 失败
 */
int airui_chart_set_range(lv_obj_t *chart, int32_t min, int32_t max)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (max < min) {
        int32_t tmp = min;
        min = max;
        max = tmp;
    }

    lv_chart_set_axis_range(chart, LV_CHART_AXIS_PRIMARY_Y, min, max);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 设置点数
 * @param chart Chart 对象指针
 * @param count 点数（小于 1 时自动修正为 1）
 * @return 0 成功，<0 失败
 */
int airui_chart_set_point_count(lv_obj_t *chart, uint32_t count)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (count < 1) {
        count = 1;
    }

    lv_chart_set_point_count(chart, count);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 设置更新模式
 * @param chart Chart 对象指针
 * @param mode 更新模式（shift/circular）
 * @return 0 成功，<0 失败
 */
int airui_chart_set_update_mode(lv_obj_t *chart, lv_chart_update_mode_t mode)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (mode != LV_CHART_UPDATE_MODE_SHIFT && mode != LV_CHART_UPDATE_MODE_CIRCULAR) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_set_update_mode(chart, mode);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 设置线条颜色
 * @param chart Chart 对象指针
 * @param color 颜色值
 * @return 0 成功，<0 失败
 */
int airui_chart_set_line_color(lv_obj_t *chart, lv_color_t color)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_series_t *series = airui_chart_get_series(chart);
    if (series == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_set_series_color(chart, series, color);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 设置数据点点击回调
 * @param chart Chart 对象指针
 * @param callback_ref Lua 回调引用
 * @return 0 成功，<0 失败
 */
int airui_chart_set_on_point(lv_obj_t *chart, int callback_ref)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(chart);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return airui_component_bind_event(meta, AIRUI_EVENT_CLICKED, callback_ref);
}

/**
 * 获取当前按下的数据点索引
 * @param chart Chart 对象指针
 * @return 按下点索引，非法返回 -1
 */
int airui_chart_get_pressed_point(lv_obj_t *chart)
{
    if (chart == NULL) {
        return -1;
    }

    uint32_t point_count = lv_chart_get_point_count(chart);
    uint32_t pressed = lv_chart_get_pressed_point(chart);
    if (pressed >= point_count) {
        return -1;
    }

    return (int)pressed;
}
