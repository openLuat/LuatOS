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

#define AIRUI_TABLE_MT "airui.table"


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
 * @table config.col_width 可选的列宽数组，支持逐列设置
 * @int config.border_color 可选的边框颜色（Hex 整数，如 0xff0000）
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
 * Table:set_col_width(col, width)
 * @api table:set_col_width(col, width)
 * @int col 列索引（从 0 开始）
 * @int width 宽度（像素）
 * @return nil
 */
static int l_table_set_col_width(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    int col = luaL_checkinteger(L, 2);
    int width = luaL_checkinteger(L, 3);
    airui_table_set_col_width(table, col, width);
    return 0;
}

/**
 * Table:set_border_color(color)
 * @api table:set_border_color(color)
 * @int color 16 进制颜色整数（如 0xff0000）
 * @return nil
 */
static int l_table_set_border_color(lua_State *L) {
    lv_obj_t *table = airui_check_component(L, 1, AIRUI_TABLE_MT);
    lua_Integer raw = luaL_checkinteger(L, 2);
    lv_color_t color = lv_color_hex((uint32_t)raw);
    airui_table_set_border_color(table, color);
    return 0;
}

/**
 * Table:destroy()
 * @api table:destroy()
 * @return nil
 */
static int l_table_destroy(lua_State *L) {
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_TABLE_MT);
    if (ud != NULL && ud->obj != NULL) {
        airui_component_meta_t *meta = airui_component_meta_get(ud->obj);
        if (meta != NULL) {
            airui_component_meta_free(meta);
        }
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

void airui_register_table_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_TABLE_MT);
    static const luaL_Reg methods[] = {
        {"set_cell_text", l_table_set_cell_text},
        {"set_col_width", l_table_set_col_width},
        {"set_border_color", l_table_set_border_color},
        {"destroy", l_table_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_table_create(lua_State *L) {
    return l_airui_table(L);
}

