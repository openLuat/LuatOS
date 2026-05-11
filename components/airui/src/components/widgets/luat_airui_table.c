/**
 * @file luat_airui_table.c
 * @summary Table 组件实现
 * @responsible Table 创建与基础列/单元格 API
 */

#include "luat_airui_component.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/draw/lv_draw_rect.h"
#include "lvgl9/src/draw/lv_draw_label.h"
#include "lvgl9/src/draw/lv_draw_private.h"
#include "lvgl9/src/core/lv_obj_scroll.h"
#include "lvgl9/src/widgets/table/lv_table.h"
#include "lvgl9/src/widgets/table/lv_table_private.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_timer.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_malloc.h"
#include <stdint.h>
#include <string.h>

typedef struct {
    bool has_bg_color;
    lv_color_t bg_color;
    bool has_border_color;
    lv_color_t border_color;
    bool has_text_color;
    lv_color_t text_color;
} airui_table_cell_style_t;

typedef enum {
    AIRUI_TABLE_CELL_VERTICAL_ALIGN_CENTER = 0,
    AIRUI_TABLE_CELL_VERTICAL_ALIGN_TOP
} airui_table_cell_vertical_align_t;

typedef struct {
    lv_coord_t *row_heights;
    uint16_t row_count;
    airui_table_cell_style_t *row_styles;
    uint16_t row_style_count;
    airui_table_cell_style_t *col_styles;
    uint16_t col_style_count;
    lv_timer_t *jump_scroll_timer;
    uint32_t jump_scroll_interval;
    uint16_t jump_scroll_current_row;
    uint16_t jump_scroll_focus_col;
    uint16_t jump_scroll_step;
    bool jump_scroll_loop;
    bool jump_scroll_anim;
    bool jump_scroll_running;
    bool jump_scroll_paused;
    lv_timer_t *marquee_scroll_timer;
    uint32_t marquee_scroll_interval;
    uint16_t marquee_scroll_speed;
    bool marquee_scroll_loop;
    bool marquee_scroll_running;
    bool marquee_scroll_paused;
    uint16_t cell_font_size;
    uint8_t cell_vertical_align;
} airui_table_data_t;

static void airui_table_apply_row_height(lv_obj_t *table, uint32_t row, lv_coord_t height);
static void airui_table_jump_scroll_select_cell(lv_obj_t *table, uint32_t row, uint32_t col);
static void airui_table_jump_scroll_stop_internal(lv_obj_t *table, bool reset_position);
static void airui_table_jump_scroll_timer_cb(lv_timer_t *timer);
static void airui_table_apply_data(lua_State *L_state, int idx, lv_obj_t *table, int *rows, int *cols);
static void airui_table_apply_col_widths(lua_State *L_state, int idx, lv_obj_t *table, int cols);
static void airui_table_apply_row_heights(lua_State *L_state, int idx, lv_obj_t *table, int rows);
static void airui_table_scroll_row_into_view(lv_obj_t *table, uint32_t row, bool animated);
static void airui_table_shift_cached_row_heights(airui_table_data_t *data, uint32_t index, int32_t delta);
static void airui_table_marquee_scroll_stop_internal(lv_obj_t *table, bool reset_position);
static void airui_table_marquee_scroll_timer_cb(lv_timer_t *timer);
static void airui_table_reapply_row_heights(lv_obj_t *table);
static lv_coord_t airui_table_normalize_row_height(lv_coord_t height);
static void airui_table_sync_size(lv_obj_t *table, int rows, int cols);
static void airui_table_style_event_cb(lv_event_t *e);
static void airui_table_draw_task_added_event_cb(lv_event_t *e);
static int airui_table_ensure_cell_style_capacity(airui_table_cell_style_t **styles, uint16_t *count, uint32_t target_count);
static void airui_table_shift_cell_style_rules(airui_table_cell_style_t **styles, uint16_t *count, uint32_t index, int32_t delta);
static airui_table_cell_style_t *airui_table_get_cell_style_slot(lv_obj_t *table, bool is_row, uint32_t index, bool create);
static void airui_table_adjust_after_structure_change(lv_obj_t *table, bool row_axis, uint32_t index, uint32_t remove_count);
static void airui_table_clamp_selection(lv_obj_t *table);

static airui_table_cell_vertical_align_t airui_table_parse_vertical_align(lua_State *L_state, int idx,
                                                                          const char *field,
                                                                          airui_table_cell_vertical_align_t def)
{
    lua_getfield(L_state, idx, field);
    if (lua_type(L_state, -1) == LUA_TSTRING) {
        const char *value = lua_tostring(L_state, -1);
        if (value != NULL && strcmp(value, "top") == 0) {
            lua_pop(L_state, 1);
            return AIRUI_TABLE_CELL_VERTICAL_ALIGN_TOP;
        }
        if (value != NULL && strcmp(value, "center") == 0) {
            lua_pop(L_state, 1);
            return AIRUI_TABLE_CELL_VERTICAL_ALIGN_CENTER;
        }
    }
    lua_pop(L_state, 1);
    return def;
}

/**
 * 通过 config 表创建 Table 组件
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return 创建成功返回 Table 对象指针，失败返回 NULL
 */
