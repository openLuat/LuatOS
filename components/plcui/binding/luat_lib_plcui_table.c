/*
@module plcui.table
@summary XML 数据表格
@version 0.1.0
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_font.h"
#include <stdlib.h>
#include <string.h>

static bool cell_index(lua_State *L, plcui_widget_t *widget, unsigned *index)
{
    lua_Integer row = luaL_checkinteger(L, 2);
    lua_Integer column = luaL_checkinteger(L, 3);
    if (row < 1 || row > widget->table->rows || column < 1 || column > widget->table->columns) return false;
    *index = (unsigned)(row - 1) * widget->table->columns + (unsigned)(column - 1);
    return true;
}

/**
 * 更新一个单元格，不改变 XML 定义的行列数。
 * @api table:set_cell(row, column, text)
 * @int row 行号，从 1 开始
 * @int column 列号，从 1 开始
 * @string text UTF-8 文本，最多 511 字节
 * @return bool|nil 成功返回 true，失败返回 nil
 * @return table|nil 失败时返回错误表
 */
static int table_set_cell(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_TABLE, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    unsigned index;
    if (!cell_index(L, widget, &index)) return luat_plcui_binding_error(L, "E_SCHEMA", "Cell index is outside the XML table");
    size_t length;
    const char *text = luaL_checklstring(L, 4, &length);
    if (length >= PLCUI_TEXT_MAX || memchr(text, 0, length)) return luat_plcui_binding_error(L, "E_SCHEMA", "Cell text exceeds 511 bytes or contains NUL");
    char *copy = malloc(length + 1);
    if (!copy) return luat_plcui_binding_error(L, "E_MEMORY", "Cannot allocate cell text");
    memcpy(copy, text, length + 1);
    free(widget->table->cells[index]);
    widget->table->cells[index] = copy;
    lv_table_set_cell_value(widget->obj, index / widget->table->columns, index % widget->table->columns, copy);
    return luat_plcui_binding_success(L);
}

/**
 * 读取单元格文本。
 * @api table:get_cell(row, column)
 * @int row 行号，从 1 开始
 * @int column 列号，从 1 开始
 * @return string|nil 单元格文本，失败返回 nil
 * @return table|nil 失败时返回错误表
 */
static int table_get_cell(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_TABLE, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    unsigned index;
    if (!cell_index(L, widget, &index)) return luat_plcui_binding_error(L, "E_SCHEMA", "Cell index is outside the XML table");
    lua_pushstring(L, widget->table->cells[index] ? widget->table->cells[index] : "");
    return 1;
}

/**
 * 设置某一列的像素宽度。
 * @api table:set_column_width(column, width)
 * @int column 列号，从 1 开始
 * @int width 列宽，范围 1～4096
 * @return bool|nil 成功返回 true，失败返回 nil
 * @return table|nil 失败时返回错误表
 */
static int table_set_column_width(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_TABLE, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer column = luaL_checkinteger(L, 2);
    lua_Integer width = luaL_checkinteger(L, 3);
    if (column < 1 || column > widget->table->columns || width < 1 || width > 4096) return luat_plcui_binding_error(L, "E_SCHEMA", "Column or width is outside its range");
    widget->table->widths[column - 1] = (uint16_t)width;
    lv_table_set_column_width(widget->obj, (uint32_t)column - 1U, (int32_t)width);
    return luat_plcui_binding_success(L);
}

/**
 * 获取表格的固定行列数。
 * @api table:get_size()
 * @return int 行数，包含表头
 * @return int 列数
 */
static int table_get_size(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_TABLE, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_pushinteger(L, widget->table->rows);
    lua_pushinteger(L, widget->table->columns);
    return 2;
}

/**
 * 调整 HZFont 字号，保持 XML 表格区域不变。
 * @api table:set_font_size(font_size)
 * @int font_size 字号，范围 1～255
 * @return bool|nil 成功返回 true，失败返回 nil
 * @return table|nil 失败时返回错误表
 */
static int table_set_font_size(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_TABLE, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer size = luaL_checkinteger(L, 2);
    if (size < 1 || size > 255) return luat_plcui_binding_error(L, "E_SCHEMA", "font_size must be between 1 and 255");
    if (!luat_plcui_set_font_size(widget, (uint16_t)size, &error)) return luat_plcui_push_error(L, &error);
    return luat_plcui_binding_success(L);
}

void luat_plcui_register_table_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_cell", table_set_cell},
        {"get_cell", table_get_cell},
        {"set_column_width", table_set_column_width},
        {"get_size", table_get_size},
        {"set_font_size", table_set_font_size},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_TABLE_MT);
    luaL_setfuncs(L, methods, 0);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
