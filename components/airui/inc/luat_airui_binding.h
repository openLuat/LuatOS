/**
 * @file luat_airui_binding.h
 * @summary Shared AIRUI Lua binding declarations.
 */

#ifndef LUAT_AIRUI_BINDING_H
#define LUAT_AIRUI_BINDING_H

#include <stdint.h>
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/core/lv_obj.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct airui_component_ref {
    lv_obj_t *obj;
    uint32_t id;
    uint8_t alive;
    uint32_t ref_count;
} airui_component_ref_t;

typedef struct {
    airui_component_ref_t *ref;
} airui_component_ud_t;

void airui_push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt);
lv_obj_t *airui_check_component(lua_State *L, int index, const char *mt);
lv_obj_t *airui_component_userdata_obj(airui_component_ud_t *ud);

void airui_component_invalidate_ref(airui_component_ref_t *ref);
void airui_component_ref_retain(airui_component_ref_t *ref);
void airui_component_ref_release(airui_component_ref_t *ref);

int airui_component_destroy_userdata(lua_State *L, int index, const char *mt);
int airui_component_is_destroyed(lua_State *L);
int airui_component_userdata_gc(lua_State *L);
void airui_component_set_metatable_gc(lua_State *L);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_AIRUI_BINDING_H */
