/*
@module  easylvgl.dropdown
@summary EasyLVGL Dropdown 组件
@version 0.2.0
@date    2025.12.12
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"
#include "lvgl9/src/widgets/dropdown/lv_dropdown.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "easylvgl.dropdown"
#include "luat_log.h"

#define EASYLVGL_DROPDOWN_MT "easylvgl.dropdown"

static int l_easylvgl_dropdown(lua_State *L)
{
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

    lv_obj_t *dropdown = easylvgl_dropdown_create_from_config(L, 1);
    if (dropdown == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, dropdown, EASYLVGL_DROPDOWN_MT);
    return 1;
}

static int l_dropdown_set_selected(lua_State *L)
{
    lv_obj_t *dropdown = easylvgl_check_component(L, 1, EASYLVGL_DROPDOWN_MT);
    int index = luaL_checkinteger(L, 2);
    easylvgl_dropdown_set_selected(dropdown, index);
    return 0;
}

static int l_dropdown_get_selected(lua_State *L)
{
    lv_obj_t *dropdown = easylvgl_check_component(L, 1, EASYLVGL_DROPDOWN_MT);
    int index = easylvgl_dropdown_get_selected(dropdown);
    lua_pushinteger(L, index);
    return 1;
}

static int l_dropdown_set_on_change(lua_State *L)
{
    lv_obj_t *dropdown = easylvgl_check_component(L, 1, EASYLVGL_DROPDOWN_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    easylvgl_dropdown_set_on_change(dropdown, ref);
    return 0;
}

static int l_dropdown_gc(lua_State *L)
{
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_DROPDOWN_MT);
    if (ud != NULL && ud->obj != NULL) {
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
        if (meta != NULL) {
            if (meta->user_data != NULL) {
                luat_heap_free(meta->user_data);
                meta->user_data = NULL;
            }
            easylvgl_component_meta_free(meta);
        }
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

void easylvgl_register_dropdown_meta(lua_State *L)
{
    luaL_newmetatable(L, EASYLVGL_DROPDOWN_MT);

    lua_pushcfunction(L, l_dropdown_gc);
    lua_setfield(L, -2, "__gc");

    static const luaL_Reg methods[] = {
        {"set_selected", l_dropdown_set_selected},
        {"get_selected", l_dropdown_get_selected},
        {"set_on_change", l_dropdown_set_on_change},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int easylvgl_dropdown_create(lua_State *L)
{
    return l_easylvgl_dropdown(L);
}

