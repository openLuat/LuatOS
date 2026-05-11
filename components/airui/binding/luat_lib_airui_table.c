/*
@module  airui.table
@summary AIRUI Table 组件
@version 0.1.0
@date    2025.12.26
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#include <string.h>

#define AIRUI_TABLE_MT "airui.table"

static void airui_table_fill_row_from_lua(lua_State *L, lv_obj_t *table, int row, int idx);
static void airui_table_fill_col_from_lua(lua_State *L, lv_obj_t *table, int col, int idx);
static airui_table_scroll_action_t airui_table_parse_scroll_action(lua_State *L, int idx);
static int airui_table_parse_axis(lua_State *L, int idx, bool *is_row);

/**
 * 创建 Table 组件
 * @api airui.table(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 200
 * @int config.h 高度，默认 120
 * @int config.rows 行数，默认 4，最小 1
 * @int config.cols 列数，默认 3，最小 1
 * @table config.data 可选的二维表内容，按 { {"r0c0", "r0c1"}, {"r1c0", "r1c1"} } 传入
 * @int|table config.row_height 可选的行高设置，支持单个高度或逐行数组
 * @table config.col_width 可选的列宽数组，支持逐列设置
 * @table config.style 可选样式配置
 * @int config.style.bg_color 表格背景色（0xRRGGBB）
 * @int config.style.bg_opa 表格背景透明度（0-255）
 * @int config.style.border_color 表格边框颜色（0xRRGGBB）
 * @int config.style.border_width 表格边框宽度，设为 0 可隐藏外边框
 * @int config.style.radius 表格圆角半径
 * @int config.style.cell_bg_color 单元格背景色（0xRRGGBB）
 * @int config.style.cell_bg_opa 单元格背景透明度（0-255）
 * @int config.style.cell_border_color 单元格边框颜色（0xRRGGBB）
 * @int config.style.cell_border_width 单元格边框宽度，设为 0 可隐藏内部网格线
 * @int config.style.cell_text_color 单元格文字颜色（0xRRGGBB）
 * @int config.style.cell_text_align 单元格水平对齐，支持 airui.TEXT_ALIGN_LEFT/CENTER/RIGHT
 * @string config.style.cell_vertical_align 单元格垂直对齐，支持 "top"/"center"
 * @int config.style.cell_font_size 单元格字体大小，使用 hzfont 时生效
 * @int config.style.selected_cell_bg_color 选中单元格背景色（0xRRGGBB）
 * @int config.style.selected_cell_bg_opa 选中单元格背景透明度（0-255）
 * @int config.style.selected_cell_border_color 选中单元格边框颜色（0xRRGGBB）
 * @int config.style.selected_cell_text_color 选中单元格文字颜色（0xRRGGBB）
 * @int config.border_color 可选的边框颜色（Hex 整数，如 0xff0000）
 * @function config.on_click 单元格点击回调函数，参数为 (self, row, col, value) 
 * @userdata config.parent 父对象，默认当前屏幕
 * @return userdata Table 对象
 */
static int l_airui_table(lua_State *L) {
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

    lv_obj_t *table = airui_table_create_from_config(L, 1);
    if (table == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, table, AIRUI_TABLE_MT);
    return 1;
}

/**
 * Table:set_cell_text(row, col, text)
 * @api table:set_cell_text(row, col, text)
 * @int row 行索引（从 0 开始）
 * @int col 列索引（从 0 开始）
 * @string text 单元格文本
 * @return nil
 * @usage
 * tbl:set_cell_text(0, 0, "hello")
 */
static int l_table_set_cell_text(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    int row = luaL_checkinteger(L, 2);
    int col = luaL_checkinteger(L, 3);
    const char *text = luaL_optstring(L, 4, "");
    airui_table_set_cell_text(table, row, col, text);
    return 0;
}

/**
 * Table:get_cell_text(row, col)
 * @api table:get_cell_text(row, col)
 * @int row 行索引（从 0 开始）
 * @int col 列索引（从 0 开始）
 * @return string 单元格文本
 * @usage
 * local text = tbl:get_cell_text(0, 0)
 */
static int l_table_get_cell_text(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    int row = luaL_checkinteger(L, 2);
    int col = luaL_checkinteger(L, 3);
    const char *text = airui_table_get_cell_text(table, row, col);
    lua_pushstring(L, text ? text : "");
    return 1;
}

/**
 * Table:set_on_cell_click(callback)
 * @api table:set_on_cell_click(callback)
 * @function callback 回调函数 function(row, col, value) row/col 从 0 开始
 * @return nil
 * @usage
 * tbl:set_on_cell_click(function(row, col, value)
 *     log.info("table", "clicked cell", row, col, value)
 * end)
 */
static int l_table_set_on_cell_click(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    airui_table_set_on_cell_click(table, ref);
    return 0;
}

