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
#include "lvgl9/src/core/lv_obj_event.h"
#include "lvgl9/src/draw/lv_draw.h"
#include "lvgl9/src/draw/lv_draw_line.h"
#include "lvgl9/src/draw/lv_draw_rect.h"
#include "lvgl9/src/draw/lv_draw_triangle.h"
#include "lvgl9/src/misc/lv_async.h"
#include "lvgl9/src/misc/lv_color.h"
#include "lvgl9/src/misc/lv_grad.h"
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#define AIRUI_CHART_MAX_SERIES 8
#define AIRUI_CHART_MAX_Y_AXES 4
#define AIRUI_CHART_MAX_NAME_LEN 31
#define AIRUI_CHART_MAX_UNIT_LEN 15
#define AIRUI_CHART_MAX_TICKS 16

/* 图表轴线数据 */
typedef struct {
    bool enabled;
    bool right;
    int32_t offset;
    lv_color_t color;
    int32_t min;
    int32_t max;
    uint32_t tick_count;
    char unit[AIRUI_CHART_MAX_UNIT_LEN + 1];
    lv_obj_t *unit_label;
    lv_obj_t *tick_labels[AIRUI_CHART_MAX_TICKS];
    uint32_t tick_label_count;
} airui_chart_axis_state_t;

/* 曲线下方渐变填充（LVGL lv_example_chart_5 同款 faded area） */
typedef struct {
    bool enabled;
    bool has_color;
    lv_color_t color;
    lv_opa_t opa_start;
    lv_opa_t opa_end;
} airui_chart_fill_state_t;

