/*
@module plcui.table
@summary XML 数据表格
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_font.h"
#include <stdlib.h>
#include <string.h>

/**
 * 检查 Lua 行列参数并换算为表格模型中的一维索引。
 * @param L Lua 状态机，参数 2、3 分别为从 1 开始的行号和列号
 * @param widget 已验证类型及生命周期的 table 组件
 * @param index 成功时写入从 0 开始的模型索引，失败时不写入
 * @return 行列均在 XML 表格范围内返回 true，否则返回 false
 * @note Lua 参数类型错误由 luaL_checkinteger 抛出；本函数不向 Lua 栈压入返回值。
 */
static bool cell_index(lua_State *L, plcui_widget_t *widget, unsigned *index)
{
    lua_Integer row = luaL_checkinteger(L, 2);
    lua_Integer column = luaL_checkinteger(L, 3);
    if (row < 1 || row > widget->table->rows || column < 1 || column > widget->table->columns) return false;
    *index = (unsigned)(row - 1) * widget->table->columns + (unsigned)(column - 1);
    return true;
}

/**
 * 更新一个单元格的文本，不改变表格行列数。
 * @api table:set_cell(row, column, text)
 * @int row 必填，行号，范围 1～XML 定义的 rows，包含表头行
 * @int column 必填，列号，范围 1～XML 定义的 columns
 * @string text 必填，UTF-8 文本，可为空，最多 511 字节，不允许 NUL 字节
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 与当前单元格文本相同时直接成功，避免重复分配和行高计算。
 * @note 新文本参与原生换行和行高计算；表格外框尺寸保持不变。
 * @usage
 * local values = xml:find("main", "values")
 * values:set_cell(2, 2, "运行中")
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
    /* 新页面已包含模型中的单元格值；同值更新无需再次分配文本或计算行高。 */
    const char *previous = widget->table->cells[index];
    if (!strcmp(previous ? previous : "", text)) return luat_plcui_binding_success(L);
    char *copy = malloc(length + 1);
    if (!copy) return luat_plcui_binding_error(L, "E_MEMORY", "Cannot allocate cell text");
    memcpy(copy, text, length + 1);
    free(widget->table->cells[index]);
    widget->table->cells[index] = copy;
    lv_table_set_cell_value(widget->obj, index / widget->table->columns, index % widget->table->columns, copy);
    return luat_plcui_binding_success(L);
}

/**
 * 读取指定单元格保存的完整文本。
 * @api table:get_cell(row, column)
 * @int row 必填，行号，范围 1～XML 定义的 rows，包含表头行
 * @int column 必填，列号，范围 1～XML 定义的 columns
 * @return string|nil 成功返回单元格文本，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 未初始化或内容为空的单元格返回空字符串，不返回 nil。
 * @usage
 * local values = xml:find("main", "values")
 * local text = values:get_cell(2, 2)
 * log.info("cell", text)
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
 * 设置指定列的像素宽度。
 * @api table:set_column_width(column, width)
 * @int column 必填，列号，范围 1～XML 定义的 columns
 * @int width 必填，列宽，单位像素，范围 1～4096
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 保持表格外框和其他列宽度不变；列内换行、行高和滚动范围由原生表格重新计算。
 * @note 修改保存到当前文档模型，同一文档切页重建时仍使用此列宽。
 * @usage
 * local values = xml:find("main", "values")
 * values:set_column_width(2, 180)
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
 * 读取 XML 定义的固定行数和列数。
 * @api table:get_size()
 * @return int|nil 成功返回总行数，运行错误返回 nil
 * @return int|table 成功返回总列数，失败返回包含 code、message 的错误表
 * @note 行数包含表头；接口不改变表格结构，也不返回当前可见行列数。
 * @usage
 * local values = xml:find("main", "values")
 * local rows, columns = values:get_size()
 * log.info("table size", rows, columns)
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
 * 设置表格单元格使用的 HZFont 像素字号。
 * @api table:set_font_size(font_size)
 * @int font_size 必填，像素字号，范围 1～255
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 仅适用于 XML 中 font="hzfont" 或引用 HZFont 资源的表格。
 * @note 保持表格位置、外框尺寸及数据不变；字号变化可能影响换行、行高和滚动范围。
 * @usage
 * local values = xml:find("main", "values")
 * values:set_font_size(20)
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

/**
 * 注册 table 的单元格、列宽、结构查询、字号及公共组件方法。
 * @param L Lua 状态机
 * @note 由模块初始化调用，不是公开 Lua 接口；注册完成后恢复原有栈高度。
 */
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
    luat_plcui_binding_register_methods(L, methods);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
