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
 * @int config.tab_font_size 标签字体大小，使用 hzfont 时生效
 * @string config.switch_mode 切屏方式，可选 "swipe" 或 "jump"，默认 "swipe"
 * @table config.tabs 页面名称数组，至少一个，默认 Tab 1
 * @table config.page_style 可选的 Tab 页样式配置
 * @int config.page_style.tabbar_size 标签栏尺寸，设为 0 可隐藏 tab bar
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
    airui_push_component_userdata(L, page, AIRUI_CONTAINER_MT);
    return 1;
}

/**
 * TabView:get_tab_count()
 * @api tabview:get_tab_count()
 * @return int 当前标签页数量
 */
static int l_tabview_get_tab_count(lua_State *L) {
    lv_obj_t *tabview = airui_check_component(L, 1, AIRUI_TABVIEW_MT);
    lua_pushinteger(L, airui_tabview_get_tab_count(tabview));
    return 1;
}

/**
 * TabView:add_tab(title, content)
 * @api tabview:add_tab(title, content)
 * @string title 标签标题
 * @userdata content 可选，追加到新页中的子组件
 * @return userdata 页对象，失败返回 nil
 */
static int l_tabview_add_tab(lua_State *L) {
    lv_obj_t *tabview = airui_check_component(L, 1, AIRUI_TABVIEW_MT);
    const char *title = luaL_checkstring(L, 2);
    airui_component_ud_t *content_ud = NULL;

    if (!lua_isnoneornil(L, 3)) {
        if (lua_type(L, 3) != LUA_TUSERDATA) {
            luaL_error(L, "expected userdata as content object");
            return 0;
        }

        content_ud = (airui_component_ud_t *)lua_touserdata(L, 3);
        if (content_ud == NULL || airui_component_userdata_obj(content_ud) == NULL) {
            luaL_error(L, "invalid content object");
            return 0;
        }
    }

    lv_obj_t *page = airui_tabview_add_tab(tabview, title);
    if (page == NULL) {
        lua_pushnil(L);
        return 1;
    }

    if (content_ud != NULL) {
        lv_obj_set_parent(airui_component_userdata_obj(content_ud), page);
    }

    airui_push_component_userdata(L, page, AIRUI_CONTAINER_MT);
    return 1;
}

/**
 * TabView:remove_tab(index)
 * @api tabview:remove_tab(index)
 * @int index 页索引
 * @return nil
 */
static int l_tabview_remove_tab(lua_State *L) {
    lv_obj_t *tabview = airui_check_component(L, 1, AIRUI_TABVIEW_MT);
    int index = luaL_checkinteger(L, 2);
    if (index < 0) {
        luaL_error(L, "index must be >= 0");
        return 0;
    }

    if (airui_tabview_remove_tab(tabview, (uint32_t)index) != AIRUI_OK) {
        luaL_error(L, "remove_tab failed");
        return 0;
    }

    return 0;
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
    lv_obj_t *tabview = airui_check_component(L, 1, AIRUI_TABVIEW_MT);
    airui_component_meta_t *meta = airui_component_meta_get(tabview);
    if (meta != NULL) {
        airui_tabview_release_data(meta);
        meta->user_data = NULL;
    }
    return airui_component_destroy_userdata(L, 1, AIRUI_TABVIEW_MT);
}

void airui_register_tabview_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_TABVIEW_MT);

    static const luaL_Reg methods[] = {
        {"set_active", l_tabview_set_active},
        {"get_content", l_tabview_get_content},
        {"get_tab_count", l_tabview_get_tab_count},
        {"add_tab", l_tabview_add_tab},
        {"remove_tab", l_tabview_remove_tab},
        {"set_on_change", l_tabview_set_on_change},
        {"destroy", l_tabview_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_tabview_create(lua_State *L) {
    return l_airui_tabview(L);
}