/* 图表数据 */
typedef struct {
    lv_chart_series_t *series[AIRUI_CHART_MAX_SERIES];
    lv_obj_t *owners[AIRUI_CHART_MAX_SERIES];
    uint8_t series_axes[AIRUI_CHART_MAX_SERIES];
    lv_chart_type_t series_types[AIRUI_CHART_MAX_SERIES];
    bool fill_override[AIRUI_CHART_MAX_SERIES];
    airui_chart_fill_state_t series_fill[AIRUI_CHART_MAX_SERIES];
    lv_obj_t *layers[AIRUI_CHART_MAX_SERIES];
    uint8_t layer_axes[AIRUI_CHART_MAX_SERIES];
    lv_chart_type_t layer_types[AIRUI_CHART_MAX_SERIES];
    bool layer_filled[AIRUI_CHART_MAX_SERIES];
    bool layered;
    lv_chart_update_mode_t update_mode;
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
    airui_chart_axis_state_t axis_y[AIRUI_CHART_MAX_Y_AXES];
    airui_chart_fill_state_t fill;
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
static void airui_chart_parse_fill_config(lua_State *L, int idx, airui_chart_fill_state_t *fill);
static void airui_chart_apply_fill_fade_flag(lv_obj_t *chart, const airui_chart_fill_state_t *fill);
static int32_t airui_chart_get_plot_bottom_y(lv_obj_t *chart);
static void airui_chart_draw_faded_area(lv_event_t *e, const airui_chart_fill_state_t *fill);
static void airui_chart_fill_draw_event_cb(lv_event_t *e);
static void airui_chart_sync_layers(lv_obj_t *chart);
static int airui_chart_enable_layers(lv_obj_t *chart);
static lv_obj_t *airui_chart_get_layer(lv_obj_t *chart, uint32_t axis, lv_chart_type_t type, bool filled);

/* Group columns by axis/type and keep filled lines behind unfilled lines. */
static lv_obj_t *airui_chart_get_layer(lv_obj_t *chart, uint32_t axis, lv_chart_type_t type, bool filled)
{
    filled = type == LV_CHART_TYPE_LINE && filled;
    airui_chart_data_t *data = airui_chart_get_data(chart);
    uint32_t slot = AIRUI_CHART_MAX_SERIES;
    for (uint32_t i = 0; i < AIRUI_CHART_MAX_SERIES; i++) {
        if (data->layers[i] != NULL && data->layer_axes[i] == axis && data->layer_types[i] == type && data->layer_filled[i] == filled) {
            return data->layers[i];
        }
        if (data->layers[i] == NULL) slot = i;
    }
    if (slot == AIRUI_CHART_MAX_SERIES) return NULL;
    lv_obj_t *layer = lv_chart_create(chart);
    if (layer == NULL) return NULL;
    lv_obj_remove_style_all(layer);
    lv_obj_remove_flag(layer, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(layer, LV_OBJ_FLAG_IGNORE_LAYOUT);
    lv_chart_set_type(layer, type);
    lv_chart_set_point_count(layer, data->point_count);
    lv_chart_set_update_mode(layer, data->update_mode);
    lv_chart_set_div_line_count(layer, 0, 0);
    lv_obj_add_flag(layer, LV_OBJ_FLAG_SEND_DRAW_TASK_EVENTS);
    lv_obj_add_event_cb(layer, airui_chart_fill_draw_event_cb, LV_EVENT_DRAW_TASK_ADDED, chart);
    data->layers[slot] = layer;
    data->layer_axes[slot] = (uint8_t)axis;
    data->layer_types[slot] = type;
    data->layer_filled[slot] = filled;
    return layer;
}

static void airui_chart_prune_layers(airui_chart_data_t *data)
{
    for (uint32_t i = 0; i < AIRUI_CHART_MAX_SERIES; i++) {
        if (data->layers[i] != NULL && lv_chart_get_series_next(data->layers[i], NULL) == NULL) {
            lv_obj_delete(data->layers[i]);
            data->layers[i] = NULL;
        }
    }
}

static int airui_chart_move_series(lv_obj_t *chart, uint32_t index, uint32_t axis, lv_chart_type_t type, bool filled)
{
    filled = type == LV_CHART_TYPE_LINE && filled;
    airui_chart_data_t *data = airui_chart_get_data(chart);
    lv_obj_t *old = data->owners[index];
    lv_obj_t *owner = airui_chart_get_layer(chart, axis, type, filled);
    if (owner == old) return AIRUI_OK;
    if (owner == NULL) {
        /* At the eight-layer limit a singleton can change its group in place. */
        if (old != chart && lv_chart_get_series_next(old, NULL) == data->series[index] &&
            lv_chart_get_series_next(old, data->series[index]) == NULL) {
            for (uint32_t i = 0; i < AIRUI_CHART_MAX_SERIES; i++) {
                if (data->layers[i] == old) {
                    data->layer_axes[i] = (uint8_t)axis;
                    data->layer_types[i] = type;
                    data->layer_filled[i] = filled;
                    data->series_axes[index] = (uint8_t)axis;
                    data->series_types[index] = type;
                    lv_chart_set_type(old, type);
                    return AIRUI_OK;
                }
            }
        }
        return AIRUI_ERR_NO_MEM;
    }
    lv_chart_series_t *series = lv_chart_add_series(owner, data->series_colors[index], LV_CHART_AXIS_PRIMARY_Y);
    if (series == NULL) {
        airui_chart_prune_layers(data);
        return AIRUI_ERR_NO_MEM;
    }
    int32_t *src = lv_chart_get_series_y_array(old, data->series[index]);
    int32_t *dst = lv_chart_get_series_y_array(owner, series);
    memcpy(dst, src, data->point_count * sizeof(int32_t));
    lv_chart_set_x_start_point(owner, series, lv_chart_get_x_start_point(old, data->series[index]));
    lv_chart_remove_series(old, data->series[index]);
    data->owners[index] = owner;
    data->series[index] = series;
    data->series_axes[index] = (uint8_t)axis;
    data->series_types[index] = type;
    airui_chart_prune_layers(data);
    return AIRUI_OK;
}

static int airui_chart_enable_layers(lv_obj_t *chart)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    data->layered = true;
    lv_obj_remove_flag(chart, LV_OBJ_FLAG_SCROLLABLE);
    for (uint32_t i = 0; i < data->series_count; i++) {
        if (data->owners[i] == chart) {
            const airui_chart_fill_state_t *fill = data->fill_override[i] ? &data->series_fill[i] : &data->fill;
            int ret = airui_chart_move_series(chart, i, data->series_axes[i], data->series_types[i], fill->enabled);
            if (ret != AIRUI_OK) return ret;
        }
    }
    return AIRUI_OK;
}

static bool airui_chart_has_bars(const airui_chart_data_t *data)
{
    for (uint32_t i = 0; i < data->series_count; i++) {
        if (data->series_types[i] != LV_CHART_TYPE_LINE) return true;
    }
    return false;
}

static int32_t airui_chart_block_width(lv_obj_t *chart, const airui_chart_data_t *data)
{
    int32_t w = lv_obj_get_content_width(chart);
    int64_t block = ((int64_t)w - (int64_t)(data->point_count - 1) * data->bar_group_gap) / data->point_count;
    return block > 0 ? (int32_t)block : 1;
}

static void airui_chart_sync_layers(lv_obj_t *chart)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || !data->layered) return;
    lv_obj_update_layout(chart);
    int32_t w = LV_MAX(lv_obj_get_content_width(chart), 1);
    int32_t h = LV_MAX(lv_obj_get_content_height(chart), 1);
    bool bars = airui_chart_has_bars(data);
    int32_t block = bars ? LV_MIN(airui_chart_block_width(chart, data), w) : 0;
    /* Lines use the same category centers as bars, including odd block widths. */
    for (uint32_t i = 0; i < AIRUI_CHART_MAX_SERIES; i++) {
        lv_obj_t *layer = data->layers[i];
        if (layer == NULL) continue;
        bool line = data->layer_types[i] == LV_CHART_TYPE_LINE;
        lv_obj_set_pos(layer, line ? block / 2 : 0, 0);
        lv_obj_set_size(layer, line ? LV_MAX(w - block, 1) : w, h);
        lv_obj_set_style_line_width(layer, lv_obj_get_style_line_width(chart, LV_PART_ITEMS), LV_PART_ITEMS);
        lv_obj_set_style_size(layer, lv_obj_get_style_width(chart, LV_PART_INDICATOR),
                             lv_obj_get_style_height(chart, LV_PART_INDICATOR), LV_PART_INDICATOR);
        lv_obj_set_style_bg_opa(layer, lv_obj_get_style_bg_opa(chart, LV_PART_INDICATOR), LV_PART_INDICATOR);
        lv_obj_set_style_radius(layer, lv_obj_get_style_radius(chart, LV_PART_INDICATOR), LV_PART_INDICATOR);
        lv_obj_set_style_radius(layer, data->bar_radius, LV_PART_ITEMS);
        lv_obj_set_style_pad_column(layer, data->bar_group_gap, LV_PART_MAIN);
        lv_obj_set_style_pad_column(layer, data->bar_series_gap, LV_PART_ITEMS);
        airui_chart_axis_state_t *axis = &data->axis_y[data->layer_axes[i]];
        lv_chart_set_axis_range(layer, LV_CHART_AXIS_PRIMARY_Y, axis->min, axis->max);
        lv_chart_refresh(layer);
    }
    /* Filled/column layers are behind plain lines, independent of creation order. */
    for (int rank = 0; rank < 3; rank++) {
        for (uint32_t i = 0; i < AIRUI_CHART_MAX_SERIES; i++) {
            lv_obj_t *layer = data->layers[i];
            if (layer == NULL) continue;
            int layer_rank = data->layer_types[i] == LV_CHART_TYPE_LINE ? 2 : 1;
            if (data->layer_filled[i] && layer_rank == 2) layer_rank = 0;
            if (layer_rank == rank) lv_obj_move_foreground(layer);
        }
    }
    if (data->legend_box != NULL) lv_obj_move_foreground(data->legend_box);
}