lv_obj_t *airui_table_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);

    if (ctx == NULL) {
        return NULL;
    }

    // 读取配置项
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_floor_integer(L, idx, "x", 0);
    int y = airui_marshal_floor_integer(L, idx, "y", 0);
    int w = airui_marshal_floor_integer(L, idx, "w", 200);
    int h = airui_marshal_floor_integer(L, idx, "h", 120);
    int rows = airui_marshal_integer(L, idx, "rows", 4);
    int cols = airui_marshal_integer(L, idx, "cols", 3);
    if (rows < 1) rows = 1;
    if (cols < 1) cols = 1;

    lv_obj_t *table = lv_table_create(parent);
    if (table == NULL) {
        return NULL;
    }

    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, table, AIRUI_COMPONENT_TABLE);
    if (meta == NULL) {
        lv_obj_delete(table);
        return NULL;
    }

    // 设置 Table 的位置与尺寸
    lv_obj_set_pos(table, x, y);
    lv_obj_set_size(table, w, h);
    // 默认 padding 与边框
    lv_obj_set_style_pad_all(table, 6, ((lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT));
    lv_obj_set_style_border_width(table, 1, ((lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT));
    // 设置边框颜色
    lv_color_t border_color;
    if (airui_marshal_color(L_state, idx, "border_color", &border_color)) {
        lv_obj_set_style_border_color(table, border_color, ((lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT));
    }

    lua_getfield(L_state, idx, "style");
    if (lua_type(L_state, -1) == LUA_TTABLE) {
        airui_table_set_style(table, L_state, lua_gettop(L_state));
    }
    lua_pop(L_state, 1);

    lv_obj_add_event_cb(table, airui_table_style_event_cb, LV_EVENT_STYLE_CHANGED, NULL);
    lv_obj_add_event_cb(table, airui_table_draw_task_added_event_cb, LV_EVENT_DRAW_TASK_ADDED, NULL);
    lv_obj_add_flag(table, LV_OBJ_FLAG_SEND_DRAW_TASK_EVENTS);

    airui_table_sync_size(table, rows, cols);

    airui_table_apply_data(L_state, idx, table, &rows, &cols);
    airui_table_sync_size(table, rows, cols);

    airui_table_apply_col_widths(L_state, idx, table, cols);

    airui_table_apply_row_heights(L_state, idx, table, rows);

    int callback_ref = airui_component_capture_callback(L, idx, "on_click");
    if (callback_ref != LUA_NOREF) {
        airui_component_bind_event(meta, AIRUI_EVENT_VALUE_CHANGED, callback_ref);
    }

    LV_UNUSED(meta);

    return table;
}

// 释放表数据
static void airui_table_release_data(void *user_data)
{
    airui_table_data_t *data = (airui_table_data_t *)user_data;
    if (data == NULL) {
        return;
    }

    if (data->row_heights != NULL) {
        luat_heap_free(data->row_heights);
    }
    if (data->row_styles != NULL) {
        luat_heap_free(data->row_styles);
    }
    if (data->col_styles != NULL) {
        luat_heap_free(data->col_styles);
    }
    if (data->jump_scroll_timer != NULL) {
        lv_timer_delete(data->jump_scroll_timer);
        data->jump_scroll_timer = NULL;
    }
    if (data->marquee_scroll_timer != NULL) {
        lv_timer_delete(data->marquee_scroll_timer);
        data->marquee_scroll_timer = NULL;
    }
    luat_heap_free(data);
}

// 获取表数据
static airui_table_data_t *airui_table_get_data(lv_obj_t *table)
{
    airui_component_meta_t *meta = airui_component_meta_get(table);
    if (meta == NULL) {
        return NULL;
    }
    return (airui_table_data_t *)meta->user_data;
}

static airui_table_data_t *airui_table_ensure_data(lv_obj_t *table)
{
    airui_table_data_t *data = airui_table_get_data(table);
    if (data != NULL) {
        return data;
    }

    airui_component_meta_t *meta = airui_component_meta_get(table);
    if (meta == NULL) {
        return NULL;
    }

    data = (airui_table_data_t *)luat_heap_malloc(sizeof(airui_table_data_t));
    if (data == NULL) {
        return NULL;
    }
    memset(data, 0, sizeof(airui_table_data_t));
    airui_component_meta_set_user_data(meta, data, airui_table_release_data);
    return data;
}

// 存储行高
static int airui_table_store_row_height(lv_obj_t *table, uint32_t row, lv_coord_t height)
{
    airui_table_data_t *data = airui_table_ensure_data(table);
    if (data == NULL) {
        return AIRUI_ERR_NO_MEM;
    }

    height = airui_table_normalize_row_height(height);

    if (row >= data->row_count) {
        uint32_t new_count = row + 1;
        lv_coord_t *new_heights = (lv_coord_t *)luat_heap_malloc(sizeof(lv_coord_t) * new_count);
        if (new_heights == NULL) {
            return AIRUI_ERR_NO_MEM;
        }
        memset(new_heights, 0, sizeof(lv_coord_t) * new_count);
        if (data->row_heights != NULL) {
            memcpy(new_heights, data->row_heights, sizeof(lv_coord_t) * data->row_count);
            luat_heap_free(data->row_heights);
        }
        data->row_heights = new_heights;
        data->row_count = (uint16_t)new_count;
    }

    data->row_heights[row] = height;
    return AIRUI_OK;
}

// 缓存行高
static void airui_table_shift_cached_row_heights(airui_table_data_t *data, uint32_t index, int32_t delta)
{
    if (data == NULL || delta == 0) {
        return;
    }

    if (delta > 0) {
        uint32_t step = (uint32_t)delta;
        uint32_t old_count = data->row_count;
        uint32_t new_count = old_count + step;
        lv_coord_t *new_heights = (lv_coord_t *)luat_heap_malloc(sizeof(lv_coord_t) * new_count);
        if (new_heights == NULL) {
            return;
        }
        memset(new_heights, 0, sizeof(lv_coord_t) * new_count);

        if (data->row_heights != NULL && old_count > 0) {
            if (index > old_count) {
                index = old_count;
            }
            if (index > 0) {
                memcpy(new_heights, data->row_heights, sizeof(lv_coord_t) * index);
            }
            if (index < old_count) {
                memcpy(new_heights + index + step,
                       data->row_heights + index,
                       sizeof(lv_coord_t) * (old_count - index));
            }
            luat_heap_free(data->row_heights);
        }

        data->row_heights = new_heights;
        data->row_count = (uint16_t)new_count;
        return;
    }

    if (data->row_heights == NULL || data->row_count == 0) {
        return;
    }

    uint32_t remove_count = (uint32_t)(-delta);
    if (index >= data->row_count) {
        return;
    }
    if (index + remove_count > data->row_count) {
        remove_count = data->row_count - index;
    }
    if (remove_count == 0) {
        return;
    }

    memmove(data->row_heights + index,
            data->row_heights + index + remove_count,
            sizeof(lv_coord_t) * (data->row_count - index - remove_count));

    data->row_count = (uint16_t)(data->row_count - remove_count);
    if (data->row_count == 0) {
        luat_heap_free(data->row_heights);
        data->row_heights = NULL;
        return;
    }

    lv_coord_t *new_heights = (lv_coord_t *)luat_heap_malloc(sizeof(lv_coord_t) * data->row_count);
    if (new_heights == NULL) {
        return;
    }
    memcpy(new_heights, data->row_heights, sizeof(lv_coord_t) * data->row_count);
    luat_heap_free(data->row_heights);
    data->row_heights = new_heights;
}

static int airui_table_ensure_cell_style_capacity(airui_table_cell_style_t **styles, uint16_t *count, uint32_t target_count)
{
    if (styles == NULL || count == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (target_count <= *count) {
        return AIRUI_OK;
    }

    airui_table_cell_style_t *new_styles = (airui_table_cell_style_t *)luat_heap_malloc(sizeof(airui_table_cell_style_t) * target_count);
    if (new_styles == NULL) {
        return AIRUI_ERR_NO_MEM;
    }

    memset(new_styles, 0, sizeof(airui_table_cell_style_t) * target_count);
    if (*styles != NULL && *count > 0) {
        memcpy(new_styles, *styles, sizeof(airui_table_cell_style_t) * (*count));
        luat_heap_free(*styles);
    }

    *styles = new_styles;
    *count = (uint16_t)target_count;
    return AIRUI_OK;
}

static void airui_table_shift_cell_style_rules(airui_table_cell_style_t **styles, uint16_t *count, uint32_t index, int32_t delta)
{
    if (styles == NULL || count == NULL || delta == 0) {
        return;
    }

    if (delta > 0) {
        uint32_t old_count = *count;
        uint32_t new_count = old_count + (uint32_t)delta;
        if (airui_table_ensure_cell_style_capacity(styles, count, new_count) != AIRUI_OK) {
            return;
        }
        if (index > old_count) {
            index = old_count;
        }
        memmove((*styles) + index + delta,
                (*styles) + index,
                sizeof(airui_table_cell_style_t) * (old_count - index));
        memset((*styles) + index, 0, sizeof(airui_table_cell_style_t) * (uint32_t)delta);
        return;
    }

    if (*styles == NULL || *count == 0 || index >= *count) {
        return;
    }

    uint32_t remove_count = (uint32_t)(-delta);
    if (index + remove_count > *count) {
        remove_count = *count - index;
    }
    if (remove_count == 0) {
        return;
    }

    memmove((*styles) + index,
            (*styles) + index + remove_count,
            sizeof(airui_table_cell_style_t) * (*count - index - remove_count));
    memset((*styles) + (*count - remove_count), 0, sizeof(airui_table_cell_style_t) * remove_count);
    *count = (uint16_t)(*count - remove_count);

    if (*count == 0) {
        luat_heap_free(*styles);
        *styles = NULL;
        return;
    }

    airui_table_cell_style_t *new_styles = (airui_table_cell_style_t *)luat_heap_malloc(sizeof(airui_table_cell_style_t) * (*count));
    if (new_styles == NULL) {
        return;
    }
    memcpy(new_styles, *styles, sizeof(airui_table_cell_style_t) * (*count));
    luat_heap_free(*styles);
    *styles = new_styles;
}

static airui_table_cell_style_t *airui_table_get_cell_style_slot(lv_obj_t *table, bool is_row, uint32_t index, bool create)
{
    airui_table_data_t *data = create ? airui_table_ensure_data(table) : airui_table_get_data(table);
    if (data == NULL) {
        return NULL;
    }

    lv_table_t *table_dsc = (lv_table_t *)table;
    uint32_t limit = is_row ? table_dsc->row_cnt : table_dsc->col_cnt;
    if (index >= limit) {
        return NULL;
    }

    airui_table_cell_style_t **styles = is_row ? &data->row_styles : &data->col_styles;
    uint16_t *count = is_row ? &data->row_style_count : &data->col_style_count;
    if (create && airui_table_ensure_cell_style_capacity(styles, count, limit) != AIRUI_OK) {
        return NULL;
    }
    if (*styles == NULL || index >= *count) {
        return NULL;
    }
    return (*styles) + index;
}

// 选择单元格
static void airui_table_jump_scroll_select_cell(lv_obj_t *table, uint32_t row, uint32_t col)
{
    if (table == NULL) {
        return;
    }

    lv_table_t *table_dsc = (lv_table_t *)table;
    if (table_dsc->row_cnt == 0 || table_dsc->col_cnt == 0) {
        return;
    }

    if (row >= table_dsc->row_cnt) {
        row = table_dsc->row_cnt - 1;
    }
    if (col >= table_dsc->col_cnt) {
        col = table_dsc->col_cnt - 1;
    }

    table_dsc->row_act = row;
    table_dsc->col_act = col;
    lv_obj_invalidate(table);
}

// 滚动行到视图
static void airui_table_scroll_row_into_view(lv_obj_t *table, uint32_t row, bool animated)
{
    if (table == NULL) {
        return;
    }

    lv_table_t *table_dsc = (lv_table_t *)table;
    if (table_dsc->row_h == NULL || row >= table_dsc->row_cnt) {
        return;
    }

    int32_t row_top = 0;
    for (uint32_t i = 0; i < row; i++) {
        row_top += table_dsc->row_h[i];
    }

    int32_t row_bottom = row_top + table_dsc->row_h[row];
    int32_t visible_top = lv_obj_get_scroll_top(table);
    int32_t visible_bottom = visible_top + lv_obj_get_height(table);
    int32_t target = visible_top;

    if (row_top < visible_top) {
        target = row_top;
    }
    else if (row_bottom > visible_bottom) {
        target = row_bottom - lv_obj_get_height(table);
    }
    else {
        return;
    }

    lv_obj_scroll_to_y(table, target, animated ? LV_ANIM_ON : LV_ANIM_OFF);
}

// 停止跳转滚动
static void airui_table_jump_scroll_stop_internal(lv_obj_t *table, bool reset_position)
{
    airui_table_data_t *data = airui_table_get_data(table);
    if (data == NULL) {
        return;
    }

    if (data->jump_scroll_timer != NULL) {
        lv_timer_delete(data->jump_scroll_timer);
        data->jump_scroll_timer = NULL;
    }

    data->jump_scroll_running = false;
    data->jump_scroll_paused = false;
    data->jump_scroll_current_row = 0;

    if (reset_position) {
        lv_obj_stop_scroll_anim(table);
        lv_obj_scroll_to_y(table, 0, LV_ANIM_OFF);
        airui_table_jump_scroll_select_cell(table, 0, data->jump_scroll_focus_col);
    }
}

// 跳转滚动定时器回调
static void airui_table_jump_scroll_timer_cb(lv_timer_t *timer)
{
    if (timer == NULL) {
        return;
    }

    lv_obj_t *table = (lv_obj_t *)lv_timer_get_user_data(timer);
    if (table == NULL) {
        lv_timer_delete(timer);
        return;
    }

    airui_table_data_t *data = airui_table_get_data(table);
    if (data == NULL || data->jump_scroll_timer != timer || !data->jump_scroll_running || data->jump_scroll_paused) {
        return;
    }

    uint32_t row_count = lv_table_get_row_count(table);
    uint32_t col_count = lv_table_get_column_count(table);
    if (row_count == 0 || col_count == 0) {
        airui_table_jump_scroll_stop_internal(table, false);
        return;
    }

    if (row_count == 1) {
        data->jump_scroll_current_row = 0;
        airui_table_jump_scroll_select_cell(table, 0, 0);
        return;
    }

    uint32_t focus_col = data->jump_scroll_focus_col;
    if (focus_col >= col_count) {
        focus_col = col_count - 1;
    }

    uint32_t next_row = data->jump_scroll_current_row + data->jump_scroll_step;
    bool wrapped = false;
    if (next_row >= row_count) {
        if (!data->jump_scroll_loop) {
            airui_table_jump_scroll_stop_internal(table, false);
            return;
        }
        next_row %= row_count;
        wrapped = true;
    }

    if (wrapped) {
        lv_obj_stop_scroll_anim(table);
        lv_obj_scroll_to_y(table, 0, LV_ANIM_OFF);
    }

    data->jump_scroll_current_row = (uint16_t)next_row;
    airui_table_jump_scroll_select_cell(table, next_row, focus_col);
    airui_table_scroll_row_into_view(table, next_row, data->jump_scroll_anim && !wrapped);
}

// 停止跑马灯滚动
static void airui_table_marquee_scroll_stop_internal(lv_obj_t *table, bool reset_position)
{
    airui_table_data_t *data = airui_table_get_data(table);
    if (data == NULL) {
        return;
    }

    if (data->marquee_scroll_timer != NULL) {
        lv_timer_delete(data->marquee_scroll_timer);
        data->marquee_scroll_timer = NULL;
    }

    data->marquee_scroll_running = false;
    data->marquee_scroll_paused = false;

    if (reset_position) {
        lv_obj_stop_scroll_anim(table);
        lv_obj_scroll_to_y(table, 0, LV_ANIM_OFF);
    }
}

// 跑马灯滚动定时器回调
static void airui_table_marquee_scroll_timer_cb(lv_timer_t *timer)
{
    if (timer == NULL) {
        return;
    }

    lv_obj_t *table = (lv_obj_t *)lv_timer_get_user_data(timer);
    if (table == NULL) {
        lv_timer_delete(timer);
        return;
    }

    airui_table_data_t *data = airui_table_get_data(table);
    if (data == NULL || data->marquee_scroll_timer != timer || !data->marquee_scroll_running || data->marquee_scroll_paused) {
        return;
    }

    if (lv_table_get_row_count(table) == 0 || lv_table_get_column_count(table) == 0) {
        airui_table_marquee_scroll_stop_internal(table, false);
        return;
    }

    int32_t scroll_bottom = lv_obj_get_scroll_bottom(table);
    if (scroll_bottom <= 0) {
        if (!data->marquee_scroll_loop) {
            airui_table_marquee_scroll_stop_internal(table, false);
            return;
        }
        lv_obj_stop_scroll_anim(table);
        lv_obj_scroll_to_y(table, 0, LV_ANIM_OFF);
        scroll_bottom = lv_obj_get_scroll_bottom(table);
        if (scroll_bottom <= 0) {
            return;
        }
    }

    int32_t delta = data->marquee_scroll_speed;
    if (delta <= 0) {
        delta = 1;
    }
    if (delta > scroll_bottom) {
        delta = scroll_bottom;
    }
    lv_obj_scroll_to_y(table, lv_obj_get_scroll_y(table) + delta, LV_ANIM_OFF);
}

// 样式事件回调
static void airui_table_style_event_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) != LV_EVENT_STYLE_CHANGED) {
        return;
    }

    lv_obj_t *table = lv_event_get_target(e);
    airui_table_reapply_row_heights(table);
}

