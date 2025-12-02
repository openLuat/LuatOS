#define LUAT_LOG_TAG "easylvgl_component"
#include "easylvgl_component.h"
#include "luat_log.h"
#include "../lvgl9/lvgl.h"
#include "../lvgl9/src/widgets/image/lv_image.h"
#include "../lvgl9/src/widgets/win/lv_win.h"
#include "../lvgl9/src/widgets/label/lv_label.h"
#include "../lvgl9/src/widgets/button/lv_button.h"

static lua_State *s_lua_state = NULL;

static bool easylvgl_component_read_integer(lua_State *L, int table_index, const char *key, int *out) {
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

static bool easylvgl_component_read_point(lua_State *L, int table_index, const char *key, lv_point_t *out) {
    const int abs_index = lua_absindex(L, table_index);
    lua_getfield(L, abs_index, key);
    bool ok = false;
    if (lua_istable(L, -1)) {
        int x = 0;
        int y = 0;
        if (easylvgl_component_read_integer(L, lua_gettop(L), "x", &x) &&
            easylvgl_component_read_integer(L, lua_gettop(L), "y", &y)) {
            if (out != NULL) {
                out->x = x;
                out->y = y;
            }
            ok = true;
        }
    }
    lua_pop(L, 1);
    return ok;
}

void easylvgl_set_lua_state(lua_State *L) {
    s_lua_state = L;
}

lua_State *easylvgl_get_lua_state(void) {
    return s_lua_state;
}

static easylvgl_component_meta_t *easylvgl_component_alloc_meta(void) {
    easylvgl_component_meta_t *meta = (easylvgl_component_meta_t *)luat_heap_malloc(sizeof(easylvgl_component_meta_t));
    if (meta != NULL) {
        meta->callback_ref = LUA_NOREF;
        meta->title = NULL;
        meta->content = NULL;
        meta->flags = 0;
    }
    return meta;
}

easylvgl_component_meta_t *easylvgl_component_get_meta(lv_obj_t *obj) {
    if (obj == NULL) return NULL;
    return (easylvgl_component_meta_t *)lv_obj_get_user_data(obj);
}

easylvgl_component_meta_t *easylvgl_component_ensure_meta(lv_obj_t *obj) {
    if (obj == NULL) return NULL;
    easylvgl_component_meta_t *meta = easylvgl_component_get_meta(obj);
    if (meta == NULL) {
        meta = easylvgl_component_alloc_meta();
        if (meta == NULL) {
            LLOGE("Failed to allocate component metadata");
            return NULL;
        }
        lv_obj_set_user_data(obj, meta);
    }
    return meta;
}

void easylvgl_component_release_meta(lv_obj_t *obj) {
    if (obj == NULL) return;
    easylvgl_component_meta_t *meta = easylvgl_component_get_meta(obj);
    if (meta == NULL) return;
    if (s_lua_state != NULL && meta->callback_ref != LUA_NOREF) {
        luaL_unref(s_lua_state, LUA_REGISTRYINDEX, meta->callback_ref);
    }
    luat_heap_free(meta);
    lv_obj_set_user_data(obj, NULL);
}

void easylvgl_component_set_callback_ref(lv_obj_t *obj, int callback_ref) {
    if (obj == NULL) return;
    easylvgl_component_meta_t *meta = easylvgl_component_ensure_meta(obj);
    if (meta == NULL) return;
    if (s_lua_state != NULL && meta->callback_ref != LUA_NOREF) {
        luaL_unref(s_lua_state, LUA_REGISTRYINDEX, meta->callback_ref);
    }
    meta->callback_ref = callback_ref;
}

void easylvgl_component_call_callback(lv_obj_t *obj) {
    if (obj == NULL) return;
    easylvgl_component_meta_t *meta = easylvgl_component_get_meta(obj);
    if (meta == NULL || meta->callback_ref == LUA_NOREF) return;
    lua_State *L = easylvgl_get_lua_state();
    if (L == NULL) {
        return;
    }
    lua_rawgeti(L, LUA_REGISTRYINDEX, meta->callback_ref);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1);
        return;
    }
    lua_pushlightuserdata(L, obj);
    if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
        LLOGE("Error calling component callback: %s", lua_tostring(L, -1));
        lua_pop(L, 1);
    }
}

void easylvgl_component_set_title(lv_obj_t *obj, lv_obj_t *title) {
    easylvgl_component_meta_t *meta = easylvgl_component_ensure_meta(obj);
    if (meta != NULL) {
        meta->title = title;
    }
}