/**
 * Table:set_col_width(col, width)
 * @api table:set_col_width(col, width)
 * @int col 列索引（从 0 开始）
 * @int width 宽度（像素）
 * @return nil
 * @usage
 * tbl:set_col_width(1, 120)
 */
static int l_table_set_col_width(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    int col = luaL_checkinteger(L, 2);
    int width = luaL_checkinteger(L, 3);
    airui_table_set_col_width(table, col, width);
    return 0;
}

/**
 * Table:set_row_height(row, height)
 * @api table:set_row_height(row, height)
 * @int row 行索引（从 0 开始）
 * @int height 高度（像素）
 * @return nil
 * @usage
 * tbl:set_row_height(0, 40)
 */
static int l_table_set_row_height(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    int row = luaL_checkinteger(L, 2);
    int height = luaL_checkinteger(L, 3);
    airui_table_set_row_height(table, row, height);
    return 0;
}

/**
 * Table:set_border_color(color)
 * @api table:set_border_color(color)
 * @int color 16 进制颜色整数（如 0xff0000）
 * @return nil
 * @usage
 * tbl:set_border_color(0xff0000)
 */
static int l_table_set_border_color(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    lua_Integer raw = luaL_checkinteger(L, 2);
    lv_color_t color = lv_color_hex((uint32_t)raw);
    airui_table_set_border_color(table, color);
    return 0;
}

/**
 * Table:set_style(style)
 * @api table:set_style(style)
 * @table style 样式表，仅覆盖传入字段
 * @int style.bg_color 表格背景色（0xRRGGBB）
 * @int style.bg_opa 表格背景透明度（0-255）
 * @int style.border_color 表格边框颜色（0xRRGGBB）
 * @int style.border_width 表格边框宽度，设为 0 可隐藏外边框
 * @int style.radius 表格圆角半径
 * @int style.cell_bg_color 单元格背景色（0xRRGGBB）
 * @int style.cell_bg_opa 单元格背景透明度（0-255）
 * @int style.cell_border_color 单元格边框颜色（0xRRGGBB）
 * @int style.cell_border_width 单元格边框宽度，设为 0 可隐藏内部网格线
 * @int style.cell_text_color 单元格文字颜色（0xRRGGBB）
 * @int style.cell_text_align 单元格水平对齐，支持 airui.TEXT_ALIGN_LEFT/CENTER/RIGHT
 * @string style.cell_vertical_align 单元格垂直对齐，支持 "top"/"center"
 * @int style.cell_font_size 单元格字体大小，使用 hzfont 时生效
 * @int style.selected_cell_bg_color 选中单元格背景色（0xRRGGBB）
 * @int style.selected_cell_bg_opa 选中单元格背景透明度（0-255）
 * @int style.selected_cell_border_color 选中单元格边框颜色（0xRRGGBB）
 * @int style.selected_cell_text_color 选中单元格文字颜色（0xRRGGBB）
 * @return nil
 * @usage
 * tbl:set_style({ bg_color = 0xffffff, cell_text_color = 0x333333, radius = 6 })
 */
static int l_table_set_style(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    airui_table_set_style(table, L, 2);
    return 0;
}

/**
 * Table:set_cell_style(axis, index, style)
 * @api table:set_cell_style(axis, index, style)
 * @string axis 作用维度，支持 row/col
 * @int index 行或列索引（从 0 开始）
 * @table style 指定行或列的单元格样式，仅支持下列字段
 * @int style.cell_bg_color 单元格背景色（0xRRGGBB）
 * @int style.cell_border_color 单元格边框颜色（0xRRGGBB）
 * @int style.cell_text_color 单元格文字颜色（0xRRGGBB）
 * @return nil
 * @usage
 * tbl:set_cell_style("row", 1, { cell_text_color = 0xff0000 })
 * tbl:set_cell_style("col", 0, { cell_bg_color = 0xeeeeee, cell_border_color = 0xcccccc })
 */
static int l_table_set_cell_style(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    bool is_row = true;
    airui_table_parse_axis(L, 2, &is_row);
    int index = luaL_checkinteger(L, 3);
    if (index < 0) {
        luaL_error(L, "index must be >= 0");
        return 0;
    }
    luaL_checktype(L, 4, LUA_TTABLE);
    airui_table_set_cell_style(table, is_row, (uint16_t)index, L, 4);
    return 0;
}

