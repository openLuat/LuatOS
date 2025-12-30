/*
@module  easylvgl.button
@summary EasyLVGL Button 组件 Lua 绑定
@version 0.1.0
@date    2025.12.02
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"
#include <string.h>

#define LUAT_LOG_TAG "easylvgl.button"
#include "luat_log.h"

// 元表名称
#define EASYLVGL_BUTTON_MT "easylvgl.button"

/**
 * 创建 Button 组件
 * @api easylvgl.button(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 100
 * @int config.h 高度，默认 40
 * @string config.text 文本内容，可选
 * @function config.on_click 点击回调函数，可选
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Button 对象
 */
static int l_easylvgl_button(lua_State *L) {
    // 检查上下文是否已初始化（从注册表获取）
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
    
    lv_obj_t *btn = easylvgl_button_create_from_config(L, 1);
    if (btn == NULL) {
        lua_pushnil(L);
        return 1;
    }
    
    easylvgl_push_component_userdata(L, btn, EASYLVGL_BUTTON_MT);
    return 1;
}

/**
 * Button:set_text(text)
 * @api button:set_text(text)
 * @string text 文本内容
 * @return nil
 */
static int l_button_set_text(lua_State *L) {
    lv_obj_t *btn = easylvgl_check_component(L, 1, EASYLVGL_BUTTON_MT);
    const char *text = luaL_checkstring(L, 2);
    easylvgl_button_set_text(btn, text);
    return 0;
}

/**
 * Button:set_on_click(callback)
 * @api button:set_on_click(callback)
 * @function callback 回调函数
 * @return nil
 */
static int l_button_set_on_click(lua_State *L) {
    lv_obj_t *btn = easylvgl_check_component(L, 1, EASYLVGL_BUTTON_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    
    // 保存回调函数到 registry
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    
    easylvgl_button_set_on_click(btn, ref);
    return 0;
}

/**
 * Button GC（垃圾回收）
 */
static int l_button_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_BUTTON_MT);
    if (ud != NULL && ud->obj != NULL) {
        // 获取元数据并释放
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
        if (meta != NULL) {
            easylvgl_component_meta_free(meta);
        }
        
        // 删除 LVGL 对象
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

/**
 * 注册 Button 元表
 * @param L Lua 状态
 */
void easylvgl_register_button_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_BUTTON_MT);
    
    // 设置元方法
    lua_pushcfunction(L, l_button_gc);
    lua_setfield(L, -2, "__gc");
    
    // 设置方法表
    static const luaL_Reg methods[] = {
        {"set_text", l_button_set_text},
        {"set_on_click", l_button_set_on_click},
        {NULL, NULL}
    };
    
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    
    lua_pop(L, 1);
}

/**
 * Button 创建函数（供主模块注册）
 */
int easylvgl_button_create(lua_State *L) {
    return l_easylvgl_button(L);
}

