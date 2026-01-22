/**
 * @file luat_airui_marshal.c
 * @summary 配置表字段读取工具
 * @responsible 从 Lua 配置表中读取各种类型的字段
 */

#include "luat_airui_component.h"
#include "luat_airui_binding.h"
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
int airui_marshal_integer(void *L, int idx, const char *key, int default_value)
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
bool airui_marshal_bool(void *L, int idx, const char *key, bool default_value)
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
const char *airui_marshal_string(void *L, int idx, const char *key, const char *default_value)
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
 * 从配置表读取颜色字段（仅支持整数 Hex）
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param out 输出颜色
 * @return true 成功解析，false 未指定或类型错误
 */
bool airui_marshal_color(void *L, int idx, const char *key, lv_color_t *out)
{
    if (L == NULL || key == NULL || out == NULL) {
        return false;
    }

    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, key);

    bool ok = false;
    if (lua_type(L_state, -1) == LUA_TNUMBER) {
        uint32_t raw = (uint32_t)lua_tointeger(L_state, -1);
        *out = lv_color_hex(raw);
        ok = true;
    }

    lua_pop(L_state, 1);
    return ok;
}

/**
 * 从配置表读取父对象
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return LVGL 父对象指针，未指定返回当前活动屏幕
 */
lv_obj_t *airui_marshal_parent(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }
    
    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, "parent");
    
    if (lua_type(L_state, -1) == LUA_TUSERDATA) {
        // 从 userdata 结构体中获取 LVGL 对象指针
        // userdata 是 airui_component_ud_t 结构体，需要访问其 obj 字段
        airui_component_ud_t *ud = (airui_component_ud_t *)lua_touserdata(L_state, -1);
        lv_obj_t *parent = (ud != NULL) ? ud->obj : NULL;
        lua_pop(L_state, 1);
        
        // 如果 userdata 有效且包含有效的对象指针，返回该对象
        if (parent != NULL) {
            return parent;
        }
        // 如果 userdata 无效，回退到默认屏幕
        return lv_scr_act();
    }
    
    lua_pop(L_state, 1);
    // 未指定父对象，返回当前活动屏幕
    return lv_scr_act();
}

/**
 * 从配置表读取点坐标（用于 pivot 等）
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param out 输出点坐标，成功返回 true，失败返回 false
 * @return true 成功读取，false 未找到或格式错误
 */
bool airui_marshal_point(void *L, int idx, const char *key, lv_point_t *out)
{
    if (L == NULL || key == NULL || out == NULL) {
        return false;
    }
    
    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, key);
    
    if (lua_type(L_state, -1) == LUA_TTABLE) {
        // 读取 x 字段
        lua_getfield(L_state, -1, "x");
        if (lua_type(L_state, -1) == LUA_TNUMBER) {
            out->x = lua_tointeger(L_state, -1);
            lua_pop(L_state, 1);
            
            // 读取 y 字段
            lua_getfield(L_state, -1, "y");
            if (lua_type(L_state, -1) == LUA_TNUMBER) {
                out->y = lua_tointeger(L_state, -1);
                lua_pop(L_state, 2);  // 弹出 y 和 pivot 表
                return true;
            }
            lua_pop(L_state, 1);
        } else {
            lua_pop(L_state, 1);
        }
        lua_pop(L_state, 1);
    } else {
        lua_pop(L_state, 1);
    }
    
    return false;
}

/**
 * 获取表字段长度（仅支持数组）
 */
int airui_marshal_table_length(void *L, int idx, const char *key)
{
    if (L == NULL || key == NULL) {
        return 0;
    }

    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, key);

    if (!lua_istable(L_state, -1)) {
        lua_pop(L_state, 1);
        return 0;
    }

    int len = (int)lua_rawlen(L_state, -1);
    lua_pop(L_state, 1);
    return len;
}

/**
 * 获取表字段中指定位置的字符串
 */
const char *airui_marshal_table_string_at(void *L, int idx, const char *key, int position)
{
    if (L == NULL || key == NULL || position <= 0) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, key);

    if (!lua_istable(L_state, -1)) {
        lua_pop(L_state, 1);
        return NULL;
    }

    lua_rawgeti(L_state, -1, position);
    const char *value = NULL;
    if (lua_type(L_state, -1) == LUA_TSTRING) {
        value = lua_tostring(L_state, -1);
    }

    lua_pop(L_state, 2);
    return value;
}

