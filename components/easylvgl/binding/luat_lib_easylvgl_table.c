/*
@module  easylvgl.table
@summary EasyLVGL Table 组件
@version 0.1.0
@date    2025.12.26
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"

#define EASYLVGL_TABLE_MT "easylvgl.table"

static int l_easylvgl_table(lua_State *L) {
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);

    if (ctx == NULL) {
        luaL_error(L, "easylvgl not initialized, call easylvgl.init() first");
        return 0;
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lv_obj_t *table = easylvgl_table_create_from_config(L, 1);
    if (table == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, table, EASYLVGL_TABLE_MT);
    return 1;
}

static int l_table_set_cell_text(lua_State *L) {
    lv_obj_t *table = easylvgl_check_component(L, 1, EASYLVGL_TABLE_MT);
    int row = luaL_checkinteger(L, 2);
    int col = luaL_checkinteger(L, 3);
    const char *text = luaL_optstring(L, 4, "");
    easylvgl_table_set_cell_text(table, row, col, text);
    return 0;
}

static int l_table_set_col_width(lua_State *L) {
    lv_obj_t *table = easylvgl_check_component(L, 1, EASYLVGL_TABLE_MT);
    int col = luaL_checkinteger(L, 2);
    int width = luaL_checkinteger(L, 3);
    easylvgl_table_set_col_width(table, col, width);
    return 0;
}

static int l_table_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_TABLE_MT);
    if (ud != NULL && ud->obj != NULL) {
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
        if (meta != NULL) {
            easylvgl_component_meta_free(meta);
        }
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

void easylvgl_register_table_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_TABLE_MT);
    lua_pushcfunction(L, l_table_gc);
    lua_setfield(L, -2, "__gc");

    static const luaL_Reg methods[] = {
        {"set_cell_text", l_table_set_cell_text},
        {"set_col_width", l_table_set_col_width},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int easylvgl_table_create(lua_State *L) {
    return l_easylvgl_table(L);
}

