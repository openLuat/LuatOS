/*
@module  easylvgl.xml
@summary EasyLVGL XML 支持 (LVGL 9.4)
@version 0.1.0
@date    2025.12.31
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_binding.h"
#include "../inc/luat_easylvgl_xml.h"

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