static int airui_table_insert_impl(lua_State *L, bool is_row, int index_arg, int data_arg, int size_arg) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    int index = luaL_checkinteger(L, index_arg);
    if (index < 0) {
        index = 0;
    }

    airui_table_insert(table, is_row, (uint16_t)index);
    if (!lua_isnoneornil(L, data_arg)) {
        luaL_checktype(L, data_arg, LUA_TTABLE);
        if (is_row) {
            airui_table_fill_row_from_lua(L, table, index, data_arg);
        }
        else {
            airui_table_fill_col_from_lua(L, table, index, data_arg);
        }
    }

    if (!lua_isnoneornil(L, size_arg)) {
        int size = luaL_checkinteger(L, size_arg);
        if (is_row) {
            airui_table_set_row_height(table, (uint16_t)index, size);
        }
        else {
            airui_table_set_col_width(table, (uint16_t)index, size);
        }
    }
    return 0;
}

/**
 * Table:insert(axis, index, data[, size])
 * @api table:insert(axis, index, data[, size])
 * @string axis 插入维度，支持 row/col
 * @int index 插入位置（从 0 开始）
 * @table data 行数据或列数据
 * @int size 可选尺寸，row 时表示行高，col 时表示列宽
 * @return nil
 * @usage
 * tbl:insert("row", 1, { "新行A", "新行B", "新行C" }, 36)
 * tbl:insert("col", 2, { "c2r0", "c2r1", "c2r2" }, 100)
 */
static int l_table_insert(lua_State *L) {
    bool is_row = true;
    airui_table_parse_axis(L, 2, &is_row);
    return airui_table_insert_impl(L, is_row, 3, 4, 5);
}

/**
 * Table:remove(axis, index[, count])
 * @api table:remove(axis, index[, count])
 * @string axis 移除维度，支持 row/col
 * @int index 起始位置（从 0 开始）
 * @int count 可选数量，默认 1
 * @return nil
 * @usage
 * tbl:remove("row", 2)
 * tbl:remove("col", 0, 2)
 */
static int l_table_remove(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    bool is_row = true;
    airui_table_parse_axis(L, 2, &is_row);
    int index = luaL_checkinteger(L, 3);
    int count = luaL_optinteger(L, 4, 1);
    if (index < 0 || count < 1) {
        luaL_error(L, "index/count must be valid");
        return 0;
    }
    airui_table_remove(table, is_row, (uint16_t)index, (uint16_t)count);
    return 0;
}

/**
 * Table:auto_jump_scroll_control(config)
 * @api table:auto_jump_scroll_control(config)
 * @table config 控制配置
 * @string config.action 控制动作，支持 start/pause/resume/stop
 * @int config.interval start 时可选，滚动间隔（毫秒），默认 1500，表示每次跳转到下一批行之前的停留时间
 * @boolean config.loop start 时可选，是否循环滚动，默认 true，true 表示滚动到最后一行后回到首行继续
 * @boolean config.anim start 时可选，是否使用动画，默认 true，true 表示按行平滑滚动，false 表示直接跳转
 * @int config.step start 时可选，每次前进的行数，默认 1，例如 1 表示逐行滚动，2 表示每次跳过 1 行
 * @int config.focus_col start 时可选，自动滚动使用的焦点列，默认 0，滚动到目标行时会以该列单元格作为定位参考
 * @return nil
 * @usage
 * tbl:auto_jump_scroll_control({ action = "start", interval = 1500, loop = true, anim = true, step = 1, focus_col = 0 })
 * tbl:auto_jump_scroll_control({ action = "pause" })
 * tbl:auto_jump_scroll_control({ action = "stop" })
 */
