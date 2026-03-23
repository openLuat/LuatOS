/**
 * @file luat_airui_table.c
 * @summary Table 组件实现
 * @responsible Table 创建与基础列/单元格 API
 */

#include "luat_airui_component.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/widgets/table/lv_table.h"
#include "lvgl9/src/widgets/table/lv_table_private.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_malloc.h"
#include <stdint.h>
#include <string.h>

static void airui_table_apply_row_height(lv_obj_t *table, uint32_t row, lv_coord_t height);
static void airui_table_apply_data(lua_State *L_state, int idx, lv_obj_t *table, int *rows, int *cols);
static void airui_table_apply_col_widths(lua_State *L_state, int idx, lv_obj_t *table, int cols);
static void airui_table_apply_row_heights(lua_State *L_state, int idx, lv_obj_t *table, int rows);
static void airui_table_reapply_row_heights(lv_obj_t *table);
static lv_coord_t airui_table_normalize_row_height(lv_coord_t height);
static void airui_table_sync_size(lv_obj_t *table, int rows, int cols);
static void airui_table_style_event_cb(lv_event_t *e);

typedef struct {
    lv_coord_t *row_heights;
    uint16_t row_count;
} airui_table_data_t;

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
    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);
    int w = airui_marshal_integer(L, idx, "w", 200);
    int h = airui_marshal_integer(L, idx, "h", 120);
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
    lv_obj_set_style_pad_all(table, 6, (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT));
    lv_obj_set_style_border_width(table, 1, (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT));
    // 设置边框颜色
    lv_color_t border_color;
    if (airui_marshal_color(L_state, idx, "border_color", &border_color)) {
        lv_obj_set_style_border_color(table, border_color, (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT));
    }

    lv_obj_add_event_cb(table, airui_table_style_event_cb, LV_EVENT_STYLE_CHANGED, NULL);

    airui_table_sync_size(table, rows, cols);

    airui_table_apply_data(L_state, idx, table, &rows, &cols);
    airui_table_sync_size(table, rows, cols);

    airui_table_apply_col_widths(L_state, idx, table, cols);

    airui_table_apply_row_heights(L_state, idx, table, rows);

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

// 样式事件回调
static void airui_table_style_event_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) != LV_EVENT_STYLE_CHANGED) {
        return;
    }

    lv_obj_t *table = lv_event_get_target(e);
    airui_table_reapply_row_heights(table);
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
    lv_obj_set_style_border_color(table, color, (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT));
    return AIRUI_OK;
}