static void airui_table_draw_task_added_event_cb(lv_event_t *e)
{
    lv_obj_t *table = lv_event_get_current_target(e);
    lv_draw_task_t *draw_task = lv_event_get_param(e);
    lv_draw_dsc_base_t *base = (lv_draw_dsc_base_t *)draw_task->draw_dsc;
    if (table == NULL || draw_task == NULL || base == NULL || base->part != LV_PART_ITEMS) {
        return;
    }

    lv_table_t *table_dsc = (lv_table_t *)table;
    uint32_t row = base->id1;
    uint32_t col = base->id2;
    if (row >= table_dsc->row_cnt || col >= table_dsc->col_cnt) {
        return;
    }

    if (row == table_dsc->row_act && col == table_dsc->col_act &&
        (table->state & (LV_STATE_PRESSED | LV_STATE_FOCUSED | LV_STATE_FOCUS_KEY | LV_STATE_EDITED))) {
        return;
    }

    airui_table_data_t *data = airui_table_get_data(table);
    if (data == NULL) {
        return;
    }

    airui_table_cell_style_t merged = {0};
    bool has_style = false;
    if (data->row_styles != NULL && row < data->row_style_count) {
        merged = data->row_styles[row];
        has_style = merged.has_bg_color || merged.has_border_color || merged.has_text_color;
    }
    if (data->col_styles != NULL && col < data->col_style_count) {
        airui_table_cell_style_t *col_style = &data->col_styles[col];
        if (col_style->has_bg_color) {
            merged.has_bg_color = true;
            merged.bg_color = col_style->bg_color;
        }
        if (col_style->has_border_color) {
            merged.has_border_color = true;
            merged.border_color = col_style->border_color;
        }
        if (col_style->has_text_color) {
            merged.has_text_color = true;
            merged.text_color = col_style->text_color;
        }
        has_style = has_style || col_style->has_bg_color || col_style->has_border_color || col_style->has_text_color;
    }
    if (!has_style) {
        return;
    }

    lv_draw_fill_dsc_t *fill_dsc = lv_draw_task_get_fill_dsc(draw_task);
    lv_draw_border_dsc_t *border_dsc = lv_draw_task_get_border_dsc(draw_task);
    lv_draw_label_dsc_t *label_dsc = lv_draw_task_get_label_dsc(draw_task);

    if (fill_dsc != NULL && merged.has_bg_color) {
        fill_dsc->color = merged.bg_color;
        fill_dsc->opa = LV_OPA_COVER;
    }
    if (border_dsc != NULL && merged.has_border_color) {
        border_dsc->color = merged.border_color;
        border_dsc->opa = LV_OPA_COVER;
    }
    if (label_dsc != NULL && merged.has_text_color) {
        label_dsc->color = merged.text_color;
        label_dsc->opa = LV_OPA_COVER;
    }
    if (label_dsc != NULL && data->cell_font_size > 0) {
        lv_font_t *font = airui_font_hzfont_get_size(data->cell_font_size);
        if (font != NULL) {
            label_dsc->font = font;
        }
    }

    if (draw_task->type == LV_DRAW_TASK_TYPE_LABEL && data->cell_vertical_align == AIRUI_TABLE_CELL_VERTICAL_ALIGN_TOP) {
        lv_table_cell_ctrl_t ctrl = 0;
        uint32_t cell = row * table_dsc->col_cnt + col;
        if (table_dsc->cell_data != NULL && table_dsc->cell_data[cell] != NULL) {
            ctrl = table_dsc->cell_data[cell]->ctrl;
        }

        if ((ctrl & LV_TABLE_CELL_CTRL_TEXT_CROP) == 0) {
            lv_coord_t row_height = table_dsc->row_h[row];
            lv_coord_t text_height = lv_area_get_height(&draw_task->area);
            lv_coord_t pad_top = lv_obj_get_style_pad_top(table, LV_PART_ITEMS);
            lv_coord_t offset = (row_height - text_height) / 2 - pad_top;
            if (offset > 0) {
                draw_task->area.y1 -= offset;
                draw_task->area.y2 -= offset;
            }
        }
    }
}

