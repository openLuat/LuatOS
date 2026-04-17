/**
 * @file luat_airui_chart.c
 * @summary Chart 曲线图组件实现
 * @responsible Chart 创建、数据更新、样式与回调绑定
 */

#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/widgets/chart/lv_chart.h"
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_async.h"
#include "lvgl9/src/misc/lv_color.h"
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#define AIRUI_CHART_MAX_SERIES 8
#define AIRUI_CHART_MAX_NAME_LEN 31
#define AIRUI_CHART_MAX_UNIT_LEN 15
#define AIRUI_CHART_MAX_TICKS 16

/* 图表轴线数据 */
typedef struct {
    bool enabled;
    int32_t min;
    int32_t max;
    uint32_t tick_count;
    char unit[AIRUI_CHART_MAX_UNIT_LEN + 1];
    lv_obj_t *unit_label;
    lv_obj_t *tick_labels[AIRUI_CHART_MAX_TICKS];
    uint32_t tick_label_count;
} airui_chart_axis_state_t;

/* 图表数据 */
typedef struct {
    lv_chart_series_t *series[AIRUI_CHART_MAX_SERIES];
    lv_color_t series_colors[AIRUI_CHART_MAX_SERIES];
    char series_names[AIRUI_CHART_MAX_SERIES][AIRUI_CHART_MAX_NAME_LEN + 1];
    uint8_t series_count;
    int32_t y_min;
    int32_t y_max;
    uint32_t point_count;
    uint32_t hdiv;
    uint32_t vdiv;
    lv_chart_type_t type;
    int32_t bar_group_gap;
    int32_t bar_series_gap;
    int32_t bar_radius;
    bool legend_enabled;
    lv_obj_t *legend_box;
    lv_obj_t *legend_marks[AIRUI_CHART_MAX_SERIES];
    lv_obj_t *legend_labels[AIRUI_CHART_MAX_SERIES];
    airui_chart_axis_state_t axis_x;
    airui_chart_axis_state_t axis_y;
} airui_chart_data_t;

