/*
@module  easylvgl.dropdown
@summary EasyLVGL Dropdown 组件
@version 0.2.0
@date    2025.12.12
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"
#include "lvgl9/src/widgets/dropdown/lv_dropdown.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "easylvgl.dropdown"
#include "luat_log.h"

#define EASYLVGL_DROPDOWN_MT "easylvgl.dropdown"

/**
 * 创建 Dropdown 组件
 * @api easylvgl.dropdown(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 140
 * @int config.h 高度，默认 40
 * @table config.options 选项列表（字符串数组）
 * @int config.default_index 默认选中项索引，默认 -1
 * @function config.on_change 选中项变化回调
 * @userdata config.parent 父对象，可覆盖默认屏幕
 * @return userdata Dropdown 对象，失败返回 nil
 */
static int l_easylvgl_dropdown(lua_State *L)
{
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);

    if (ctx == NULL) {
        luaL_error(L, "easylvgl not initialized, call easylvgl.init() first");
        return 0;
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lv_obj_t *dropdown = easylvgl_dropdown_create_from_config(L, 1);
    if (dropdown == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, dropdown, EASYLVGL_DROPDOWN_MT);
    return 1;
}

/**
 * Dropdown:set_selected(index)
 * @api dropdown:set_selected(index)
 * @int index 选中项索引，0 起始
 * @return nil
 */
static int l_dropdown_set_selected(lua_State *L)
{
    lv_obj_t *dropdown = easylvgl_check_component(L, 1, EASYLVGL_DROPDOWN_MT);
    int index = luaL_checkinteger(L, 2);
    easylvgl_dropdown_set_selected(dropdown, index);
    return 0;
}

/**
 * Dropdown:get_selected()
 * @api dropdown:get_selected()
 * @return int 当前选中项索引
 */
static int l_dropdown_get_selected(lua_State *L)
{
    lv_obj_t *dropdown = easylvgl_check_component(L, 1, EASYLVGL_DROPDOWN_MT);
    int index = easylvgl_dropdown_get_selected(dropdown);
    lua_pushinteger(L, index);
    return 1;
}

/**
 * Dropdown:set_on_change(callback)
 * @api dropdown:set_on_change(callback)
 * @function callback 选中项改变回调
 * @return nil
 */
static int l_dropdown_set_on_change(lua_State *L)
{
    lv_obj_t *dropdown = easylvgl_check_component(L, 1, EASYLVGL_DROPDOWN_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    easylvgl_dropdown_set_on_change(dropdown, ref);
    return 0;
}

/**
 * Dropdown:destroy（手动销毁）
 */
static int l_dropdown_destroy(lua_State *L)
{
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_DROPDOWN_MT);
    if (ud != NULL && ud->obj != NULL) {
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
        if (meta != NULL) {
            if (meta->user_data != NULL) {
                luat_heap_free(meta->user_data);
                meta->user_data = NULL;
            }
            easylvgl_component_meta_free(meta);
        }
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

/**
 * 注册 Dropdown 元表
 * @param L Lua 状态
 */
void easylvgl_register_dropdown_meta(lua_State *L)
{
    luaL_newmetatable(L, EASYLVGL_DROPDOWN_MT);

    static const luaL_Reg methods[] = {
        {"set_selected", l_dropdown_set_selected},
        {"get_selected", l_dropdown_get_selected},
        {"set_on_change", l_dropdown_set_on_change},
        {"destroy", l_dropdown_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Dropdown 创建函数（供主模块注册）
 */
int easylvgl_dropdown_create(lua_State *L)
{
    return l_easylvgl_dropdown(L);
}

