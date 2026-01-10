/*
@module  easylvgl.container
@summary EasyLVGL Container 组件 Lua 绑定
@version 0.1.0
@date    2025.12.25
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"

#define EASYLVGL_CONTAINER_MT "easylvgl.container"

/**
 * 创建 Container 组件
 * @api easylvgl.container(config)
 */
static int l_easylvgl_container(lua_State *L) {
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

    lv_obj_t *container = easylvgl_container_create_from_config(L, 1);
    if (container == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, container, EASYLVGL_CONTAINER_MT);
    return 1;
}

/**
 * Container:set_color(color)
 * @api container:set_color(color)
 * @int color 背景色（0xRRGGBB）
 */
static int l_container_set_color(lua_State *L) {
    lv_obj_t *container = easylvgl_check_component(L, 1, EASYLVGL_CONTAINER_MT);
    uint32_t color = (uint32_t)luaL_checkinteger(L, 2);
    easylvgl_container_set_color(container, color);
    return 0;
}

/**
 * Container:set_hidden(hidden)
 * @api container:set_hidden(hidden)
 * @bool hidden 是否隐藏
 */
static int l_container_set_hidden(lua_State *L) {
    lv_obj_t *container = easylvgl_check_component(L, 1, EASYLVGL_CONTAINER_MT);
    bool hidden = lua_toboolean(L, 2);
    easylvgl_container_set_hidden(container, hidden);
    return 0;
}

/**
 * Container:hide()
 */
static int l_container_hide(lua_State *L) {
    lv_obj_t *container = easylvgl_check_component(L, 1, EASYLVGL_CONTAINER_MT);
    easylvgl_container_set_hidden(container, true);
    return 0;
}

/**
 * Container:open()
 */
static int l_container_open(lua_State *L) {
    lv_obj_t *container = easylvgl_check_component(L, 1, EASYLVGL_CONTAINER_MT);
    easylvgl_container_open(container);
    return 0;
}


/**
 * Container:destroy()
 */
static int l_container_destroy(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_CONTAINER_MT);
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

/**
 * 注册 Container 元表
 */
void easylvgl_register_container_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_CONTAINER_MT);
    // lua_pushcfunction(L, l_container_gc);
    // lua_setfield(L, -2, "__gc");

    static const luaL_Reg methods[] = {
        {"set_color", l_container_set_color},
        {"set_hidden", l_container_set_hidden},
        {"hide", l_container_hide},
        {"open", l_container_open},
        {"destroy", l_container_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Container 创建函数（供主模块注册）
 */
int easylvgl_container_create(lua_State *L) {
    return l_easylvgl_container(L);
}

