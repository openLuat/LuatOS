/*
@module  airui.container
@summary AIRUI Container 组件 Lua 绑定
@version 0.1.0
@date    2025.12.25
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define AIRUI_CONTAINER_MT "airui.container"

/**
 * 创建 Container 组件
 * @api airui.container(config)
 */
static int l_airui_container(lua_State *L) {
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

    lv_obj_t *container = airui_container_create_from_config(L, 1);
    if (container == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, container, AIRUI_CONTAINER_MT);
    return 1;
}

/**
 * Container:set_color(color[, opacity])
 * @api container:set_color(color, opacity?)
 * @int color 背景色（0xRRGGBB）
 * @int opacity 透明度（0-255），默认 `LV_OPA_COVER`
 */
static int l_container_set_color(lua_State *L) {
    lv_obj_t *container = airui_check_component(L, 1, AIRUI_CONTAINER_MT);
    uint32_t color = (uint32_t)luaL_checkinteger(L, 2);
    int opacity = luaL_optinteger(L, 3, LV_OPA_COVER);
    airui_container_set_color(container, color, opacity);
    return 0;
}

/**
 * Container:set_border_color(color[, width])
 * @api container:set_border_color(color, width?)
 * @int color 边框颜色（0xRRGGBB）
 * @int width 边框宽度（默认 1）
 */
static int l_container_set_border_color(lua_State *L) {
    lv_obj_t *container = airui_check_component(L, 1, AIRUI_CONTAINER_MT);
    uint32_t color = (uint32_t)luaL_checkinteger(L, 2);
    int width = luaL_optinteger(L, 3, 1);
    airui_container_set_border_color(container, color, width);
    return 0;
}

/**
 * Container:set_hidden(hidden)
 * @api container:set_hidden(hidden)
 * @bool hidden 是否隐藏
 */
static int l_container_set_hidden(lua_State *L) {
    lv_obj_t *container = airui_check_component(L, 1, AIRUI_CONTAINER_MT);
    bool hidden = lua_toboolean(L, 2);
    airui_container_set_hidden(container, hidden);
    return 0;
}

/**
 * Container:hide()
 */
static int l_container_hide(lua_State *L) {
    lv_obj_t *container = airui_check_component(L, 1, AIRUI_CONTAINER_MT);
    airui_container_set_hidden(container, true);
    return 0;
}

/**
 * Container:open()
 */
static int l_container_open(lua_State *L) {
    lv_obj_t *container = airui_check_component(L, 1, AIRUI_CONTAINER_MT);
    airui_container_open(container);
    return 0;
}


/**
 * Container:destroy()
 */
static int l_container_destroy(lua_State *L) {
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_CONTAINER_MT);
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

/**
 * 注册 Container 元表
 */
void airui_register_container_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_CONTAINER_MT);
    // lua_pushcfunction(L, l_container_gc);
    // lua_setfield(L, -2, "__gc");

    static const luaL_Reg methods[] = {
        {"set_color", l_container_set_color},
        {"set_border_color", l_container_set_border_color},
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
int airui_container_create(lua_State *L) {
    return l_airui_container(L);
}