/** Set one Y axis; changing its range also rescales the associated series. */
int airui_chart_set_y_axis_from_config(lv_obj_t *chart, uint32_t axis_index, void *L, int idx)
{
    lua_State *state = (lua_State *)L;
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || axis_index >= AIRUI_CHART_MAX_Y_AXES || !lua_istable(state, idx)) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    airui_chart_axis_state_t *axis = &data->axis_y[axis_index];
    int32_t min = airui_marshal_integer(L, idx, "min", axis->min);
    int32_t max = airui_marshal_integer(L, idx, "max", axis->max);
    if (min > max) { int32_t tmp = min; min = max; max = tmp; }
    if (min == max) return AIRUI_ERR_INVALID_PARAM;
    const char *side = airui_marshal_string(L, idx, "side", axis->right ? "right" : "left");
    if (strcmp(side, "right") != 0 && strcmp(side, "left") != 0) return AIRUI_ERR_INVALID_PARAM;
    if (axis_index > 0) {
        int ret = airui_chart_enable_layers(chart);
        if (ret != AIRUI_OK) return ret;
    }
    axis->min = min;
    axis->max = max;
    axis->enabled = airui_marshal_bool(L, idx, "enable", true);
    axis->right = strcmp(side, "right") == 0;
    axis->offset = LV_MAX(airui_marshal_integer(L, idx, "offset", axis->offset), 0);
    axis->tick_count = (uint32_t)LV_CLAMP(2, airui_marshal_integer(L, idx, "ticks", (int)axis->tick_count), AIRUI_CHART_MAX_TICKS);
    airui_marshal_color(L, idx, "color", &axis->color);
    const char *unit = airui_marshal_string(L, idx, "unit", axis->unit);
    if (unit != axis->unit) {
        strncpy(axis->unit, unit, AIRUI_CHART_MAX_UNIT_LEN);
        axis->unit[AIRUI_CHART_MAX_UNIT_LEN] = '\0';
    }
    if (axis_index == 0) {
        data->y_min = min;
        data->y_max = max;
        lv_chart_set_axis_range(chart, LV_CHART_AXIS_PRIMARY_Y, min, max);
    }
    airui_chart_sync_layers(chart);
    airui_chart_axis_render(chart, axis, false);
    return AIRUI_OK;
}

