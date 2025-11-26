#include "easylvgl_component.h"
#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"

static bool read_integer_field(lua_State *L, int table_index, const char *key, int *out) {
    const int abs_index = lua_absindex(L, table_index);
    lua_getfield(L, abs_index, key);
    bool ok = false;
    if (lua_isinteger(L, -1)) {
        *out = (int)lua_tointeger(L, -1);
        ok = true;
    }
    lua_pop(L, 1);
    return ok;
}

lv_obj_t *easylvgl_component_get_lv_obj_from_value(lua_State *L, int index) {
    if (lua_isnoneornil(L, index)) {
        return NULL;
    }

    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_testudata(L, index, EASYLVGL_BUTTON_MT);
    if (ud != NULL && ud->obj != NULL) {
        return ud->obj;
    }

    ud = (easylvgl_component_ud_t *)luaL_testudata(L, index, EASYLVGL_LABEL_MT);
    if (ud != NULL && ud->obj != NULL) {
        return ud->obj;
    }

    if (lua_islightuserdata(L, index)) {
        return (lv_obj_t *)lua_touserdata(L, index);
    }

    return NULL;
}

lv_obj_t *easylvgl_component_get_parent_from_table(lua_State *L, int table_index) {
    const int abs_index = lua_absindex(L, table_index);
    lv_obj_t *parent = NULL;
    lua_getfield(L, abs_index, "parent");
    parent = easylvgl_component_get_lv_obj_from_value(L, -1);
    lua_pop(L, 1);
    return parent;
}

const char *easylvgl_component_get_string_field(lua_State *L, int table_index, const char *key) {
    const int abs_index = lua_absindex(L, table_index);
    lua_getfield(L, abs_index, key);
    const char *value = NULL;
    if (lua_isstring(L, -1)) {
        value = lua_tostring(L, -1);
    }
    lua_pop(L, 1);
    return value;
}

void easylvgl_component_apply_geometry(lua_State *L, int table_index, lv_obj_t *obj) {
    int value = 0;
    if (read_integer_field(L, table_index, "x", &value)) {
        lv_obj_set_x(obj, value);
    }
    if (read_integer_field(L, table_index, "y", &value)) {
        lv_obj_set_y(obj, value);
    }
    if (read_integer_field(L, table_index, "w", &value)) {
        lv_obj_set_width(obj, value);
    }
    if (read_integer_field(L, table_index, "h", &value)) {
        lv_obj_set_height(obj, value);
    }
}

int easylvgl_component_capture_callback(lua_State *L, int table_index, const char *key) {
    const int abs_index = lua_absindex(L, table_index);
    int ref = LUA_NOREF;
    lua_getfield(L, abs_index, key);
    if (lua_isfunction(L, -1)) {
        lua_pushvalue(L, -1);
        ref = luaL_ref(L, LUA_REGISTRYINDEX);
        lua_pop(L, 1);
    } else {
        lua_pop(L, 1);
    }
    return ref;
}

