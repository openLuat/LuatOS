/**
 * @file luat_airui_table.c
 * @summary Table 组件实现
 * @responsible Table 创建与基础列/单元格 API
 */

#include "luat_airui_component.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/widgets/table/lv_table.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lua.h"
#include "lauxlib.h"
#include <stdint.h>

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

    lv_table_set_row_cnt(table, rows);
    lv_table_set_col_cnt(table, cols);

    int col_width_count = airui_marshal_table_length(L, idx, "col_width");
    if (col_width_count > 0) {
        lua_getfield(L_state, idx, "col_width");
        for (int i = 0; i < col_width_count && i < cols; i++) {
            if (lua_type(L_state, -1) == LUA_TTABLE) {
                // 设置每一列的宽度
                lua_rawgeti(L_state, -1, i + 1);
                if (lua_type(L_state, -1) == LUA_TNUMBER) {
                    int width = lua_tointeger(L_state, -1);
                    lv_table_set_col_width(table, i, width);
                }
                lua_pop(L_state, 1);
            }
        }
        lua_pop(L_state, 1);
    }

    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, table, AIRUI_COMPONENT_TABLE);
    if (meta == NULL) {
        lv_obj_delete(table);
        return NULL;
    }

    return table;
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
    lv_table_set_col_width(table, col, width);
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