static int l_table_auto_jump_scroll_control(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    uint32_t interval = 1500;
    bool loop = true;
    bool anim = true;
    uint16_t step = 1;
    uint16_t focus_col = 0;

    luaL_checktype(L, 2, LUA_TTABLE);
    lua_getfield(L, 2, "action");
    airui_table_scroll_action_t action = airui_table_parse_scroll_action(L, -1);
    lua_pop(L, 1);

    if (action == AIRUI_TABLE_SCROLL_ACTION_START) {
        lua_getfield(L, 2, "interval");
        if (lua_isnumber(L, -1)) {
            interval = (uint32_t)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "loop");
        if (!lua_isnil(L, -1)) {
            loop = lua_toboolean(L, -1);
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "anim");
        if (!lua_isnil(L, -1)) {
            anim = lua_toboolean(L, -1);
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "step");
        if (lua_isnumber(L, -1)) {
            step = (uint16_t)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "focus_col");
        if (lua_isnumber(L, -1)) {
            focus_col = (uint16_t)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
    }

    airui_table_auto_jump_scroll_control(table, action, interval, loop, anim, step, focus_col);
    return 0;
}

/**
 * Table:auto_marquee_scroll_control(config)
 * @api table:auto_marquee_scroll_control(config)
 * @table config 控制配置
 * @string config.action 控制动作，支持 start/pause/resume/stop
 * @int config.interval start 时可选，滚动 tick 间隔（毫秒），默认 30，数值越小滚动更新越频繁
 * @boolean config.loop start 时可选，是否循环滚动，默认 true，true 表示到底部后回到顶部继续跑马灯滚动
 * @int config.speed start 时可选，每次 tick 的滚动像素，默认 1，数值越大滚动越快
 * @return nil
 * @usage
 * tbl:auto_marquee_scroll_control({ action = "start", interval = 30, loop = true, speed = 2 })
 * tbl:auto_marquee_scroll_control({ action = "resume" })
 * tbl:auto_marquee_scroll_control({ action = "stop" })
 */
static int l_table_auto_marquee_scroll_control(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    uint32_t interval = 30;
    bool loop = true;
    uint16_t speed = 1;

    luaL_checktype(L, 2, LUA_TTABLE);
    lua_getfield(L, 2, "action");
    airui_table_scroll_action_t action = airui_table_parse_scroll_action(L, -1);
    lua_pop(L, 1);

    if (action == AIRUI_TABLE_SCROLL_ACTION_START) {
        lua_getfield(L, 2, "interval");
        if (lua_isnumber(L, -1)) {
            interval = (uint32_t)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "loop");
        if (!lua_isnil(L, -1)) {
            loop = lua_toboolean(L, -1);
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "speed");
        if (lua_isnumber(L, -1)) {
            speed = (uint16_t)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
    }

    airui_table_auto_marquee_scroll_control(table, action, interval, loop, speed);
    return 0;
}

/**
 * Table:destroy()
 * @api table:destroy()
 * @return nil
 * @usage
 * tbl:destroy()
 */
static int l_table_destroy(lua_State *L) {
    return airui_component_destroy_userdata(L, 1, AIRUI_TABLE_MT);
}

static void airui_table_fill_row_from_lua(lua_State *L, lv_obj_t *table, int row, int idx) {
    if (!lua_istable(L, idx)) {
        return;
    }

    size_t col_count = lua_rawlen(L, idx);
    for (size_t col = 0; col < col_count; col++) {
        lua_rawgeti(L, idx, (lua_Integer)(col + 1));
        if (!lua_isnil(L, -1)) {
            size_t text_len = 0;
            const char *text = luaL_tolstring(L, -1, &text_len);
            airui_table_set_cell_text(table, (uint16_t)row, (uint16_t)col, text ? text : "");
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }
}

static void airui_table_fill_col_from_lua(lua_State *L, lv_obj_t *table, int col, int idx) {
    if (!lua_istable(L, idx)) {
        return;
    }

    size_t row_count = lua_rawlen(L, idx);
    for (size_t row = 0; row < row_count; row++) {
        lua_rawgeti(L, idx, (lua_Integer)(row + 1));
        if (!lua_isnil(L, -1)) {
            size_t text_len = 0;
            const char *text = luaL_tolstring(L, -1, &text_len);
            airui_table_set_cell_text(table, (uint16_t)row, (uint16_t)col, text ? text : "");
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }
}

static airui_table_scroll_action_t airui_table_parse_scroll_action(lua_State *L, int idx) {
    const char *action = luaL_checkstring(L, idx);
    if (!strcmp(action, "start")) {
        return AIRUI_TABLE_SCROLL_ACTION_START;
    }
    if (!strcmp(action, "pause")) {
        return AIRUI_TABLE_SCROLL_ACTION_PAUSE;
    }
    if (!strcmp(action, "resume")) {
        return AIRUI_TABLE_SCROLL_ACTION_RESUME;
    }
    if (!strcmp(action, "stop")) {
        return AIRUI_TABLE_SCROLL_ACTION_STOP;
    }

    luaL_error(L, "unsupported auto_scroll action: %s", action);
    return AIRUI_TABLE_SCROLL_ACTION_STOP;
}

static int airui_table_parse_axis(lua_State *L, int idx, bool *is_row) {
    const char *axis = luaL_checkstring(L, idx);
    if (!strcmp(axis, "row")) {
        *is_row = true;
        return 0;
    }
    if (!strcmp(axis, "col")) {
        *is_row = false;
        return 0;
    }
    return luaL_error(L, "unsupported axis: %s", axis);
}

void airui_register_table_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_TABLE_MT);
    static const luaL_Reg methods[] = {
        {"set_cell_text", l_table_set_cell_text},
        {"get_cell_text", l_table_get_cell_text},
        {"set_cell_style", l_table_set_cell_style},
        {"set_col_width", l_table_set_col_width},
        {"set_row_height", l_table_set_row_height},
        {"set_style", l_table_set_style},
        {"set_border_color", l_table_set_border_color},
        {"insert", l_table_insert},
        {"remove", l_table_remove},
        {"auto_jump_scroll_control", l_table_auto_jump_scroll_control},
        {"auto_marquee_scroll_control", l_table_auto_marquee_scroll_control},
        {"set_on_cell_click", l_table_set_on_cell_click},
        {"destroy", l_table_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_table_create(lua_State *L) {
    return l_airui_table(L);
}

