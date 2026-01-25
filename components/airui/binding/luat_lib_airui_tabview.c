/*
@module  airui.tabview
@summary AIRUI TabView 组件
@version 0.1.0
@date    2025.12.26
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define AIRUI_TABVIEW_MT "airui.tabview"

/**
 * 创建 TabView 组件
 * @api airui.tabview(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 320
 * @int config.h 高度，默认 200
 * @int config.tabbar_pos 标签栏位置，默认 LV_DIR_TOP
 * @int config.active 初始激活页索引，默认 0
 * @table config.tabs 页面名称数组，至少一个，默认 Tab 1
 * @table config.page_style 可选的 Tab 页样式配置
 * @userdata config.parent 父对象，默认当前屏幕
 * @return userdata TabView 对象
 */
static int l_airui_tabview(lua_State *L) {
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

    lv_obj_t *tabview = airui_tabview_create_from_config(L, 1);
    if (tabview == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, tabview, AIRUI_TABVIEW_MT);
    return 1;
}

/**
 * TabView:set_active(index)
 * @api tabview:set_active(index)
 * @int index 目标页索引
 * @return nil
 */
static int l_tabview_set_active(lua_State *L) {
    lv_obj_t *tabview = airui_check_component(L, 1, AIRUI_TABVIEW_MT);
    int index = luaL_checkinteger(L, 2);
    airui_tabview_set_active(tabview, index);
    return 0;
}

/**
 * TabView:get_content(index)
 * @api tabview:get_content(index)
 * @int index 页索引
 * @return userdata 页对象，失败返回 nil
 */
static int l_tabview_get_content(lua_State *L) {
    lv_obj_t *tabview = airui_check_component(L, 1, AIRUI_TABVIEW_MT);
    int index = luaL_checkinteger(L, 2);
    lv_obj_t *page = airui_tabview_get_content(tabview, index);
    if (page == NULL) {
        lua_pushnil(L);
        return 1;
    }
    airui_component_ud_t *ud = (airui_component_ud_t *)lua_newuserdata(L, sizeof(airui_component_ud_t));
    ud->obj = page;
    return 1;
}

/**
 * TabView:set_on_change(cb)
 * @api tabview:set_on_change(cb)
 * @function cb 回调（参数：tabview, index）
 * @return nil
 */
static int l_tabview_set_on_change(lua_State *L) {
    lv_obj_t *tabview = airui_check_component(L, 1, AIRUI_TABVIEW_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    airui_component_meta_t *meta = airui_component_meta_get(tabview);
    if (meta != NULL) {
        airui_component_bind_event(meta, AIRUI_EVENT_VALUE_CHANGED, ref);
    } else {
        luaL_unref(L, LUA_REGISTRYINDEX, ref);
    }
    return 0;
}

/**
 * TabView:destroy()
 * @api tabview:destroy()
 * @return nil
 */
static int l_tabview_destroy(lua_State *L) {
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_TABVIEW_MT);
    if (ud != NULL && ud->obj != NULL) {
        airui_component_meta_t *meta = airui_component_meta_get(ud->obj);
        if (meta != NULL) {
            airui_tabview_release_data(meta);
            airui_component_meta_free(meta);
        }
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

void airui_register_tabview_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_TABVIEW_MT);

    static const luaL_Reg methods[] = {
        {"set_active", l_tabview_set_active},
        {"get_content", l_tabview_get_content},
        {"set_on_change", l_tabview_set_on_change},
        {"destroy", l_tabview_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_tabview_create(lua_State *L) {
    return l_airui_tabview(L);
}

