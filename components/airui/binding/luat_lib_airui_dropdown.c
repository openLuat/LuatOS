/*
@module  airui.dropdown
@summary AIRUI Dropdown 组件
@version 0.2.0
@date    2025.12.12
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"
#include "lvgl9/src/widgets/dropdown/lv_dropdown.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airui.dropdown"
#include "luat_log.h"

#define AIRUI_DROPDOWN_MT "airui.dropdown"

/**
 * 创建 Dropdown 组件
 * @api airui.dropdown(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 140
 * @int config.h 高度，默认 40
 * @string config.font 字体类型，传 "hzfont" 时启用 hzfont
 * @int config.font_size 字体大小，使用 hzfont 时生效
 * @table config.options 选项列表（字符串数组）
 * @int config.default_index 默认选中项索引，默认 -1
 * @function config.on_change 选中项变化回调，参数为 (self, idx, value)
 * @userdata config.parent 父对象，可覆盖默认屏幕
 * @return userdata Dropdown 对象，失败返回 nil
 */
static int l_airui_dropdown(lua_State *L)
{
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

    lv_obj_t *dropdown = airui_dropdown_create_from_config(L, 1);
    if (dropdown == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, dropdown, AIRUI_DROPDOWN_MT);
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
    lv_obj_t *dropdown = airui_check_component(L, 1, AIRUI_DROPDOWN_MT);
    int index = luaL_checkinteger(L, 2);
    airui_dropdown_set_selected(dropdown, index);
    return 0;
}

/**
 * Dropdown:get_selected()
 * @api dropdown:get_selected()
 * @return int 当前选中项索引
 */
static int l_dropdown_get_selected(lua_State *L)
{
    lv_obj_t *dropdown = airui_check_component(L, 1, AIRUI_DROPDOWN_MT);
    int index = airui_dropdown_get_selected(dropdown);
    lua_pushinteger(L, index);
    return 1;
}

/**
 * Dropdown:get_value()
 * @api dropdown:get_value()
 * @return string 当前选中项文本
 */
static int l_dropdown_get_value(lua_State *L)
{
    lv_obj_t *dropdown = airui_check_component(L, 1, AIRUI_DROPDOWN_MT);
    char value[256] = {0};
    lv_dropdown_get_selected_str(dropdown, value, sizeof(value));
    lua_pushstring(L, value);
    return 1;
}

/**
 * Dropdown:set_on_change(callback)
 * @api dropdown:set_on_change(callback)
 * @function callback 选中项改变回调，参数为 (self, idx, value)
 * @return nil
 */
static int l_dropdown_set_on_change(lua_State *L)
{
    lv_obj_t *dropdown = airui_check_component(L, 1, AIRUI_DROPDOWN_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    airui_dropdown_set_on_change(dropdown, ref);
    return 0;
}

/**
 * Dropdown:destroy（手动销毁）
 */
static int l_dropdown_destroy(lua_State *L)
{
    lv_obj_t *dropdown = airui_check_component(L, 1, AIRUI_DROPDOWN_MT);
    airui_component_meta_t *meta = airui_component_meta_get(dropdown);
    if (meta != NULL && meta->user_data != NULL) {
        luat_heap_free(meta->user_data);
        meta->user_data = NULL;
    }
    return airui_component_destroy_userdata(L, 1, AIRUI_DROPDOWN_MT);
}

/**
 * 注册 Dropdown 元表
 * @param L Lua 状态
 */
void airui_register_dropdown_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_DROPDOWN_MT);

    static const luaL_Reg methods[] = {
        {"set_selected", l_dropdown_set_selected},
        {"get_selected", l_dropdown_get_selected},
        {"get_value", l_dropdown_get_value},
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
int airui_dropdown_create(lua_State *L)
{
    return l_airui_dropdown(L);
}

