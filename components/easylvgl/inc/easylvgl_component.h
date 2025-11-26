#ifndef EASYLVGL_COMPONENT_H
#define EASYLVGL_COMPONENT_H

#include "lua.h"
#include "lauxlib.h"
#include "luat_base.h"
#include "luat_mem.h"
#include "easylvgl.h"
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int callback_ref;
    lv_obj_t *title;
    lv_obj_t *content;
    uint8_t flags;
} easylvgl_component_meta_t;

#define EASYLVGL_COMPONENT_FLAG_CLICK (1 << 0)
#define EASYLVGL_COMPONENT_FLAG_CLOSE (1 << 1)

typedef struct {
    lv_obj_t *obj;
} easylvgl_component_ud_t;

void easylvgl_set_lua_state(lua_State *L);
lua_State *easylvgl_get_lua_state(void);

easylvgl_component_meta_t *easylvgl_component_get_meta(lv_obj_t *obj);
easylvgl_component_meta_t *easylvgl_component_ensure_meta(lv_obj_t *obj);
void easylvgl_component_release_meta(lv_obj_t *obj);

void easylvgl_component_set_callback_ref(lv_obj_t *obj, int callback_ref);
void easylvgl_component_call_callback(lv_obj_t *obj);

void easylvgl_component_attach_click_event(lv_obj_t *obj);
void easylvgl_component_attach_win_close_event(lv_obj_t *win, lv_obj_t *target);

void easylvgl_component_set_title(lv_obj_t *obj, lv_obj_t *title);
lv_obj_t *easylvgl_component_get_title(lv_obj_t *obj);
void easylvgl_component_set_content(lv_obj_t *obj, lv_obj_t *content);
lv_obj_t *easylvgl_component_get_content(lv_obj_t *obj);

bool easylvgl_component_get_integer_field(lua_State *L, int table_index, const char *key, int *out);
bool easylvgl_component_get_bool_field(lua_State *L, int table_index, const char *key, bool *out);
bool easylvgl_component_get_pivot(lua_State *L, int table_index, lv_point_t *out);
const char *easylvgl_component_get_string_field(lua_State *L, int table_index, const char *key);
lv_obj_t *easylvgl_component_get_parent_from_table(lua_State *L, int table_index);
lv_obj_t *easylvgl_component_get_lv_obj_from_value(lua_State *L, int index);
void easylvgl_component_apply_geometry(lua_State *L, int table_index, lv_obj_t *obj);
int easylvgl_component_capture_callback(lua_State *L, int table_index, const char *key);

#endif /*EASYLVGL_COMPONENT_H*/

