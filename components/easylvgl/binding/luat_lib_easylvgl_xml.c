/*
@module  easylvgl.xml
@summary EasyLVGL XML 支持 (LVGL 9.4)
@version 0.1.0
@date    2025.12.31
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#define LUAT_LOG_TAG "easylvgl.xml"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_malloc.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_binding.h"
#include "../inc/luat_easylvgl_xml.h"

typedef struct {
    lua_State *L;
    int lua_ref;
} easylvgl_xml_event_ref_t;

static void easylvgl_xml_event_trampoline(lv_event_t *event);
static void easylvgl_xml_event_release(lv_event_t *event);
static void l_push_xml_disabled(lua_State *L);

int l_easylvgl_xml_init(lua_State *L) {
    (void)L;
    easylvgl_xml_init();
    return 0;
}

int l_easylvgl_xml_deinit(lua_State *L) {
    (void)L;
    easylvgl_xml_deinit();
    return 0;
}

int l_easylvgl_xml_register_from_file(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    if (!easylvgl_xml_register_from_file(path)) {
        l_push_xml_disabled(L);
        return 1;
    }
    lua_pushboolean(L, 1);
    return 1;
}

int l_easylvgl_xml_register_from_data(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    const char *data = luaL_checkstring(L, 2);
    if (!easylvgl_xml_register_from_data(name, data)) {
        l_push_xml_disabled(L);
        return 1;
    }
    lua_pushboolean(L, 1);
    return 1;
}

int l_easylvgl_xml_register_image(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    const void *src = NULL;
    if (!lua_isnoneornil(L, 2)) {
        if (lua_isstring(L, 2)) {
            src = lua_tostring(L, 2);
        }
        else {
            src = lua_touserdata(L, 2);
        }
    }

    if (src == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "xml_register_image: src is nil or unsupported type");
        return 2;
    }

    if (!easylvgl_xml_register_image(name, src)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "xml_register_image: registration failed");
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}

int l_easylvgl_xml_create_screen(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    lv_obj_t *screen = easylvgl_xml_create_screen(name);
    if (screen == NULL) {
        lua_pushnil(L);
        return 1;
    }
    easylvgl_push_component_userdata(L, screen, EASYLVGL_CONTAINER_MT);
    return 1;
}

int l_easylvgl_xml_bind_event(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    lv_event_code_t code = (lv_event_code_t)luaL_optinteger(L, 2, LV_EVENT_CLICKED);
    luaL_checktype(L, 3, LUA_TFUNCTION);

    lv_obj_t *target = easylvgl_xml_find_object(name);
    if (target == NULL) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "xml_bind_event: object '%s' not found", name);
        return 2;
    }

    easylvgl_xml_event_ref_t *ref = (easylvgl_xml_event_ref_t *)luat_heap_malloc(sizeof(*ref));
    if (ref == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "xml_bind_event: allocation failed");
        return 2;
    }

    lua_pushvalue(L, 3);
    ref->lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    ref->L = L;

    lv_obj_add_event_cb(target, easylvgl_xml_event_trampoline, code, ref);
    lv_obj_add_event_cb(target, easylvgl_xml_event_release, LV_EVENT_DELETE, ref);

    lua_pushboolean(L, 1);
    return 1;
}

static void easylvgl_xml_event_trampoline(lv_event_t *event) {
    easylvgl_xml_event_ref_t *ref = lv_event_get_user_data(event);
    if (ref == NULL || ref->lua_ref == LUA_REFNIL) {
        return;
    }
    lua_State *L = ref->L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref->lua_ref);
    if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
        const char *msg = lua_tostring(L, -1);
        LLOGE("xml event callback error: %s", msg ? msg : "unknown");
        lua_pop(L, 1);
    }
}

static void easylvgl_xml_event_release(lv_event_t *event) {
    easylvgl_xml_event_ref_t *ref = lv_event_get_user_data(event);
    if (ref == NULL) {
        return;
    }
    luaL_unref(ref->L, LUA_REGISTRYINDEX, ref->lua_ref);
    luat_heap_free(ref);
}

static void l_push_xml_disabled(lua_State *L) {
    lua_pushboolean(L, 0);
}


