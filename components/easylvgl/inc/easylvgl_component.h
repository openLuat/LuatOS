#ifndef EASYLVGL_COMPONENT_H
#define EASYLVGL_COMPONENT_H

#include "lua.h"
#include "easylvgl.h"
#include <stdbool.h>

typedef struct {
    lv_obj_t *obj;
} easylvgl_component_ud_t;

lv_obj_t *easylvgl_component_get_lv_obj_from_value(lua_State *L, int index);
lv_obj_t *easylvgl_component_get_parent_from_table(lua_State *L, int table_index);
const char *easylvgl_component_get_string_field(lua_State *L, int table_index, const char *key);
void easylvgl_component_apply_geometry(lua_State *L, int table_index, lv_obj_t *obj);
int easylvgl_component_capture_callback(lua_State *L, int table_index, const char *key);

#endif /*EASYLVGL_COMPONENT_H*/