static void airui_table_clamp_selection(lv_obj_t *table)
{
    if (table == NULL) {
        return;
    }

    lv_table_t *table_dsc = (lv_table_t *)table;
    if (table_dsc->row_cnt == 0 || table_dsc->col_cnt == 0) {
        table_dsc->row_act = 0;
        table_dsc->col_act = 0;
        return;
    }

    if (table_dsc->row_act >= table_dsc->row_cnt) {
        table_dsc->row_act = table_dsc->row_cnt - 1;
    }
    if (table_dsc->col_act >= table_dsc->col_cnt) {
        table_dsc->col_act = table_dsc->col_cnt - 1;
    }
}

static void airui_table_adjust_after_structure_change(lv_obj_t *table, bool row_axis, uint32_t index, uint32_t remove_count)
{
    airui_table_data_t *data = airui_table_get_data(table);
    lv_table_t *table_dsc = (lv_table_t *)table;

    if (data != NULL) {
        if (row_axis) {
            if ((data->jump_scroll_running || data->jump_scroll_paused) && data->jump_scroll_current_row >= index) {
                if (data->jump_scroll_current_row < index + remove_count) {
                    data->jump_scroll_current_row = (uint16_t)index;
                }
                else {
                    data->jump_scroll_current_row = (uint16_t)(data->jump_scroll_current_row - remove_count);
                }
            }
        }
        else {
            if (data->jump_scroll_focus_col >= index) {
                if (data->jump_scroll_focus_col < index + remove_count) {
                    data->jump_scroll_focus_col = (uint16_t)index;
                }
                else {
                    data->jump_scroll_focus_col = (uint16_t)(data->jump_scroll_focus_col - remove_count);
                }
            }
        }
    }

    if (row_axis && table_dsc->row_act >= index) {
        if (table_dsc->row_act < index + remove_count) {
            table_dsc->row_act = index;
        }
        else {
            table_dsc->row_act -= remove_count;
        }
    }
    if (!row_axis && table_dsc->col_act >= index) {
        if (table_dsc->col_act < index + remove_count) {
            table_dsc->col_act = index;
        }
        else {
            table_dsc->col_act -= remove_count;
        }
    }

    airui_table_clamp_selection(table);
}

