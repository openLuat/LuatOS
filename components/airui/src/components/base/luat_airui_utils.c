/*
@summary AIRUI 公共辅助函数
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../../../inc/luat_airui_component.h"
#include "../../../inc/luat_airui_binding.h"

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

// 获取组件对象
lv_obj_t *airui_component_userdata_obj(airui_component_ud_t *ud) {
    if (ud == NULL || ud->ref == NULL || !ud->ref->alive || ud->ref->obj == NULL) {
        return NULL;
    }
    return ud->ref->obj;
}

// 无效化组件引用
void airui_component_invalidate_ref(airui_component_ref_t *ref) {
    if (ref == NULL) {
        return;
    }
    ref->alive = 0;
    ref->obj = NULL;
}

// 推送组件 userdata 到 Lua 栈
void airui_push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt) {
    airui_component_meta_t *meta = airui_component_meta_get(obj);
    if (meta == NULL || meta->ref == NULL) {
        luaL_error(L, "component %s is missing metadata", mt);
        return;
    }

    airui_component_ud_t *ud = (airui_component_ud_t *)lua_newuserdata(L, sizeof(airui_component_ud_t));
    ud->ref = meta->ref;
    luaL_getmetatable(L, mt);
    lua_setmetatable(L, -2);
}

// 检查并获取组件 userdata
lv_obj_t *airui_check_component(lua_State *L, int index, const char *mt) {
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, index, mt);
    lv_obj_t *obj = airui_component_userdata_obj(ud);
    if (obj == NULL || !lv_obj_is_valid(obj)) {
        if (ud != NULL && ud->ref != NULL) {
            airui_component_invalidate_ref(ud->ref);
        }
        luaL_where(L, 1);
        const char *where = lua_tostring(L, -1);
        LLOGE("%s ERROR: access destroyed airui component (%s, ref_id=%u)",
              where != NULL ? where : "",
              mt,
              (unsigned int)(ud != NULL && ud->ref != NULL ? ud->ref->id : 0));
        lua_pop(L, 1);
        luaL_error(L, "attempt to access destroyed %s object", mt);
    }
    return obj;
}

// 销毁组件 userdata
int airui_component_destroy_userdata(lua_State *L, int index, const char *mt) {
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, index, mt);
    lv_obj_t *obj = airui_component_userdata_obj(ud);

    if (obj == NULL) {
        return 0;
    }

    if (!lv_obj_is_valid(obj)) {
        airui_component_invalidate_ref(ud->ref);
        return 0;
    }

    lv_obj_delete(obj);
    return 0;
}

// 检查组件是否被销毁
int airui_component_is_destroyed(lua_State *L) {
    airui_component_ud_t *ud = (airui_component_ud_t *)lua_touserdata(L, 1);
    lv_obj_t *obj = airui_component_userdata_obj(ud);

    if (obj == NULL || !lv_obj_is_valid(obj)) {
        if (ud != NULL && ud->ref != NULL) {
            airui_component_invalidate_ref(ud->ref);
        }
        lua_pushboolean(L, 1);
        return 1;
    }

    lua_pushboolean(L, 0);
    return 1;
}
