/**
 * @file luat_easylvgl_marshal.c
 * @summary 配置表字段读取工具
 * @responsible 从 Lua 配置表中读取各种类型的字段
 */

#include "luat_easylvgl_component.h"
#include "lua.h"
#include "lauxlib.h"

/**
 * 从配置表读取整数字段
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param default_value 默认值
 * @return 整数值
 */
int easylvgl_marshal_integer(void *L, int idx, const char *key, int default_value)
{
    if (L == NULL || key == NULL) {
        return default_value;
    }
    
    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, key);
    
    if (lua_type(L_state, -1) == LUA_TNUMBER) {
        int value = lua_tointeger(L_state, -1);
        lua_pop(L_state, 1);
        return value;
    }
    
    lua_pop(L_state, 1);
    return default_value;
}

/**
 * 从配置表读取布尔字段
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param default_value 默认值
 * @return 布尔值
 */
bool easylvgl_marshal_bool(void *L, int idx, const char *key, bool default_value)
{
    if (L == NULL || key == NULL) {
        return default_value;
    }
    
    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, key);
    
    if (lua_type(L_state, -1) == LUA_TBOOLEAN) {
        bool value = lua_toboolean(L_state, -1) != 0;
        lua_pop(L_state, 1);
        return value;
    }
    
    lua_pop(L_state, 1);
    return default_value;
}

/**
 * 从配置表读取字符串字段
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param default_value 默认值
 * @return 字符串指针（内部字符串，不需要释放），未找到返回 default_value
 */
const char *easylvgl_marshal_string(void *L, int idx, const char *key, const char *default_value)
{
    if (L == NULL || key == NULL) {
        return default_value;
    }
    
    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, key);
    
    if (lua_type(L_state, -1) == LUA_TSTRING) {
        const char *value = lua_tostring(L_state, -1);
        lua_pop(L_state, 1);
        return value;
    }
    
    lua_pop(L_state, 1);
    return default_value;
}

/**
 * 从配置表读取父对象
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return LVGL 父对象指针，未指定返回 NULL（返回屏幕对象）
 */
lv_obj_t *easylvgl_marshal_parent(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }
    
    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, "parent");
    
    if (lua_type(L_state, -1) == LUA_TUSERDATA) {
        // 从 userdata 中获取 LVGL 对象指针
        lv_obj_t *parent = (lv_obj_t *)lua_touserdata(L_state, -1);
        lua_pop(L_state, 1);
        return parent;
    }
    
    lua_pop(L_state, 1);
    // 未指定父对象，返回当前活动屏幕
    return lv_scr_act();
}