// 归一化行高
static lv_coord_t airui_table_normalize_row_height(lv_coord_t height)
{
    return height < 1 ? 1 : height;
}

// 同步表大小
static void airui_table_sync_size(lv_obj_t *table, int rows, int cols)
{
    if (table == NULL) {
        return;
    }

    if (rows < 1) {
        rows = 1;
    }
    if (cols < 1) {
        cols = 1;
    }

    lv_table_set_row_count(table, (uint32_t)rows);
    lv_table_set_column_count(table, (uint32_t)cols);
}

// 应用行高
static void airui_table_apply_row_height(lv_obj_t *table, uint32_t row, lv_coord_t height)
{
    if (table == NULL) {
        return;
    }

    height = airui_table_normalize_row_height(height);

    if (row >= lv_table_get_row_count(table)) {
        lv_table_set_row_count(table, row + 1);
    }

    lv_table_t *table_dsc = (lv_table_t *)table;
    if (table_dsc->row_h == NULL) {
        return;
    }

    int32_t min_height = lv_obj_get_style_min_height(table, LV_PART_ITEMS);
    int32_t max_height = lv_obj_get_style_max_height(table, LV_PART_ITEMS);
    table_dsc->row_h[row] = LV_CLAMP(min_height, height, max_height);

    lv_obj_refresh_self_size(table);
    lv_obj_invalidate(table);
}

// 重新应用行高
static void airui_table_reapply_row_heights(lv_obj_t *table)
{
    airui_table_data_t *data = airui_table_get_data(table);
    if (data == NULL || data->row_heights == NULL) {
        return;
    }

    for (uint32_t row = 0; row < data->row_count; row++) {
        if (data->row_heights[row] > 0) {
            airui_table_apply_row_height(table, row, data->row_heights[row]);
        }
    }
}

// 应用数据
static void airui_table_apply_data(lua_State *L_state, int idx, lv_obj_t *table, int *rows, int *cols)
{
    lua_getfield(L_state, idx, "data");
    if (lua_type(L_state, -1) != LUA_TTABLE) {
        lua_pop(L_state, 1);
        return;
    }

    size_t row_count = lua_rawlen(L_state, -1);
    for (size_t row = 0; row < row_count; row++) {
        lua_rawgeti(L_state, -1, (lua_Integer)(row + 1));
        if (lua_type(L_state, -1) == LUA_TTABLE) {
            size_t col_count = lua_rawlen(L_state, -1);
            for (size_t col = 0; col < col_count; col++) {
                lua_rawgeti(L_state, -1, (lua_Integer)(col + 1));
                if (!lua_isnil(L_state, -1)) {
                    size_t text_len = 0;
                    const char *text = luaL_tolstring(L_state, -1, &text_len);
                    lv_table_set_cell_value(table, (uint32_t)row, (uint32_t)col, text ? text : "");
                    lua_pop(L_state, 1);
                }
                lua_pop(L_state, 1);
            }
            if ((int)col_count > *cols) {
                *cols = (int)col_count;
            }
        }
        lua_pop(L_state, 1);
    }

    if ((int)row_count > *rows) {
        *rows = (int)row_count;
    }
    lua_pop(L_state, 1);
}