lv_obj_t *easylvgl_component_get_title(lv_obj_t *obj) {
    easylvgl_component_meta_t *meta = easylvgl_component_get_meta(obj);
    return meta == NULL ? NULL : meta->title;
}

void easylvgl_component_set_content(lv_obj_t *obj, lv_obj_t *content) {
    easylvgl_component_meta_t *meta = easylvgl_component_ensure_meta(obj);
    if (meta != NULL) {
        meta->content = content;
    }
}

lv_obj_t *easylvgl_component_get_content(lv_obj_t *obj) {
    easylvgl_component_meta_t *meta = easylvgl_component_get_meta(obj);
    return meta == NULL ? NULL : meta->content;
}

bool easylvgl_component_get_integer_field(lua_State *L, int table_index, const char *key, int *out) {
    return easylvgl_component_read_integer(L, table_index, key, out);
}

bool easylvgl_component_get_bool_field(lua_State *L, int table_index, const char *key, bool *out) {
    const int abs_index = lua_absindex(L, table_index);
    lua_getfield(L, abs_index, key);
    bool ok = false;
    if (lua_isboolean(L, -1)) {
        if (out != NULL) *out = lua_toboolean(L, -1);
        ok = true;
    } else if (lua_isinteger(L, -1)) {
        if (out != NULL) *out = lua_tointeger(L, -1) != 0;
        ok = true;
    }
    lua_pop(L, 1);
    return ok;
}

bool easylvgl_component_get_pivot(lua_State *L, int table_index, lv_point_t *out) {
    return easylvgl_component_read_point(L, table_index, "pivot", out);
}

const char *easylvgl_component_get_string_field(lua_State *L, int table_index, const char *key) {
    const int abs_index = lua_absindex(L, table_index);
    lua_getfield(L, abs_index, key);
    const char *result = NULL;
    if (lua_isstring(L, -1)) {
        result = lua_tostring(L, -1);
    }
    lua_pop(L, 1);
    return result;
}

lv_obj_t *easylvgl_component_get_parent_from_table(lua_State *L, int table_index) {
    const int abs_index = lua_absindex(L, table_index);
    lv_obj_t *parent = NULL;
    lua_getfield(L, abs_index, "parent");
    parent = easylvgl_component_get_lv_obj_from_value(L, -1);
    lua_pop(L, 1);
    return parent;
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

    ud = (easylvgl_component_ud_t *)luaL_testudata(L, index, EASYLVGL_IMAGE_MT);
    if (ud != NULL && ud->obj != NULL) {
        return ud->obj;
    }

    ud = (easylvgl_component_ud_t *)luaL_testudata(L, index, EASYLVGL_WIN_MT);
    if (ud != NULL && ud->obj != NULL) {
        return ud->obj;
    }

    if (lua_islightuserdata(L, index)) {
        return (lv_obj_t *)lua_touserdata(L, index);
    }

    return NULL;
}

void easylvgl_component_apply_geometry(lua_State *L, int table_index, lv_obj_t *obj) {
    int value = 0;
    if (easylvgl_component_read_integer(L, table_index, "x", &value)) {
        lv_obj_set_x(obj, value);
    }
    if (easylvgl_component_read_integer(L, table_index, "y", &value)) {
        lv_obj_set_y(obj, value);
    }
    if (easylvgl_component_read_integer(L, table_index, "w", &value)) {
        lv_obj_set_width(obj, value);
    }
    if (easylvgl_component_read_integer(L, table_index, "h", &value)) {
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
    }
    lua_pop(L, 1);
    return ref;
}

static void easylvgl_component_click_event_cb(lv_event_t *e) {
    if (lv_event_get_code(e) != LV_EVENT_CLICKED) {
        return;
    }
    lv_obj_t *target = lv_event_get_target_obj(e);
    easylvgl_component_call_callback(target);
}

void easylvgl_component_attach_click_event(lv_obj_t *obj) {
    if (obj == NULL) {
        return;
    }
    easylvgl_component_meta_t *meta = easylvgl_component_ensure_meta(obj);
    if (meta == NULL) {
        return;
    }
    if (meta->flags & EASYLVGL_COMPONENT_FLAG_CLICK) {
        return;
    }
    lv_obj_add_event_cb(obj, easylvgl_component_click_event_cb, LV_EVENT_CLICKED, NULL);
    meta->flags |= EASYLVGL_COMPONENT_FLAG_CLICK;
}