/** Configure an existing series without discarding its samples or ring position. */
int airui_chart_set_series_config(lv_obj_t *chart, uint32_t index, void *L, int idx)
{
    lua_State *state = (lua_State *)L;
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || index >= data->series_count || !lua_istable(state, idx)) return AIRUI_ERR_INVALID_PARAM;
    int axis = airui_marshal_integer(L, idx, "y_axis", data->series_axes[index] + 1);
    if (axis < 1 || axis > AIRUI_CHART_MAX_Y_AXES) return AIRUI_ERR_INVALID_PARAM;
    lv_chart_type_t type = data->series_types[index];
    lua_getfield(state, idx, "type");
    if (!lua_isnil(state, -1)) {
        const char *name = lua_tostring(state, -1);
        if (name == NULL || (strcmp(name, "line") && strcmp(name, "bar") && strcmp(name, "stacked"))) {
            lua_pop(state, 1);
            return AIRUI_ERR_INVALID_PARAM;
        }
        type = strcmp(name, "line") == 0 ? LV_CHART_TYPE_LINE :
               strcmp(name, "bar") == 0 ? LV_CHART_TYPE_BAR : LV_CHART_TYPE_STACKED;
    }
    lua_pop(state, 1);
    airui_chart_fill_state_t fill = data->fill_override[index] ? data->series_fill[index] : data->fill;
    bool override = data->fill_override[index];
    lua_getfield(state, idx, "fill");
    if (lua_isboolean(state, -1)) {
        fill.enabled = lua_toboolean(state, -1);
        override = true;
    } else if (lua_istable(state, -1)) {
        fill.enabled = true;
        airui_chart_parse_fill_config(state, lua_gettop(state), &fill);
        override = true;
    } else if (!lua_isnil(state, -1)) {
        lua_pop(state, 1);
        return AIRUI_ERR_INVALID_PARAM;
    }
    lua_pop(state, 1);
    if (data->layered || axis != 1 || type != data->type || override) {
        int ret = airui_chart_enable_layers(chart);
        if (ret != AIRUI_OK) return ret;
        ret = airui_chart_move_series(chart, index, (uint32_t)(axis - 1), type, fill.enabled);
        if (ret != AIRUI_OK) return ret;
    }
    data->fill_override[index] = override;
    data->series_fill[index] = fill;
    /* Per-series overrides must receive draw events even when the global fill is off. */
    lv_obj_add_flag(data->owners[index], LV_OBJ_FLAG_SEND_DRAW_TASK_EVENTS);
    airui_chart_sync_layers(chart);
    airui_chart_axis_render(chart, &data->axis_x, true);
    lv_chart_refresh(data->owners[index]);
    return AIRUI_OK;
}

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
    if (y_max == y_min) {
        return NULL;
    }
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

    chart_data->owners[0] = chart;
    chart_data->series_types[0] = chart_type;
    chart_data->update_mode = airui_chart_parse_update_mode(L_state, idx);
    chart_data->axis_x.color = lv_color_hex(0x6b7280);
    for (uint32_t i = 0; i < AIRUI_CHART_MAX_Y_AXES; i++) {
        chart_data->axis_y[i].min = y_min;
        chart_data->axis_y[i].max = y_max;
        chart_data->axis_y[i].tick_count = 5;
        chart_data->axis_y[i].color = lv_color_hex(0x6b7280);
        chart_data->axis_y[i].right = i > 0;
        chart_data->axis_y[i].offset = i > 0 ? (int32_t)(i - 1) * 64 : 0;
    }
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
    chart_data->axis_y[0].min = y_min;
    chart_data->axis_y[0].max = y_max;
    chart_data->axis_y[0].tick_count = (hdiv > 1) ? hdiv : 2;

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

    chart_data->fill.opa_start = LV_OPA_COVER;
    chart_data->fill.opa_end = LV_OPA_TRANSP;

    lua_getfield(L_state, idx, "fill_fade");
    if (lua_type(L_state, -1) == LUA_TBOOLEAN) {
        chart_data->fill.enabled = lua_toboolean(L_state, -1);
    }
    lua_pop(L_state, 1);

    lua_getfield(L_state, idx, "fill");
    if (lua_istable(L_state, -1)) {
        airui_chart_parse_fill_config(L_state, lua_gettop(L_state), &chart_data->fill);
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
    lv_obj_add_event_cb(chart, airui_chart_fill_draw_event_cb, LV_EVENT_DRAW_TASK_ADDED, chart);
    airui_chart_apply_fill_fade_flag(chart, &chart_data->fill);

    lua_getfield(L_state, idx, "y_axis");
    int axis_result = AIRUI_OK;
    if (lua_istable(L_state, -1)) {
        axis_result = airui_chart_set_y_axis_from_config(chart, 0, L_state, lua_gettop(L_state));
    }
    lua_pop(L_state, 1);
    lua_getfield(L_state, idx, "y_axes");
    if (lua_istable(L_state, -1)) {
        size_t count = lua_rawlen(L_state, -1);
        if (count > AIRUI_CHART_MAX_Y_AXES) {
            axis_result = AIRUI_ERR_INVALID_PARAM;
        }
        for (size_t i = 0; i < count && axis_result == AIRUI_OK; i++) {
            lua_rawgeti(L_state, -1, (lua_Integer)i + 1);
            axis_result = airui_chart_set_y_axis_from_config(chart, (uint32_t)i, L_state, lua_gettop(L_state));
            lua_pop(L_state, 1);
        }
    }
    lua_pop(L_state, 1);
    if (axis_result != AIRUI_OK) {
        lv_obj_delete(chart);
        return NULL;
    }
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

    /* Setting even an unchanged layout style emits STYLE_CHANGED in LVGL. */
    if (lv_obj_get_style_pad_column(chart, LV_PART_MAIN) != group_gap) {
        lv_obj_set_style_pad_column(chart, group_gap, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (lv_obj_get_style_pad_column(chart, LV_PART_ITEMS) != series_gap) {
        lv_obj_set_style_pad_column(chart, series_gap, (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
    }
    if (lv_obj_get_style_radius(chart, LV_PART_ITEMS) != radius) {
        lv_obj_set_style_radius(chart, radius, (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
    }
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
    int64_t range = (int64_t)axis->max - axis->min;
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
        lv_obj_set_style_text_color(label, axis->color, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_update_layout(label);

        int32_t label_w = lv_obj_get_width(label);
        int32_t label_h = lv_obj_get_height(label);

        if (is_x) {
            lv_chart_type_t chart_type = lv_chart_get_type(chart);
            int32_t x = 0;
            int32_t label_x = 0;
            int32_t label_y = chart_y + chart_h + 4;
            airui_chart_data_t *data = airui_chart_get_data(chart);
            if (data->layered ? airui_chart_has_bars(data) :
                (chart_type == LV_CHART_TYPE_BAR || chart_type == LV_CHART_TYPE_STACKED)) {
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
            int32_t label_x = axis->right ? plot_x + plot_w + 6 + axis->offset
                                          : plot_x - label_w - 6 - axis->offset;
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
            lv_obj_set_style_text_color(axis->unit_label, axis->color, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
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
                unit_x = axis->right ? plot_x + plot_w + 6 + axis->offset
                                     : plot_x - unit_w - 6 - axis->offset;
                unit_y = plot_y - unit_h - 8;
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
    for (uint32_t i = 0; i < AIRUI_CHART_MAX_Y_AXES; i++) {
        airui_chart_axis_render(chart, &data->axis_y[i], false);
    }
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
 * 从 Lua 表解析曲线下方渐变填充配置
 */
static void airui_chart_parse_fill_config(lua_State *L, int idx, airui_chart_fill_state_t *fill)
{
    if (L == NULL || fill == NULL) {
        return;
    }

    lua_getfield(L, idx, "enable");
    if (lua_type(L, -1) == LUA_TBOOLEAN) {
        fill->enabled = lua_toboolean(L, -1);
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "color");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        fill->color = lv_color_hex((uint32_t)lua_tointeger(L, -1));
        fill->has_color = true;
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "opa_start");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        fill->opa_start = airui_marshal_opacity((int)lua_tointeger(L, -1));
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "opa_end");
    if (lua_type(L, -1) == LUA_TNUMBER) {
        fill->opa_end = airui_marshal_opacity((int)lua_tointeger(L, -1));
    }
    lua_pop(L, 1);
}

/**
 * 按配置开关 chart 的 DRAW_TASK 事件（渐变填充依赖）
 */
static void airui_chart_apply_fill_fade_flag(lv_obj_t *chart, const airui_chart_fill_state_t *fill)
{
    if (chart == NULL || fill == NULL) {
        return;
    }

    if (fill->enabled) {
        lv_obj_add_flag(chart, LV_OBJ_FLAG_SEND_DRAW_TASK_EVENTS);
    }
    else {
        lv_obj_remove_flag(chart, LV_OBJ_FLAG_SEND_DRAW_TASK_EVENTS);
    }
}

/**
 * 绘图区底部 Y 坐标（屏幕坐标）
 */
static int32_t airui_chart_get_plot_bottom_y(lv_obj_t *chart)
{
    if (chart == NULL) {
        return 0;
    }

    lv_area_t coords;
    lv_obj_get_coords(chart, &coords);

    int32_t border_width = lv_obj_get_style_border_width(chart, LV_PART_MAIN);
    int32_t pad_top = lv_obj_get_style_pad_top(chart, LV_PART_MAIN) + border_width;
    int32_t h = lv_obj_get_content_height(chart);
    int32_t y_ofs = coords.y1 + pad_top - lv_obj_get_scroll_top(chart);
    return y_ofs + h;
}

/**
 * 为单段曲线绘制下方渐变三角形 + 矩形（参考 LVGL lv_example_chart_5）
 */
static void airui_chart_draw_faded_area(lv_event_t *e, const airui_chart_fill_state_t *fill)
{
    lv_obj_t *obj = lv_event_get_target_obj(e);
    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    lv_draw_task_t *draw_task = lv_event_get_draw_task(e);
    lv_draw_dsc_base_t *base_dsc = (lv_draw_dsc_base_t *)lv_draw_task_get_draw_dsc(draw_task);
    lv_draw_line_dsc_t *draw_line_dsc = lv_draw_task_get_line_dsc(draw_task);
    if (base_dsc == NULL || draw_line_dsc == NULL || base_dsc->layer == NULL) {
        return;
    }

    lv_color_t fill_color = draw_line_dsc->color;
    if (fill != NULL && fill->has_color) {
        fill_color = fill->color;
    }

    lv_opa_t opa_start = (fill != NULL) ? fill->opa_start : LV_OPA_COVER;
    lv_opa_t opa_end = (fill != NULL) ? fill->opa_end : LV_OPA_TRANSP;

    lv_draw_triangle_dsc_t tri_dsc;
    lv_draw_triangle_dsc_init(&tri_dsc);
    tri_dsc.p[0].x = draw_line_dsc->p1.x;
    tri_dsc.p[0].y = draw_line_dsc->p1.y;
    tri_dsc.p[1].x = draw_line_dsc->p2.x;
    tri_dsc.p[1].y = draw_line_dsc->p2.y;
    tri_dsc.p[2].x = draw_line_dsc->p1.y < draw_line_dsc->p2.y ? draw_line_dsc->p1.x : draw_line_dsc->p2.x;
    tri_dsc.p[2].y = LV_MAX(draw_line_dsc->p1.y, draw_line_dsc->p2.y);
    tri_dsc.grad.dir = LV_GRAD_DIR_VER;
    tri_dsc.grad.stops_count = 2;

    int32_t full_h = lv_obj_get_height(obj);
    if (full_h < 1) {
        full_h = 1;
    }

    int32_t fract_upper = (int32_t)(LV_MIN(draw_line_dsc->p1.y, draw_line_dsc->p2.y) - coords.y1) * 255 / full_h;
    int32_t fract_lower = (int32_t)(LV_MAX(draw_line_dsc->p1.y, draw_line_dsc->p2.y) - coords.y1) * 255 / full_h;
    if (fract_upper < 0) {
        fract_upper = 0;
    }
    if (fract_upper > 255) {
        fract_upper = 255;
    }
    if (fract_lower < 0) {
        fract_lower = 0;
    }
    if (fract_lower > 255) {
        fract_lower = 255;
    }

    tri_dsc.grad.stops[0].color = fill_color;
    tri_dsc.grad.stops[0].opa = (lv_opa_t)((255 - fract_upper) * opa_start / 255);
    tri_dsc.grad.stops[0].frac = 0;
    tri_dsc.grad.stops[1].color = fill_color;
    tri_dsc.grad.stops[1].opa = (lv_opa_t)((255 - fract_lower) * opa_start / 255);
    tri_dsc.grad.stops[1].frac = 255;

    lv_draw_triangle(base_dsc->layer, &tri_dsc);

    lv_draw_rect_dsc_t rect_dsc;
    lv_draw_rect_dsc_init(&rect_dsc);
    rect_dsc.bg_grad.dir = LV_GRAD_DIR_VER;
    rect_dsc.bg_grad.stops_count = 2;
    rect_dsc.bg_grad.stops[0].color = fill_color;
    rect_dsc.bg_grad.stops[0].frac = 0;
    rect_dsc.bg_grad.stops[0].opa = (lv_opa_t)((255 - fract_lower) * opa_start / 255);
    rect_dsc.bg_grad.stops[1].color = fill_color;
    rect_dsc.bg_grad.stops[1].frac = 255;
    rect_dsc.bg_grad.stops[1].opa = opa_end;
    rect_dsc.bg_opa = LV_OPA_COVER;
    rect_dsc.border_opa = LV_OPA_TRANSP;

    lv_area_t rect_area;
    rect_area.x1 = (int32_t)draw_line_dsc->p1.x;
    rect_area.x2 = (int32_t)draw_line_dsc->p2.x - 1;
    rect_area.y1 = (int32_t)LV_MAX(draw_line_dsc->p1.y, draw_line_dsc->p2.y);
    rect_area.y2 = airui_chart_get_plot_bottom_y(obj);
    if (rect_area.y2 < rect_area.y1) {
        rect_area.y2 = rect_area.y1;
    }

    lv_draw_rect(base_dsc->layer, &rect_dsc, &rect_area);
}

/**
 * 曲线渐变填充绘制事件
 */
static void airui_chart_fill_draw_event_cb(lv_event_t *e)
{
    lv_obj_t *owner = lv_event_get_target_obj(e);
    lv_obj_t *chart = (lv_obj_t *)lv_event_get_user_data(e);
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL || lv_chart_get_type(owner) != LV_CHART_TYPE_LINE) {
        return;
    }
    lv_draw_task_t *task = lv_event_get_draw_task(e);
    if (task == NULL || lv_draw_task_get_type(task) != LV_DRAW_TASK_TYPE_LINE) {
        return;
    }
    lv_draw_dsc_base_t *base = (lv_draw_dsc_base_t *)lv_draw_task_get_draw_dsc(task);
    if (base == NULL || base->part != LV_PART_ITEMS) {
        return;
    }
    lv_chart_series_t *series = NULL;
    for (uint32_t n = 0; n <= base->id1; n++) {
        series = lv_chart_get_series_next(owner, series);
        if (series == NULL) return;
    }
    for (uint32_t i = 0; i < data->series_count; i++) {
        if (data->series[i] == series) {
            const airui_chart_fill_state_t *fill = data->fill_override[i] ? &data->series_fill[i] : &data->fill;
            if (fill->enabled) airui_chart_draw_faded_area(e, fill);
            return;
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
    lv_async_call_cancel(airui_chart_render_overlays_async, chart);
    for (uint32_t i = 0; i < AIRUI_CHART_MAX_SERIES; i++) {
        if (data->layers[i] != NULL) {
            lv_obj_delete(data->layers[i]);
            data->layers[i] = NULL;
        }
    }
    for (uint32_t i = 0; i < AIRUI_CHART_MAX_Y_AXES; i++) {
        airui_chart_axis_clear(chart, &data->axis_y[i], false);
    }
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

    lv_async_call_cancel(airui_chart_render_overlays_async, chart);
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

    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data == NULL) return;
    airui_chart_apply_bar_style(chart, data);
    airui_chart_sync_layers(chart);
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
        lv_chart_set_series_value_by_id(airui_chart_get_data(chart)->owners[0], series, i, value);
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
        lv_chart_set_series_value_by_id(airui_chart_get_data(chart)->owners[series_index], series, i, value);
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

    lv_chart_set_next_value(airui_chart_get_data(chart)->owners[0], series, value);
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

    lv_chart_set_next_value(airui_chart_get_data(chart)->owners[series_index], series, value);
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
            lv_chart_set_all_values(data->owners[i], data->series[i], value);
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

    if (max == min) return AIRUI_ERR_INVALID_PARAM;
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
        data->axis_y[0].min = min;
        data->axis_y[0].max = max;
        airui_chart_axis_render(chart, &data->axis_y[0], false);
    }
    airui_chart_sync_layers(chart);
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
        for (uint32_t i = 0; i < AIRUI_CHART_MAX_SERIES; i++) {
            if (data->layers[i] != NULL) lv_chart_set_point_count(data->layers[i], count);
        }
        data->point_count = count;
        data->axis_x.max = (count > 0) ? (int32_t)(count - 1) : 0;
        airui_chart_apply_bar_style(chart, data);
        airui_chart_sync_layers(chart);
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
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (data != NULL) {
        data->update_mode = mode;
        for (uint32_t i = 0; i < AIRUI_CHART_MAX_SERIES; i++) {
            if (data->layers[i] != NULL) lv_chart_set_update_mode(data->layers[i], mode);
        }
    }
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
        if (data->layered) {
            for (uint32_t i = 0; i < data->series_count; i++) {
                const airui_chart_fill_state_t *fill = data->fill_override[i] ? &data->series_fill[i] : &data->fill;
                int ret = airui_chart_move_series(chart, i, data->series_axes[i], type, fill->enabled);
                if (ret != AIRUI_OK) return ret;
            }
        } else {
            for (uint32_t i = 0; i < data->series_count; i++) data->series_types[i] = type;
        }
        data->type = type;
        airui_chart_apply_bar_style(chart, data);
        airui_chart_sync_layers(chart);
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
    airui_chart_sync_layers(chart);
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
    airui_chart_sync_layers(chart);
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

    lv_chart_set_series_color(airui_chart_get_data(chart)->owners[0], series, color);
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

    lv_chart_set_series_color(data->owners[series_index], series, color);
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

    lv_obj_t *owner = data->layered ? airui_chart_get_layer(chart, 0, data->type, data->fill.enabled) : chart;
    if (owner == NULL) return AIRUI_ERR_NO_MEM;
    lv_chart_series_t *series = lv_chart_add_series(owner, color, LV_CHART_AXIS_PRIMARY_Y);
    if (series == NULL) {
        return AIRUI_ERR_NO_MEM;
    }

    uint32_t idx = data->series_count;
    data->owners[idx] = owner;
    data->series_axes[idx] = 0;
    data->series_types[idx] = data->type;
    data->fill_override[idx] = false;
    data->series[idx] = series;
    data->series_colors[idx] = color;
    if (name != NULL && name[0] != '\0') {
        strncpy(data->series_names[idx], name, AIRUI_CHART_MAX_NAME_LEN);
        data->series_names[idx][AIRUI_CHART_MAX_NAME_LEN] = '\0';
    } else {
        snprintf(data->series_names[idx], AIRUI_CHART_MAX_NAME_LEN + 1, "series-%lu", (unsigned long)(idx + 1));
    }
    data->series_count++;

    lv_chart_set_all_values(owner, series, data->y_min);
    airui_chart_apply_bar_style(chart, data);
    airui_chart_sync_layers(chart);
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
        lv_chart_remove_series(data->owners[idx], series);
    }

    for (uint32_t i = idx; i + 1 < data->series_count; i++) {
        data->owners[i] = data->owners[i + 1];
        data->series_axes[i] = data->series_axes[i + 1];
        data->series_types[i] = data->series_types[i + 1];
        data->fill_override[i] = data->fill_override[i + 1];
        data->series_fill[i] = data->series_fill[i + 1];
        data->series[i] = data->series[i + 1];
        data->series_colors[i] = data->series_colors[i + 1];
        strncpy(data->series_names[i], data->series_names[i + 1], AIRUI_CHART_MAX_NAME_LEN);
        data->series_names[i][AIRUI_CHART_MAX_NAME_LEN] = '\0';
    }

    data->series[data->series_count - 1] = NULL;
    data->series_colors[data->series_count - 1] = lv_color_hex(0x000000);
    data->series_names[data->series_count - 1][0] = '\0';
    data->owners[data->series_count - 1] = NULL;
    data->series_count--;
    airui_chart_prune_layers(data);

    airui_chart_apply_bar_style(chart, data);
    airui_chart_sync_layers(chart);
    airui_chart_axis_render(chart, &data->axis_x, true);
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

    airui_chart_axis_state_t *axis = is_x ? &data->axis_x : &data->axis_y[0];
    if (!is_x && max == min) return AIRUI_ERR_INVALID_PARAM;
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

    if (!is_x) {
        data->y_min = min;
        data->y_max = max;
        lv_chart_set_axis_range(chart, LV_CHART_AXIS_PRIMARY_Y, min, max);
        airui_chart_sync_layers(chart);
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

/**
 * 开关曲线下方渐变填充
 */
int airui_chart_set_fill_fade(lv_obj_t *chart, bool enable, const lv_color_t *color, int opa_start, int opa_end)
{
    airui_chart_data_t *data = airui_chart_get_data(chart);
    if (chart == NULL || data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->fill.enabled = enable;
    if (color != NULL) {
        data->fill.color = *color;
        data->fill.has_color = true;
    }
    else if (!enable) {
        data->fill.has_color = false;
    }

    if (opa_start >= 0) {
        data->fill.opa_start = airui_marshal_opacity(opa_start);
    }
    if (opa_end >= 0) {
        data->fill.opa_end = airui_marshal_opacity(opa_end);
    }

    if (data->layered) {
        for (uint32_t i = 0; i < data->series_count; i++) {
            const airui_chart_fill_state_t *fill = data->fill_override[i] ? &data->series_fill[i] : &data->fill;
            int ret = airui_chart_move_series(chart, i, data->series_axes[i], data->series_types[i], fill->enabled);
            if (ret != AIRUI_OK) return ret;
        }
    }
    lv_obj_add_flag(chart, LV_OBJ_FLAG_SEND_DRAW_TASK_EVENTS);
    airui_chart_sync_layers(chart);
    lv_chart_refresh(chart);
    return AIRUI_OK;
}