int airui_table_set_style(lv_obj_t *table, void *L, int idx)
{
    if (table == NULL || L == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lua_State *L_state = (lua_State *)L;
    int value = 0;
    idx = lua_absindex(L_state, idx);
    if (!lua_istable(L_state, idx)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (airui_marshal_integer_opt(L_state, idx, "bg_color", &value)) {
        lv_obj_set_style_bg_color(table, lv_color_hex((uint32_t)value), (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "bg_opa", &value)) {
        lv_obj_set_style_bg_opa(table, airui_marshal_opacity(value), (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "border_color", &value)) {
        lv_obj_set_style_border_color(table, lv_color_hex((uint32_t)value), (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "border_width", &value)) {
        lv_obj_set_style_border_width(table, value < 0 ? 0 : value, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "radius", &value)) {
        lv_obj_set_style_radius(table, value < 0 ? 0 : value, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    }

    if (airui_marshal_integer_opt(L_state, idx, "cell_bg_color", &value)) {
        lv_obj_set_style_bg_color(table, lv_color_hex((uint32_t)value), (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "cell_bg_opa", &value)) {
        lv_obj_set_style_bg_opa(table, airui_marshal_opacity(value), (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "cell_border_color", &value)) {
        lv_obj_set_style_border_color(table, lv_color_hex((uint32_t)value), (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "cell_border_width", &value)) {
        lv_obj_set_style_border_width(table, value < 0 ? 0 : value, (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(table, value < 0 ? 0 : value, (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_PRESSED);
    }
    if (airui_marshal_integer_opt(L_state, idx, "cell_text_color", &value)) {
        lv_obj_set_style_text_color(table, lv_color_hex((uint32_t)value), (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "cell_text_align", &value)) {
        if (value == (int)LV_TEXT_ALIGN_LEFT || value == (int)LV_TEXT_ALIGN_CENTER || value == (int)LV_TEXT_ALIGN_RIGHT) {
            lv_obj_set_style_text_align(table, (lv_text_align_t)value, (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT);
            lv_obj_set_style_text_align(table, (lv_text_align_t)value, (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_PRESSED);
        }
    }

    if (airui_marshal_integer_opt(L_state, idx, "selected_cell_bg_color", &value)) {
        lv_obj_set_style_bg_color(table, lv_color_hex((uint32_t)value), (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_PRESSED);
    }
    if (airui_marshal_integer_opt(L_state, idx, "selected_cell_bg_opa", &value)) {
        lv_obj_set_style_bg_opa(table, airui_marshal_opacity(value), (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_PRESSED);
    }
    if (airui_marshal_integer_opt(L_state, idx, "selected_cell_border_color", &value)) {
        lv_obj_set_style_border_color(table, lv_color_hex((uint32_t)value), (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_PRESSED);
    }
    if (airui_marshal_integer_opt(L_state, idx, "selected_cell_text_color", &value)) {
        lv_obj_set_style_text_color(table, lv_color_hex((uint32_t)value), (lv_style_selector_t)LV_PART_ITEMS | LV_STATE_PRESSED);
    }
    if (airui_marshal_integer_opt(L_state, idx, "cell_font_size", &value) && value > 0) {
        airui_table_data_t *data = airui_table_ensure_data(table);
        if (data != NULL) {
            data->cell_font_size = (uint16_t)value;
        }
        (void)airui_text_font_apply_hzfont(table, value,
            ((lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT));
        (void)airui_text_font_apply_hzfont(table, value,
            ((lv_style_selector_t)LV_PART_ITEMS | LV_STATE_PRESSED));
    }

    {
        airui_table_data_t *data = airui_table_ensure_data(table);
        if (data != NULL) {
            data->cell_vertical_align = (uint8_t)airui_table_parse_vertical_align(
                L_state, idx, "cell_vertical_align",
                (airui_table_cell_vertical_align_t)data->cell_vertical_align);
        }
    }

    airui_table_reapply_row_heights(table);
    lv_obj_invalidate(table);
    return AIRUI_OK;
}

// 应用行高
static void airui_table_apply_col_widths(lua_State *L_state, int idx, lv_obj_t *table, int cols)
{
    lua_getfield(L_state, idx, "col_width");
    if (lua_type(L_state, -1) == LUA_TNUMBER) {
        lv_coord_t col_width = (lv_coord_t)lua_tointeger(L_state, -1);
        for (int i = 0; i < cols; i++) {
            airui_table_set_col_width(table, (uint16_t)i, col_width);
        }
    }
    else if (lua_type(L_state, -1) == LUA_TTABLE) {
        size_t col_width_count = lua_rawlen(L_state, -1);
        for (size_t i = 0; i < col_width_count && i < (size_t)cols; i++) {
            lua_rawgeti(L_state, -1, (lua_Integer)(i + 1));
            if (lua_type(L_state, -1) == LUA_TNUMBER) {
                lv_coord_t col_width = (lv_coord_t)lua_tointeger(L_state, -1);
                airui_table_set_col_width(table, (uint16_t)i, col_width);
            }
            lua_pop(L_state, 1);
        }
    }
    lua_pop(L_state, 1);
}

// 应用行高
static void airui_table_apply_row_heights(lua_State *L_state, int idx, lv_obj_t *table, int rows)
{
    lua_getfield(L_state, idx, "row_height");
    if (lua_type(L_state, -1) == LUA_TNUMBER) {
        lv_coord_t row_height = (lv_coord_t)lua_tointeger(L_state, -1);
        for (int i = 0; i < rows; i++) {
            airui_table_set_row_height(table, (uint16_t)i, row_height);
        }
    }
    else if (lua_type(L_state, -1) == LUA_TTABLE) {
        size_t row_height_count = lua_rawlen(L_state, -1);
        for (size_t i = 0; i < row_height_count && i < (size_t)rows; i++) {
            lua_rawgeti(L_state, -1, (lua_Integer)(i + 1));
            if (lua_type(L_state, -1) == LUA_TNUMBER) {
                lv_coord_t row_height = (lv_coord_t)lua_tointeger(L_state, -1);
                airui_table_set_row_height(table, (uint16_t)i, row_height);
            }
            lua_pop(L_state, 1);
        }
    }
    lua_pop(L_state, 1);
}

/**
 * 设置指定单元格文本
 * @param table Table 对象
 * @param row 行索引
 * @param col 列索引
 * @param text 文本内容
 * @return AIRUI_OK 成功，其他失败
 */
int airui_table_set_cell_text(lv_obj_t *table, uint16_t row, uint16_t col, const char *text)
{
    if (table == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_table_set_cell_value(table, row, col, text != NULL ? text : "");
    airui_table_reapply_row_heights(table);
    return AIRUI_OK;
}

/**
 * 获取单元格文本
 * @param table Table 对象
 * @param row 行索引
 * @param col 列索引
 * @return 单元格文本，失败返回 NULL
 */
const char *airui_table_get_cell_text(lv_obj_t *table, uint16_t row, uint16_t col)
{
    if (table == NULL) {
        return NULL;
    }
    return lv_table_get_cell_value(table, row, col);
}

/**
 * 调整列宽
 * @param table Table 对象
 * @param col 要设置的列索引
 * @param width 目标宽度
 * @return AIRUI_OK 成功，其他失败
 */
int airui_table_set_col_width(lv_obj_t *table, uint16_t col, lv_coord_t width)
{
    if (table == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_table_set_column_width(table, col, width);
    return AIRUI_OK;
}

/**
 * 调整行高
 * @param table Table 对象
 * @param row 要设置的行索引
 * @param height 目标高度
 * @return AIRUI_OK 成功，其他失败
 */
int airui_table_set_row_height(lv_obj_t *table, uint16_t row, lv_coord_t height)
{
    if (table == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    int ret = airui_table_store_row_height(table, row, height);
    if (ret != AIRUI_OK) {
        return ret;
    }

    airui_table_apply_row_height(table, row, height);
    return AIRUI_OK;
}

/**
 * 设置表格边框的颜色
 * @param table Table 对象
 * @param color 16 进制颜色值（lv_color_t）
 * @return AIRUI_OK 成功，其他失败
 */
int airui_table_set_border_color(lv_obj_t *table, lv_color_t color)
{
    if (table == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_obj_set_style_border_color(table, color, ((lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT));
    return AIRUI_OK;
}

int airui_table_set_cell_style(lv_obj_t *table, bool is_row, uint16_t index, void *L, int idx)
{
    if (table == NULL || L == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lua_State *L_state = (lua_State *)L;
    airui_table_cell_style_t *style = airui_table_get_cell_style_slot(table, is_row, index, true);
    int value = 0;
    if (style == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    idx = lua_absindex(L_state, idx);
    if (!lua_istable(L_state, idx)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    memset(style, 0, sizeof(airui_table_cell_style_t));
    if (airui_marshal_integer_opt(L_state, idx, "cell_bg_color", &value)) {
        style->has_bg_color = true;
        style->bg_color = lv_color_hex((uint32_t)value);
    }
    if (airui_marshal_integer_opt(L_state, idx, "cell_border_color", &value)) {
        style->has_border_color = true;
        style->border_color = lv_color_hex((uint32_t)value);
    }
    if (airui_marshal_integer_opt(L_state, idx, "cell_text_color", &value)) {
        style->has_text_color = true;
        style->text_color = lv_color_hex((uint32_t)value);
    }

    lv_obj_invalidate(table);
    return AIRUI_OK;
}

int airui_table_insert(lv_obj_t *table, bool is_row, uint16_t index)
{
    if (table == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_table_t *table_dsc = (lv_table_t *)table;
    airui_table_data_t *data = airui_table_get_data(table);
    if (is_row) {
        uint32_t old_row_count = table_dsc->row_cnt;
        uint32_t col_count = table_dsc->col_cnt;
        int32_t inserted_row_height = 0;

        if (index > old_row_count) {
            index = (uint16_t)old_row_count;
        }

        lv_table_set_row_count(table, old_row_count + 1);
        table_dsc = (lv_table_t *)table;
        inserted_row_height = table_dsc->row_h[old_row_count];

        if (col_count > 0 && index < old_row_count) {
            memmove(table_dsc->cell_data + ((index + 1U) * col_count),
                    table_dsc->cell_data + (index * col_count),
                    sizeof(table_dsc->cell_data[0]) * ((old_row_count - index) * col_count));
            memset(table_dsc->cell_data + (index * col_count), 0, sizeof(table_dsc->cell_data[0]) * col_count);
            memmove(table_dsc->row_h + index + 1U,
                    table_dsc->row_h + index,
                    sizeof(table_dsc->row_h[0]) * (old_row_count - index));
        }
        table_dsc->row_h[index] = inserted_row_height;

        if (data != NULL) {
            airui_table_shift_cached_row_heights(data, index, 1);
            airui_table_shift_cell_style_rules(&data->row_styles, &data->row_style_count, index, 1);
            if ((data->jump_scroll_running || data->jump_scroll_paused) && data->jump_scroll_current_row >= index) {
                data->jump_scroll_current_row++;
            }
        }
    }
    else {
        uint32_t row_count = table_dsc->row_cnt;
        uint32_t old_col_count = table_dsc->col_cnt;

        if (index > old_col_count) {
            index = (uint16_t)old_col_count;
        }

        lv_table_set_column_count(table, old_col_count + 1);
        table_dsc = (lv_table_t *)table;

        if (row_count > 0 && index < old_col_count) {
            uint32_t new_col_count = table_dsc->col_cnt;
            for (int32_t row_idx = (int32_t)row_count - 1; row_idx >= 0; row_idx--) {
                uint32_t row_start = (uint32_t)row_idx * new_col_count;
                memmove(table_dsc->cell_data + row_start + index + 1U,
                        table_dsc->cell_data + row_start + index,
                        sizeof(table_dsc->cell_data[0]) * (old_col_count - index));
                table_dsc->cell_data[row_start + index] = NULL;
            }

            memmove(table_dsc->col_w + index + 1U,
                    table_dsc->col_w + index,
                    sizeof(table_dsc->col_w[0]) * (old_col_count - index));
        }
        table_dsc->col_w[index] = LV_DPI_DEF;

        if (data != NULL) {
            airui_table_shift_cell_style_rules(&data->col_styles, &data->col_style_count, index, 1);
            if (data->jump_scroll_focus_col >= index) {
                data->jump_scroll_focus_col++;
            }
        }
    }

    lv_obj_refresh_self_size(table);
    lv_obj_invalidate(table);
    return AIRUI_OK;
}

int airui_table_insert_row(lv_obj_t *table, uint16_t row)
{
    return airui_table_insert(table, true, row);
}

int airui_table_insert_col(lv_obj_t *table, uint16_t col)
{
    return airui_table_insert(table, false, col);
}

int airui_table_remove(lv_obj_t *table, bool is_row, uint16_t index, uint16_t count)
{
    if (table == NULL || count == 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_table_t *table_dsc = (lv_table_t *)table;
    airui_table_data_t *data = airui_table_get_data(table);
    if (is_row) {
        uint32_t old_row_count = table_dsc->row_cnt;
        uint32_t col_count = table_dsc->col_cnt;
        if (old_row_count <= 1 || index >= old_row_count) {
            return AIRUI_ERR_INVALID_PARAM;
        }
        if ((uint32_t)index + (uint32_t)count > old_row_count) {
            count = (uint16_t)(old_row_count - index);
        }
        if (old_row_count - count < 1) {
            count = (uint16_t)(old_row_count - 1);
        }
        if (count == 0) {
            return AIRUI_ERR_INVALID_PARAM;
        }

        for (uint32_t row = index; row < (uint32_t)index + (uint32_t)count; row++) {
            for (uint32_t col = 0; col < col_count; col++) {
                lv_free(table_dsc->cell_data[row * col_count + col]);
                table_dsc->cell_data[row * col_count + col] = NULL;
            }
        }
        if ((uint32_t)index + (uint32_t)count < old_row_count) {
            memmove(table_dsc->cell_data + index * col_count,
                    table_dsc->cell_data + (index + count) * col_count,
                    sizeof(table_dsc->cell_data[0]) * ((old_row_count - index - count) * col_count));
            memmove(table_dsc->row_h + index,
                    table_dsc->row_h + index + count,
                    sizeof(table_dsc->row_h[0]) * (old_row_count - index - count));
        }
        memset(table_dsc->cell_data + (old_row_count - count) * col_count, 0, sizeof(table_dsc->cell_data[0]) * (count * col_count));
        memset(table_dsc->row_h + (old_row_count - count), 0, sizeof(table_dsc->row_h[0]) * count);

        if (data != NULL) {
            airui_table_shift_cached_row_heights(data, index, -(int32_t)count);
            airui_table_shift_cell_style_rules(&data->row_styles, &data->row_style_count, index, -(int32_t)count);
        }

        lv_table_set_row_count(table, old_row_count - count);
        airui_table_adjust_after_structure_change(table, true, index, count);
    }
    else {
        uint32_t row_count = table_dsc->row_cnt;
        uint32_t old_col_count = table_dsc->col_cnt;
        if (old_col_count <= 1 || index >= old_col_count) {
            return AIRUI_ERR_INVALID_PARAM;
        }
        if ((uint32_t)index + (uint32_t)count > old_col_count) {
            count = (uint16_t)(old_col_count - index);
        }
        if (old_col_count - count < 1) {
            count = (uint16_t)(old_col_count - 1);
        }
        if (count == 0) {
            return AIRUI_ERR_INVALID_PARAM;
        }

        for (uint32_t row = 0; row < row_count; row++) {
            uint32_t row_start = row * old_col_count;
            for (uint32_t col = index; col < (uint32_t)index + (uint32_t)count; col++) {
                lv_free(table_dsc->cell_data[row_start + col]);
                table_dsc->cell_data[row_start + col] = NULL;
            }
            if ((uint32_t)index + (uint32_t)count < old_col_count) {
                memmove(table_dsc->cell_data + row_start + index,
                        table_dsc->cell_data + row_start + index + count,
                        sizeof(table_dsc->cell_data[0]) * (old_col_count - index - count));
            }
            memset(table_dsc->cell_data + row_start + (old_col_count - count), 0, sizeof(table_dsc->cell_data[0]) * count);
        }

        if ((uint32_t)index + (uint32_t)count < old_col_count) {
            memmove(table_dsc->col_w + index,
                    table_dsc->col_w + index + count,
                    sizeof(table_dsc->col_w[0]) * (old_col_count - index - count));
        }
        memset(table_dsc->col_w + (old_col_count - count), 0, sizeof(table_dsc->col_w[0]) * count);

        if (data != NULL) {
            airui_table_shift_cell_style_rules(&data->col_styles, &data->col_style_count, index, -(int32_t)count);
        }

        lv_table_set_column_count(table, old_col_count - count);
        airui_table_adjust_after_structure_change(table, false, index, count);
    }

    lv_obj_refresh_self_size(table);
    lv_obj_invalidate(table);
    return AIRUI_OK;
}

// 自动跳转滚动
int airui_table_auto_jump_scroll_control(lv_obj_t *table,
                                         airui_table_scroll_action_t action,
                                         uint32_t interval,
                                         bool loop,
                                         bool anim,
                                         uint16_t step,
                                         uint16_t focus_col)
{
    if (table == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_table_data_t *data = airui_table_ensure_data(table);
    if (data == NULL) {
        return AIRUI_ERR_NO_MEM;
    }

    switch (action) {
    case AIRUI_TABLE_SCROLL_ACTION_START: {
        uint32_t row_count = lv_table_get_row_count(table);
        uint32_t col_count = lv_table_get_column_count(table);
        if (row_count == 0 || col_count == 0) {
            return AIRUI_ERR_INVALID_PARAM;
        }

        airui_table_marquee_scroll_stop_internal(table, false);

        if (interval == 0) {
            interval = 1500;
        }
        if (step == 0) {
            step = 1;
        }
        if (focus_col >= col_count) {
            focus_col = (uint16_t)(col_count - 1);
        }

        data->jump_scroll_interval = interval;
        data->jump_scroll_loop = loop;
        data->jump_scroll_anim = anim;
        data->jump_scroll_step = step;
        data->jump_scroll_focus_col = focus_col;
        data->jump_scroll_current_row = 0;
        data->jump_scroll_running = true;
        data->jump_scroll_paused = false;

        if (data->jump_scroll_timer == NULL) {
            data->jump_scroll_timer = lv_timer_create(airui_table_jump_scroll_timer_cb, interval, table);
            if (data->jump_scroll_timer == NULL) {
                data->jump_scroll_running = false;
                return AIRUI_ERR_NO_MEM;
            }
        }
        else {
            lv_timer_set_period(data->jump_scroll_timer, interval);
            lv_timer_set_user_data(data->jump_scroll_timer, table);
            lv_timer_resume(data->jump_scroll_timer);
        }

        lv_obj_stop_scroll_anim(table);
        lv_obj_scroll_to_y(table, 0, LV_ANIM_OFF);
        airui_table_jump_scroll_select_cell(table, 0, focus_col);
        lv_timer_reset(data->jump_scroll_timer);
        return AIRUI_OK;
    }
    case AIRUI_TABLE_SCROLL_ACTION_PAUSE:
        if (data->jump_scroll_timer != NULL) {
            lv_timer_pause(data->jump_scroll_timer);
            data->jump_scroll_paused = true;
        }
        return AIRUI_OK;
    case AIRUI_TABLE_SCROLL_ACTION_RESUME:
        if (data->jump_scroll_timer != NULL) {
            lv_timer_resume(data->jump_scroll_timer);
            data->jump_scroll_running = true;
            data->jump_scroll_paused = false;
        }
        return AIRUI_OK;
    case AIRUI_TABLE_SCROLL_ACTION_STOP:
        airui_table_jump_scroll_stop_internal(table, true);
        return AIRUI_OK;
    default:
        return AIRUI_ERR_INVALID_PARAM;
    }
}

// 自动跑马灯滚动
int airui_table_auto_marquee_scroll_control(lv_obj_t *table,
                                            airui_table_scroll_action_t action,
                                            uint32_t interval,
                                            bool loop,
                                            uint16_t speed)
{
    if (table == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_table_data_t *data = airui_table_ensure_data(table);
    if (data == NULL) {
        return AIRUI_ERR_NO_MEM;
    }

    switch (action) {
    case AIRUI_TABLE_SCROLL_ACTION_START:
        if (lv_table_get_row_count(table) == 0 || lv_table_get_column_count(table) == 0) {
            return AIRUI_ERR_INVALID_PARAM;
        }

        airui_table_jump_scroll_stop_internal(table, false);

        if (interval == 0) {
            interval = 30;
        }
        if (speed == 0) {
            speed = 1;
        }

        data->marquee_scroll_interval = interval;
        data->marquee_scroll_speed = speed;
        data->marquee_scroll_loop = loop;
        data->marquee_scroll_running = true;
        data->marquee_scroll_paused = false;

        if (data->marquee_scroll_timer == NULL) {
            data->marquee_scroll_timer = lv_timer_create(airui_table_marquee_scroll_timer_cb, interval, table);
            if (data->marquee_scroll_timer == NULL) {
                data->marquee_scroll_running = false;
                return AIRUI_ERR_NO_MEM;
            }
        }
        else {
            lv_timer_set_period(data->marquee_scroll_timer, interval);
            lv_timer_set_user_data(data->marquee_scroll_timer, table);
            lv_timer_resume(data->marquee_scroll_timer);
        }

        lv_obj_stop_scroll_anim(table);
        lv_obj_scroll_to_y(table, 0, LV_ANIM_OFF);
        lv_timer_reset(data->marquee_scroll_timer);
        return AIRUI_OK;
    case AIRUI_TABLE_SCROLL_ACTION_PAUSE:
        if (data->marquee_scroll_timer != NULL) {
            lv_timer_pause(data->marquee_scroll_timer);
            data->marquee_scroll_paused = true;
        }
        return AIRUI_OK;
    case AIRUI_TABLE_SCROLL_ACTION_RESUME:
        if (data->marquee_scroll_timer != NULL) {
            lv_timer_resume(data->marquee_scroll_timer);
            data->marquee_scroll_running = true;
            data->marquee_scroll_paused = false;
        }
        return AIRUI_OK;
    case AIRUI_TABLE_SCROLL_ACTION_STOP:
        airui_table_marquee_scroll_stop_internal(table, true);
        return AIRUI_OK;
    default:
        return AIRUI_ERR_INVALID_PARAM;
    }
}

/**
 * 设置单元格点击回调
 * @param table Table 对象指针
 * @param callback_ref Lua 回调引用
 * @return 0 成功，<0 失败
 */
int airui_table_set_on_cell_click(lv_obj_t *table, int callback_ref)
{
    if (table == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(table);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return airui_component_bind_event(meta, AIRUI_EVENT_VALUE_CHANGED, callback_ref);
}