static airui_ctx_t *airui_chart_get_ctx(lua_State *L);
static lv_chart_series_t *airui_chart_get_series_by_index(lv_obj_t *chart, uint32_t series_index);
static airui_chart_data_t *airui_chart_get_data(lv_obj_t *chart);
static lv_chart_type_t airui_chart_parse_type(lua_State *L, int idx);
static lv_chart_update_mode_t airui_chart_parse_update_mode(lua_State *L, int idx);
static void airui_chart_apply_bar_style(lv_obj_t *chart, airui_chart_data_t *data);
static void airui_chart_axis_clear(lv_obj_t *chart, airui_chart_axis_state_t *axis, bool is_x);
static void airui_chart_axis_render(lv_obj_t *chart, airui_chart_axis_state_t *axis, bool is_x);
static void airui_chart_axis_render_all(lv_obj_t *chart);
static void airui_chart_legend_clear(lv_obj_t *chart);
static void airui_chart_legend_render(lv_obj_t *chart);
static void airui_chart_cleanup_event_cb(lv_event_t *e);
static void airui_chart_overlay_event_cb(lv_event_t *e);
static void airui_chart_render_overlays_async(void *user_data);

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
    int x = airui_marshal_floor_integer(L, idx, "x", 0);
    int y = airui_marshal_floor_integer(L, idx, "y", 0);
    int w = airui_marshal_floor_integer(L, idx, "w", 240);
    int h = airui_marshal_floor_integer(L, idx, "h", 120);

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
    int bg_opa = airui_marshal_integer(L, idx, "bg_opa", -1);
    int border_width = airui_marshal_integer(L, idx, "border_width", -1);
    int grid_opa = airui_marshal_integer(L, idx, "grid_opa", -1);
    int32_t bar_group_gap = airui_marshal_integer(L, idx, "bar_group_gap", 2);
    int32_t bar_series_gap = airui_marshal_integer(L, idx, "bar_series_gap", 2);
    int32_t bar_radius = airui_marshal_integer(L, idx, "bar_radius", 0);
    lv_chart_type_t chart_type = airui_chart_parse_type(L_state, idx);

    lv_color_t line_color = lv_color_make(0x00, 0xb4, 0xff);
    lv_color_t parsed_color;
    lv_color_t bg_color;
    lv_color_t border_color;
    lv_color_t grid_color;
    if (airui_marshal_color(L, idx, "line_color", &parsed_color)) {
        line_color = parsed_color;
    }

    lv_obj_t *chart = lv_chart_create(parent);
    if (chart == NULL) {
        return NULL;
    }

    airui_chart_data_t *chart_data = (airui_chart_data_t *)luat_heap_malloc(sizeof(airui_chart_data_t));
    if (chart_data == NULL) {
        lv_obj_delete(chart);
        return NULL;
    }
    memset(chart_data, 0, sizeof(airui_chart_data_t));

    lv_obj_set_pos(chart, x, y);
    lv_obj_set_size(chart, w, h);
    lv_chart_set_type(chart, chart_type);
    lv_chart_set_point_count(chart, point_count);
    lv_chart_set_axis_range(chart, LV_CHART_AXIS_PRIMARY_Y, y_min, y_max);
    lv_chart_set_update_mode(chart, airui_chart_parse_update_mode(L_state, idx));
    lv_chart_set_div_line_count(chart, hdiv, vdiv);

    if (airui_marshal_color(L, idx, "bg_color", &bg_color)) {
        lv_obj_set_style_bg_color(chart, bg_color, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_opa(chart,
                                airui_marshal_opacity(bg_opa >= 0 ? bg_opa : LV_OPA_COVER),
                                (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    else if (bg_opa >= 0) {
        lv_obj_set_style_bg_opa(chart,
                                airui_marshal_opacity(bg_opa),
                                (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }

    if (airui_marshal_color(L, idx, "border_color", &border_color)) {
        lv_obj_set_style_border_color(chart, border_color, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(chart,
                                      border_width >= 0 ? border_width : 1,
                                      (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    else if (border_width >= 0) {
        lv_obj_set_style_border_width(chart, border_width, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }

    if (airui_marshal_color(L, idx, "grid_color", &grid_color)) {
        lv_obj_set_style_line_color(chart, grid_color, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
        if (grid_opa >= 0) {
            lv_obj_set_style_line_opa(chart,
                                      airui_marshal_opacity(grid_opa),
                                      (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
        }
    }
    else if (grid_opa >= 0) {
        lv_obj_set_style_line_opa(chart,
                                  airui_marshal_opacity(grid_opa),
                                  (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }

    lv_chart_series_t *series = lv_chart_add_series(chart, line_color, LV_CHART_AXIS_PRIMARY_Y);
    if (series == NULL) {
        luat_heap_free(chart_data);
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

    chart_data->series[0] = series;
    chart_data->series_colors[0] = line_color;
    strncpy(chart_data->series_names[0], "series-1", AIRUI_CHART_MAX_NAME_LEN);
    chart_data->series_names[0][AIRUI_CHART_MAX_NAME_LEN] = '\0';
    chart_data->series_count = 1;
    chart_data->y_min = y_min;
    chart_data->y_max = y_max;
    chart_data->point_count = point_count;
    chart_data->hdiv = hdiv;
    chart_data->vdiv = vdiv;
    chart_data->type = chart_type;
    chart_data->bar_group_gap = bar_group_gap;
    chart_data->bar_series_gap = bar_series_gap;
    chart_data->bar_radius = bar_radius;
    chart_data->axis_x.min = 0;
    chart_data->axis_x.max = (point_count > 0) ? (int32_t)(point_count - 1) : 0;
    chart_data->axis_x.tick_count = (vdiv > 1) ? vdiv : 2;
    chart_data->axis_y.min = y_min;
    chart_data->axis_y.max = y_max;
    chart_data->axis_y.tick_count = (hdiv > 1) ? hdiv : 2;

    airui_chart_apply_bar_style(chart, chart_data);

    lua_getfield(L_state, idx, "legend");
    if (lua_type(L_state, -1) == LUA_TBOOLEAN) {
        chart_data->legend_enabled = lua_toboolean(L_state, -1);
    }
    lua_pop(L_state, 1);

    lua_getfield(L_state, idx, "x_axis");
    if (lua_istable(L_state, -1)) {
        chart_data->axis_x.enabled = true;
        lua_getfield(L_state, -1, "enable");
        if (lua_type(L_state, -1) == LUA_TBOOLEAN) {
            chart_data->axis_x.enabled = lua_toboolean(L_state, -1);
        }
        lua_pop(L_state, 1);

        lua_getfield(L_state, -1, "min");
        if (lua_type(L_state, -1) == LUA_TNUMBER) {
            chart_data->axis_x.min = (int32_t)lua_tointeger(L_state, -1);
        }
        lua_pop(L_state, 1);

        lua_getfield(L_state, -1, "max");
        if (lua_type(L_state, -1) == LUA_TNUMBER) {
            chart_data->axis_x.max = (int32_t)lua_tointeger(L_state, -1);
        }
        lua_pop(L_state, 1);

        lua_getfield(L_state, -1, "ticks");
        if (lua_type(L_state, -1) == LUA_TNUMBER) {
            uint32_t ticks = (uint32_t)lua_tointeger(L_state, -1);
            if (ticks >= 2) {
                chart_data->axis_x.tick_count = ticks;
            }
        }
        lua_pop(L_state, 1);

        lua_getfield(L_state, -1, "unit");
        if (lua_type(L_state, -1) == LUA_TSTRING) {
            const char *unit = lua_tostring(L_state, -1);
            if (unit != NULL) {
                strncpy(chart_data->axis_x.unit, unit, AIRUI_CHART_MAX_UNIT_LEN);
                chart_data->axis_x.unit[AIRUI_CHART_MAX_UNIT_LEN] = '\0';
            }
        }
        lua_pop(L_state, 1);
    }
    lua_pop(L_state, 1);

    lua_getfield(L_state, idx, "y_axis");
    if (lua_istable(L_state, -1)) {
        chart_data->axis_y.enabled = true;
        lua_getfield(L_state, -1, "enable");
        if (lua_type(L_state, -1) == LUA_TBOOLEAN) {
            chart_data->axis_y.enabled = lua_toboolean(L_state, -1);
        }
        lua_pop(L_state, 1);

        lua_getfield(L_state, -1, "min");
        if (lua_type(L_state, -1) == LUA_TNUMBER) {
            chart_data->axis_y.min = (int32_t)lua_tointeger(L_state, -1);
        }
        lua_pop(L_state, 1);

        lua_getfield(L_state, -1, "max");
        if (lua_type(L_state, -1) == LUA_TNUMBER) {
            chart_data->axis_y.max = (int32_t)lua_tointeger(L_state, -1);
        }
        lua_pop(L_state, 1);

        lua_getfield(L_state, -1, "ticks");
        if (lua_type(L_state, -1) == LUA_TNUMBER) {
            uint32_t ticks = (uint32_t)lua_tointeger(L_state, -1);
            if (ticks >= 2) {
                chart_data->axis_y.tick_count = ticks;
            }
        }
        lua_pop(L_state, 1);

        lua_getfield(L_state, -1, "unit");
        if (lua_type(L_state, -1) == LUA_TSTRING) {
            const char *unit = lua_tostring(L_state, -1);
            if (unit != NULL) {
                strncpy(chart_data->axis_y.unit, unit, AIRUI_CHART_MAX_UNIT_LEN);
                chart_data->axis_y.unit[AIRUI_CHART_MAX_UNIT_LEN] = '\0';
            }
        }
        lua_pop(L_state, 1);
    }
    lua_pop(L_state, 1);

    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, chart, AIRUI_COMPONENT_CHART);
    if (meta == NULL) {
        luat_heap_free(chart_data);
        lv_obj_delete(chart);
        return NULL;
    }
    meta->user_data = chart_data;

    lv_obj_add_event_cb(chart, airui_chart_cleanup_event_cb, LV_EVENT_DELETE, chart_data);
    lv_obj_add_event_cb(chart, airui_chart_overlay_event_cb, LV_EVENT_SIZE_CHANGED, NULL);
    lv_obj_add_event_cb(chart, airui_chart_overlay_event_cb, LV_EVENT_STYLE_CHANGED, NULL);

    lv_async_call(airui_chart_render_overlays_async, chart);

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
static airui_chart_data_t *airui_chart_get_data(lv_obj_t *chart)
{
    if (chart == NULL) {
        return NULL;
    }

    airui_component_meta_t *meta = airui_component_meta_get(chart);
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }

    return (airui_chart_data_t *)meta->user_data;
}

/**
 * 获取图表数据序列
 * @param chart Chart 对象指针
 * @param series_index 序列索引
 * @return 图表序列指针，失败返回 NULL
 */
static lv_chart_series_t *airui_chart_get_series_by_index(lv_obj_t *chart, uint32_t series_index)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || series_index >= data->series_count) {
        return NULL;
    }

    return data->series[series_index];
}

/**
 * 获取图表数据序列
 * @param chart Chart 对象指针
 * @return 图表序列指针，失败返回 NULL
 */
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

// 解析图表类型
static lv_chart_type_t airui_chart_parse_type(lua_State *L, int idx)
{
    lv_chart_type_t type = LV_CHART_TYPE_LINE;

    lua_getfield(L, idx, "type");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        int type_int = (int)lua_tointeger(L, -1);
        if (type_int == (int)LV_CHART_TYPE_BAR) {
            type = LV_CHART_TYPE_BAR;
        } else if (type_int == (int)LV_CHART_TYPE_STACKED) {
            type = LV_CHART_TYPE_STACKED;
        } else if (type_int == (int)LV_CHART_TYPE_LINE) {
            type = LV_CHART_TYPE_LINE;
        }
    } else if (lua_type(L, -1) == LUA_TSTRING) {
        const char *type_str = lua_tostring(L, -1);
        if (type_str != NULL) {
            if (strcmp(type_str, "bar") == 0) {
                type = LV_CHART_TYPE_BAR;
            } else if (strcmp(type_str, "stacked") == 0) {
                type = LV_CHART_TYPE_STACKED;
            }
        }
    }
    lua_pop(L, 1);

    return type;
}

// 应用图表柱状样式
static void airui_chart_apply_bar_style(lv_obj_t *chart, airui_chart_data_t *data)
{
    if (chart == NULL || data == NULL) {
        return;
    }

    int32_t group_gap = data->bar_group_gap;
    int32_t series_gap = data->bar_series_gap;
    int32_t radius = data->bar_radius;
    if (group_gap < 0) {
        group_gap = 0;
    }
    if (series_gap < 0) {
        series_gap = 0;
    }
    if (radius < 0) {
        radius = 0;
    }

    lv_obj_update_layout(chart);
    int32_t content_w = lv_obj_get_content_width(chart);
    if (content_w < 1) {
        content_w = 1;
    }

    uint32_t point_count = lv_chart_get_point_count(chart);
    if (point_count < 1) {
        point_count = 1;
    }

    if (point_count > 1) {
        int32_t max_group_gap = (content_w - (int32_t)point_count) / (int32_t)(point_count - 1);
        if (max_group_gap < 0) {
            max_group_gap = 0;
        }
        if (group_gap > max_group_gap) {
            group_gap = max_group_gap;
        }
    } else {
        group_gap = 0;
    }

    int32_t block_w = (content_w - ((int32_t)(point_count - 1) * group_gap)) / (int32_t)point_count;
    if (block_w < 1) {
        block_w = 1;
    }

    uint32_t series_count = data->series_count > 0 ? data->series_count : 1;
    if (series_count > 1) {
        int32_t max_series_gap = (block_w - 1) / (int32_t)(series_count - 1);
        if (max_series_gap < 0) {
            max_series_gap = 0;
        }
        if (series_gap > max_series_gap) {
            series_gap = max_series_gap;
        }
    } else {
        series_gap = 0;
    }

    data->bar_group_gap = group_gap;
    data->bar_series_gap = series_gap;
    data->bar_radius = radius;

    lv_obj_set_style_pad_column(chart, group_gap, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_column(chart, series_gap, (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(chart, radius, (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
}

/**
 * 清空图表轴线
 * @param chart Chart 对象指针
 * @param axis 轴线数据
 * @param is_x 是否是 X 轴
 */
static void airui_chart_axis_clear(lv_obj_t *chart, airui_chart_axis_state_t *axis, bool is_x)
{
    (void)is_x;
    if (chart == NULL || axis == NULL) {
        return;
    }

    for (uint32_t i = 0; i < axis->tick_label_count; i++) {
        if (axis->tick_labels[i] != NULL && lv_obj_is_valid(axis->tick_labels[i])) {
            lv_obj_delete(axis->tick_labels[i]);
        }
        axis->tick_labels[i] = NULL;
    }
    axis->tick_label_count = 0;

    if (axis->unit_label != NULL && lv_obj_is_valid(axis->unit_label)) {
        lv_obj_delete(axis->unit_label);
    }
    axis->unit_label = NULL;
}

/**
 * 渲染图表轴线
 * @param chart Chart 对象指针
 * @param axis 轴线数据
 * @param is_x 是否是 X 轴
 */
static void airui_chart_axis_render(lv_obj_t *chart, airui_chart_axis_state_t *axis, bool is_x)
{
    if (chart == NULL || axis == NULL) {
        return;
    }

    lv_obj_update_layout(chart);

    airui_chart_axis_clear(chart, axis, is_x);
    if (!axis->enabled) {
        return;
    }

    lv_obj_t *parent = lv_obj_get_parent(chart);
    if (parent == NULL) {
        return;
    }

    uint32_t tick_count = axis->tick_count;
    if (tick_count < 2) {
        tick_count = 2;
    }
    if (tick_count > AIRUI_CHART_MAX_TICKS) {
        tick_count = AIRUI_CHART_MAX_TICKS;
    }

    int32_t chart_x = lv_obj_get_x(chart);
    int32_t chart_y = lv_obj_get_y(chart);
    int32_t chart_w = lv_obj_get_width(chart);
    int32_t chart_h = lv_obj_get_height(chart);
    int32_t border_w = lv_obj_get_style_border_width(chart, LV_PART_MAIN);
    int32_t pad_l = lv_obj_get_style_pad_left(chart, LV_PART_MAIN);
    int32_t pad_r = lv_obj_get_style_pad_right(chart, LV_PART_MAIN);
    int32_t pad_t = lv_obj_get_style_pad_top(chart, LV_PART_MAIN);
    int32_t pad_b = lv_obj_get_style_pad_bottom(chart, LV_PART_MAIN);
    int32_t plot_x = chart_x + border_w + pad_l;
    int32_t plot_y = chart_y + border_w + pad_t;
    int32_t plot_w = chart_w - (border_w * 2) - pad_l - pad_r;
    int32_t plot_h = chart_h - (border_w * 2) - pad_t - pad_b;
    if (plot_w < 1) {
        plot_w = 1;
    }
    if (plot_h < 1) {
        plot_h = 1;
    }
    int32_t range = axis->max - axis->min;
    int32_t ticks_min_left = 0;
    int32_t ticks_max_right = 0;
    int32_t ticks_min_top = 0;
    int32_t ticks_max_bottom = 0;
    bool ticks_bounds_valid = false;

    for (uint32_t i = 0; i < tick_count; i++) {
        lv_obj_t *label = lv_label_create(parent);
        if (label == NULL) {
            continue;
        }

        int32_t value = axis->min;
        if (tick_count > 1) {
            value = axis->min + (int32_t)((int64_t)range * (int64_t)i / (int64_t)(tick_count - 1));
        }

        char text[32] = {0};
        snprintf(text, sizeof(text), "%ld", (long)value);
        lv_label_set_text(label, text);
        lv_obj_set_style_text_color(label, lv_color_hex(0x6b7280), (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_update_layout(label);

        int32_t label_w = lv_obj_get_width(label);
        int32_t label_h = lv_obj_get_height(label);

        if (is_x) {
            lv_chart_type_t chart_type = lv_chart_get_type(chart);
            int32_t x = 0;
            int32_t label_x = 0;
            int32_t label_y = chart_y + chart_h + 4;
            if (chart_type == LV_CHART_TYPE_BAR || chart_type == LV_CHART_TYPE_STACKED) {
                uint32_t point_count = lv_chart_get_point_count(chart);
                if (point_count < 1) {
                    point_count = 1;
                }
                int32_t block_gap = lv_obj_get_style_pad_column(chart, LV_PART_MAIN);
                int32_t block_w = (plot_w - ((int32_t)(point_count - 1) * block_gap)) / (int32_t)point_count;
                if (block_w < 1) {
                    block_w = 1;
                }
                x = plot_x + block_w / 2 + (int32_t)((int64_t)(plot_w - block_w) * (int64_t)i / (int64_t)(tick_count - 1));
            } else {
                x = plot_x + (int32_t)((int64_t)plot_w * (int64_t)i / (int64_t)(tick_count - 1));
            }
            label_x = x - label_w / 2;
            lv_obj_set_pos(label, label_x, label_y);
            if (!ticks_bounds_valid) {
                ticks_min_left = label_x;
                ticks_max_right = label_x + label_w;
                ticks_min_top = label_y;
                ticks_max_bottom = label_y + label_h;
                ticks_bounds_valid = true;
            } else {
                if (label_x < ticks_min_left) {
                    ticks_min_left = label_x;
                }
                if (label_x + label_w > ticks_max_right) {
                    ticks_max_right = label_x + label_w;
                }
                if (label_y < ticks_min_top) {
                    ticks_min_top = label_y;
                }
                if (label_y + label_h > ticks_max_bottom) {
                    ticks_max_bottom = label_y + label_h;
                }
            }
        } else {
            uint32_t rev = tick_count - 1 - i;
            int32_t y = plot_y + (int32_t)((int64_t)plot_h * (int64_t)rev / (int64_t)(tick_count - 1));
            int32_t label_x = plot_x - label_w - 6;
            int32_t label_y = y - label_h / 2;
            lv_obj_set_pos(label, label_x, label_y);
            if (!ticks_bounds_valid) {
                ticks_min_left = label_x;
                ticks_max_right = label_x + label_w;
                ticks_min_top = label_y;
                ticks_max_bottom = label_y + label_h;
                ticks_bounds_valid = true;
            } else {
                if (label_x < ticks_min_left) {
                    ticks_min_left = label_x;
                }
                if (label_x + label_w > ticks_max_right) {
                    ticks_max_right = label_x + label_w;
                }
                if (label_y < ticks_min_top) {
                    ticks_min_top = label_y;
                }
                if (label_y + label_h > ticks_max_bottom) {
                    ticks_max_bottom = label_y + label_h;
                }
            }
        }

        axis->tick_labels[axis->tick_label_count++] = label;
    }

    if (axis->unit[0] != '\0') {
        axis->unit_label = lv_label_create(parent);
        if (axis->unit_label != NULL) {
            int32_t unit_x = 0;
            int32_t unit_y = 0;
            int32_t unit_w = 0;
            int32_t unit_h = 0;
            int32_t parent_w = lv_obj_get_width(parent);
            int32_t parent_h = lv_obj_get_height(parent);
            lv_label_set_text(axis->unit_label, axis->unit);
            lv_obj_set_style_text_color(axis->unit_label, lv_color_hex(0x374151), (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_update_layout(axis->unit_label);
            unit_w = lv_obj_get_width(axis->unit_label);
            unit_h = lv_obj_get_height(axis->unit_label);
            if (is_x) {
                unit_x = ticks_bounds_valid ? (ticks_max_right + 8) : (plot_x + plot_w + 12);
                unit_y = ticks_bounds_valid ? ticks_min_top : (chart_y + chart_h + 4);
                if (parent_w > 0 && unit_x + unit_w > parent_w) {
                    unit_x = parent_w - unit_w;
                }
                if (unit_x < 0) {
                    unit_x = 0;
                }
                if (parent_h > 0 && unit_y + unit_h > parent_h) {
                    unit_y = parent_h - unit_h;
                }
                if (unit_y < 0) {
                    unit_y = 0;
                }
            } else {
                unit_x = ticks_bounds_valid ? (ticks_max_right + 8) : (plot_x + 8);
                unit_y = ticks_bounds_valid ? ticks_min_top : (plot_y - unit_h + 8);
                if (unit_x < 0) {
                    unit_x = 0;
                }
                if (unit_y < 0) {
                    unit_y = 0;
                }
                if (parent_w > 0 && unit_x + unit_w > parent_w) {
                    unit_x = parent_w - unit_w;
                }
                if (parent_h > 0 && unit_y + unit_h > parent_h) {
                    unit_y = parent_h - unit_h;
                }
            }
            lv_obj_set_pos(axis->unit_label, unit_x, unit_y);
        }
    }
}

/**
 * 渲染x,y轴线
 * @param chart Chart 对象指针
 */
static void airui_chart_axis_render_all(lv_obj_t *chart)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL) {
        return;
    }

    airui_chart_axis_render(chart, &data->axis_x, true);
    airui_chart_axis_render(chart, &data->axis_y, false);
}

/**
 * 清空图表图例
 * @param chart Chart 对象指针
 */
static void airui_chart_legend_clear(lv_obj_t *chart)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL) {
        return;
    }

    if (data->legend_box != NULL && lv_obj_is_valid(data->legend_box)) {
        lv_obj_delete(data->legend_box);
    }
    data->legend_box = NULL;

    for (uint32_t i = 0; i < AIRUI_CHART_MAX_SERIES; i++) {
        data->legend_marks[i] = NULL;
        data->legend_labels[i] = NULL;
    }
}

/**
 * 渲染图表图例
 * @param chart Chart 对象指针
 */
static void airui_chart_legend_render(lv_obj_t *chart)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL) {
        return;
    }

    airui_chart_legend_clear(chart);
    if (!data->legend_enabled || data->series_count == 0) {
        return;
    }

    uint32_t line_h = 18;
    uint32_t legend_h = 6 + data->series_count * line_h;
    uint32_t legend_w = 120;

    lv_obj_t *legend = lv_obj_create(chart);
    if (legend == NULL) {
        return;
    }
    data->legend_box = legend;

    lv_obj_set_size(legend, legend_w, legend_h);
    lv_obj_set_pos(legend, lv_obj_get_width(chart) - (int32_t)legend_w - 30, 8);

    lv_obj_set_style_bg_color(legend, lv_color_hex(0xffffff), (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(legend, 180, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(legend, lv_color_hex(0xcbd5e1), (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(legend, 1, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(legend, 4, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_all(legend, 0, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_move_foreground(legend);

    for (uint32_t i = 0; i < data->series_count; i++) {
        lv_obj_t *mark = lv_obj_create(legend);
        if (mark != NULL) {
            lv_obj_set_size(mark, 10, 10);
            lv_obj_set_pos(mark, 8, 5 + (int32_t)(i * line_h));
            lv_obj_set_style_radius(mark, 2, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(mark, data->series_colors[i], (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(mark, LV_OPA_COVER, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(mark, 0, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
            data->legend_marks[i] = mark;
        }

        lv_obj_t *label = lv_label_create(legend);
        if (label != NULL) {
            lv_label_set_text(label, data->series_names[i]);
            lv_obj_set_pos(label, 24, 2 + (int32_t)(i * line_h));
            lv_obj_set_style_text_color(label, data->series_colors[i], (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
            data->legend_labels[i] = label;
        }
    }
}

/**
 * 清理图表事件回调
 * @param e 事件
 */
static void airui_chart_cleanup_event_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) != LV_EVENT_DELETE) {
        return;
    }

    lv_obj_t *chart = lv_event_get_target(e);
    airui_chart_data_t *data = (airui_chart_data_t *)lv_event_get_user_data(e);
    if (chart == NULL || data == NULL) {
        return;
    }

    airui_chart_axis_clear(chart, &data->axis_x, true);
    airui_chart_axis_clear(chart, &data->axis_y, false);
    if (data->legend_box != NULL && lv_obj_is_valid(data->legend_box)) {
        lv_obj_delete(data->legend_box);
    }
    data->legend_box = NULL;
    luat_heap_free(data);
}

static void airui_chart_overlay_event_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_SIZE_CHANGED && code != LV_EVENT_STYLE_CHANGED) {
        return;
    }

    lv_obj_t *chart = lv_event_get_target(e);
    if (chart == NULL || !lv_obj_is_valid(chart)) {
        return;
    }

    lv_async_call(airui_chart_render_overlays_async, chart);
}

/**
 * 渲染图表轴线和图例
 * @param user_data 用户数据
 */
static void airui_chart_render_overlays_async(void *user_data)
{
    lv_obj_t *chart = (lv_obj_t *)user_data;
    if (chart == NULL || !lv_obj_is_valid(chart)) {
        return;
    }

    lv_obj_update_layout(chart);

    airui_chart_axis_render_all(chart);
    airui_chart_legend_render(chart);
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

    lv_chart_series_t *series = airui_chart_get_series_by_index(chart, 0);
    if (series == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    uint32_t point_count = lv_chart_get_point_count(chart);
    for (uint32_t i = 0; i < point_count; i++) {
        int32_t value = (i < count) ? values[i] : LV_CHART_POINT_NONE;
        lv_chart_set_series_value_by_id(chart, series, i, value);
    }

    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 设置图表数据序列
 * @param chart Chart 对象指针
 * @param series_index 序列索引
 * @param values 数据数组
 * @param count 数据长度
 * @return 0 成功，<0 失败
 */
int airui_chart_set_series_values(lv_obj_t *chart, uint32_t series_index, const int32_t *values, uint32_t count)
{
    if (chart == NULL || values == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_series_t *series = airui_chart_get_series_by_index(chart, series_index);
    if (series == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    uint32_t point_count = lv_chart_get_point_count(chart);
    for (uint32_t i = 0; i < point_count; i++) {
        int32_t value = (i < count) ? values[i] : LV_CHART_POINT_NONE;
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

    lv_chart_series_t *series = airui_chart_get_series_by_index(chart, 0);
    if (series == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_set_next_value(chart, series, value);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 推送图表数据序列
 * @param chart Chart 对象指针
 * @param series_index 序列索引
 * @param value 数据值
 * @return 0 成功，<0 失败
 */
int airui_chart_push_series_value(lv_obj_t *chart, uint32_t series_index, int32_t value)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_series_t *series = airui_chart_get_series_by_index(chart, series_index);
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

    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || data->series_count == 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    for (uint32_t i = 0; i < data->series_count; i++) {
        if (data->series[i] != NULL) {
            lv_chart_set_all_values(chart, data->series[i], value);
        }
    }
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
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data != NULL) {
        data->y_min = min;
        data->y_max = max;
        data->axis_y.min = min;
        data->axis_y.max = max;
        airui_chart_axis_render(chart, &data->axis_y, false);
    }
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
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data != NULL) {
        data->point_count = count;
        data->axis_x.max = (count > 0) ? (int32_t)(count - 1) : 0;
        airui_chart_apply_bar_style(chart, data);
        airui_chart_axis_render(chart, &data->axis_x, true);
    }
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

// 设置图表类型
int airui_chart_set_type(lv_obj_t *chart, lv_chart_type_t type)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (type != LV_CHART_TYPE_LINE && type != LV_CHART_TYPE_BAR && type != LV_CHART_TYPE_STACKED) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_set_type(chart, type);
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data != NULL) {
        data->type = type;
        airui_chart_apply_bar_style(chart, data);
        airui_chart_axis_render(chart, &data->axis_x, true);
    }
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

// 设置图表柱状间距
int airui_chart_set_bar_gap(lv_obj_t *chart, int32_t group_gap, int32_t series_gap)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->bar_group_gap = group_gap;
    data->bar_series_gap = series_gap;
    airui_chart_apply_bar_style(chart, data);
    if (data->type == LV_CHART_TYPE_BAR || data->type == LV_CHART_TYPE_STACKED) {
        airui_chart_axis_render(chart, &data->axis_x, true);
    }
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

// 设置图表柱状圆角
int airui_chart_set_bar_radius(lv_obj_t *chart, int32_t radius)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->bar_radius = radius;
    airui_chart_apply_bar_style(chart, data);
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

    lv_chart_series_t *series = airui_chart_get_series_by_index(chart, 0);
    if (series == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_set_series_color(chart, series, color);
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data != NULL && data->series_count > 0) {
        data->series_colors[0] = color;
        airui_chart_legend_render(chart);
    }
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 设置图表数据序列颜色
 * @param chart Chart 对象指针
 * @param series_index 序列索引
 * @param color 颜色值
 * @return 0 成功，<0 失败
 */
int airui_chart_set_series_color(lv_obj_t *chart, uint32_t series_index, lv_color_t color)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_series_t *series = airui_chart_get_series_by_index(chart, series_index);
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (series == NULL || data == NULL || series_index >= data->series_count) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_set_series_color(chart, series, color);
    data->series_colors[series_index] = color;
    airui_chart_legend_render(chart);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 设置图表数据序列名称
 * @param chart Chart 对象指针
 * @param series_index 序列索引
 * @param name 名称
 * @return 0 成功，<0 失败
 */
int airui_chart_set_series_name(lv_obj_t *chart, uint32_t series_index, const char *name)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || series_index >= data->series_count || name == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    strncpy(data->series_names[series_index], name, AIRUI_CHART_MAX_NAME_LEN);
    data->series_names[series_index][AIRUI_CHART_MAX_NAME_LEN] = '\0';
    airui_chart_legend_render(chart);
    return AIRUI_OK;
}

/**
 * 添加图表数据序列
 * @param chart Chart 对象指针
 * @param color 颜色值
 * @param name 名称
 * @return 0 成功，<0 失败
 */
int airui_chart_add_series(lv_obj_t *chart, lv_color_t color, const char *name)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || data->series_count >= AIRUI_CHART_MAX_SERIES) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_chart_series_t *series = lv_chart_add_series(chart, color, LV_CHART_AXIS_PRIMARY_Y);
    if (series == NULL) {
        return AIRUI_ERR_NO_MEM;
    }

    uint32_t idx = data->series_count;
    data->series[idx] = series;
    data->series_colors[idx] = color;
    if (name != NULL && name[0] != '\0') {
        strncpy(data->series_names[idx], name, AIRUI_CHART_MAX_NAME_LEN);
        data->series_names[idx][AIRUI_CHART_MAX_NAME_LEN] = '\0';
    } else {
        snprintf(data->series_names[idx], AIRUI_CHART_MAX_NAME_LEN + 1, "series-%lu", (unsigned long)(idx + 1));
    }
    data->series_count++;

    lv_chart_set_all_values(chart, series, data->y_min);
    airui_chart_apply_bar_style(chart, data);
    airui_chart_legend_render(chart);
    lv_chart_refresh(chart);
    return (int)(idx + 1);
}

/**
 * 移除最后一个图表数据序列
 * @param chart Chart 对象指针
 * @return 0 成功，<0 失败
 */
int airui_chart_remove_last_series(lv_obj_t *chart)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || data->series_count <= 1) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    uint32_t idx = data->series_count - 1;
    return airui_chart_remove_series(chart, idx);
}

/**
 * 移除图表数据序列
 * @param chart Chart 对象指针
 * @param series_index 序列索引
 * @return 0 成功，<0 失败
 */
int airui_chart_remove_series(lv_obj_t *chart, uint32_t series_index)
{
    if (chart == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || data->series_count <= 1) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    if (series_index == 0 || series_index >= data->series_count) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    uint32_t idx = series_index;
    lv_chart_series_t *series = data->series[idx];
    if (series != NULL) {
        lv_chart_remove_series(chart, series);
    }

    for (uint32_t i = idx; i + 1 < data->series_count; i++) {
        data->series[i] = data->series[i + 1];
        data->series_colors[i] = data->series_colors[i + 1];
        strncpy(data->series_names[i], data->series_names[i + 1], AIRUI_CHART_MAX_NAME_LEN);
        data->series_names[i][AIRUI_CHART_MAX_NAME_LEN] = '\0';
    }

    data->series[data->series_count - 1] = NULL;
    data->series_colors[data->series_count - 1] = lv_color_hex(0x000000);
    data->series_names[data->series_count - 1][0] = '\0';
    data->series_count--;

    airui_chart_apply_bar_style(chart, data);
    airui_chart_legend_render(chart);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}

/**
 * 设置图表轴线配置
 * @param chart Chart 对象指针
 * @param is_x 是否是 X 轴
 * @param enable 是否启用
 * @param min 最小值
 * @param max 最大值
 * @param ticks 刻度数
 * @param unit 单位
 * @return 0 成功，<0 失败
 */
int airui_chart_set_axis_config(lv_obj_t *chart, bool is_x, bool enable, int32_t min, int32_t max, uint32_t ticks, const char *unit)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (chart == NULL || data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_chart_axis_state_t *axis = is_x ? &data->axis_x : &data->axis_y;
    if (max < min) {
        int32_t tmp = min;
        min = max;
        max = tmp;
    }
    axis->enabled = enable;
    axis->min = min;
    axis->max = max;
    axis->tick_count = ticks >= 2 ? ticks : 2;
    if (unit != NULL) {
        strncpy(axis->unit, unit, AIRUI_CHART_MAX_UNIT_LEN);
        axis->unit[AIRUI_CHART_MAX_UNIT_LEN] = '\0';
    } else {
        axis->unit[0] = '\0';
    }

    airui_chart_axis_render(chart, axis, is_x);
    return AIRUI_OK;
}

/**
 * 设置图表图例启用
 * @param chart Chart 对象指针
 * @param enable 是否启用
 * @return 0 成功，<0 失败
 */
int airui_chart_set_legend_enabled(lv_obj_t *chart, bool enable)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (chart == NULL || data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->legend_enabled = enable;
    airui_chart_legend_render(chart);
    return AIRUI_OK;
}
