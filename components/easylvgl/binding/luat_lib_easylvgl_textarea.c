/*
@module  easylvgl.textarea
@summary EasyLVGL Textarea 组件 Lua 绑定
@version 0.3.0
@date    2025.12.15
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "easylvgl.textarea"
#include "luat_log.h"

/************************************************************************
 * Lua 接口定义
 ************************************************************************/

static int l_easylvgl_textarea(lua_State *L) {
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
    lv_obj_t *textarea = easylvgl_textarea_create_from_config(L, 1);
    if (textarea == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, textarea, EASYLVGL_TEXTAREA_MT);
    return 1;
}

static int l_textarea_set_text(lua_State *L) {
    lv_obj_t *textarea = easylvgl_check_component(L, 1, EASYLVGL_TEXTAREA_MT);
    const char *text = luaL_checkstring(L, 2);
    easylvgl_textarea_set_text(textarea, text);
    return 0;
}

static int l_textarea_get_text(lua_State *L) {
    lv_obj_t *textarea = easylvgl_check_component(L, 1, EASYLVGL_TEXTAREA_MT);
    const char *text = easylvgl_textarea_get_text(textarea);
    lua_pushstring(L, text ? text : "");
    return 1;
}

static int l_textarea_set_cursor(lua_State *L) {
    lv_obj_t *textarea = easylvgl_check_component(L, 1, EASYLVGL_TEXTAREA_MT);
    uint32_t pos = (uint32_t)luaL_checkinteger(L, 2);
    easylvgl_textarea_set_cursor(textarea, pos);
    return 0;
}

static int l_textarea_set_on_change(lua_State *L) {
    lv_obj_t *textarea = easylvgl_check_component(L, 1, EASYLVGL_TEXTAREA_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    easylvgl_textarea_set_on_text_change(textarea, ref);
    return 0;
}

static int l_textarea_attach_keyboard(lua_State *L) {
    lv_obj_t *textarea = easylvgl_check_component(L, 1, EASYLVGL_TEXTAREA_MT);
    lv_obj_t *keyboard = easylvgl_check_component(L, 2, EASYLVGL_KEYBOARD_MT);
    easylvgl_textarea_attach_keyboard(textarea, keyboard);
    return 0;
}

static int l_textarea_get_keyboard(lua_State *L) {
    lv_obj_t *textarea = easylvgl_check_component(L, 1, EASYLVGL_TEXTAREA_MT);
    lv_obj_t *keyboard = easylvgl_textarea_get_keyboard(textarea);
    if (keyboard == NULL) {
        lua_pushnil(L);
        return 1;
    }
    easylvgl_push_component_userdata(L, keyboard, EASYLVGL_KEYBOARD_MT);
    return 1;
}

static int l_textarea_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_TEXTAREA_MT);
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

void easylvgl_register_textarea_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_TEXTAREA_MT);

    lua_pushcfunction(L, l_textarea_gc);
    lua_setfield(L, -2, "__gc");

    static const luaL_Reg functions[] = {
        {"set_text", l_textarea_set_text},
        {"get_text", l_textarea_get_text},
        {"set_cursor", l_textarea_set_cursor},
        {"set_on_text_change", l_textarea_set_on_change},
        {"attach_keyboard", l_textarea_attach_keyboard},
        {"get_keyboard", l_textarea_get_keyboard},
        {NULL, NULL}
    };

    luaL_newlib(L, functions);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int easylvgl_textarea_create(lua_State *L) {
    return l_easylvgl_textarea(L);
}

