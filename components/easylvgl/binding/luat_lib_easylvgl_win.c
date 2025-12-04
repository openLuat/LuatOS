/*
@module  easylvgl.win
@summary EasyLVGL Win 组件 Lua 绑定
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

#define LUAT_LOG_TAG "easylvgl.win"
#include "luat_log.h"

// 元表名称
#define EASYLVGL_WIN_MT "easylvgl.win"

/**
 * 创建 Win 组件
 * @api easylvgl.win(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 400
 * @int config.h 高度，默认 300
 * @string config.title 标题文本，可选
 * @bool config.close_btn 是否显示关闭按钮，默认 false
 * @bool config.auto_center 是否自动居中，默认 false
 * @table config.style 样式配置，可选
 * @int config.style.radius 圆角半径
 * @int config.style.pad 内边距
 * @int config.style.border_width 边框宽度
 * @function config.on_close 关闭回调函数，可选
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Win 对象
 */
static int l_easylvgl_win(lua_State *L) {
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
    
    lv_obj_t *win = easylvgl_win_create_from_config(L, 1);
    if (win == NULL) {
        lua_pushnil(L);
        return 1;
    }
    
    easylvgl_push_component_userdata(L, win, EASYLVGL_WIN_MT);
    return 1;
}

/**
 * Win:set_title(title)
 * @api win:set_title(title)
 * @string title 标题文本
 * @return nil
 */
static int l_win_set_title(lua_State *L) {
    lv_obj_t *win = easylvgl_check_component(L, 1, EASYLVGL_WIN_MT);
    const char *title = luaL_checkstring(L, 2);
    easylvgl_win_set_title(win, title);
    return 0;
}

/**
 * Win:add_content(child)
 * @api win:add_content(child)
 * @userdata child 子组件对象
 * @return nil
 */
static int l_win_add_content(lua_State *L) {
    lv_obj_t *win = easylvgl_check_component(L, 1, EASYLVGL_WIN_MT);
    
    // 从 userdata 中获取子对象
    easylvgl_component_ud_t *child_ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 2, NULL);
    if (child_ud == NULL || child_ud->obj == NULL) {
        luaL_error(L, "invalid child object");
        return 0;
    }
    
    easylvgl_win_add_content(win, child_ud->obj);
    return 0;
}

/**
 * Win GC（垃圾回收）
 */
static int l_win_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_WIN_MT);
    if (ud != NULL && ud->obj != NULL) {
        // 获取元数据并释放
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
        if (meta != NULL) {
            // 释放 Win 私有数据
            if (meta->user_data != NULL) {
                free(meta->user_data);
                meta->user_data = NULL;
            }
            
            easylvgl_component_meta_free(meta);
        }
        
        // 删除 LVGL 对象
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

/**
 * 注册 Win 元表
 * @param L Lua 状态
 */
void easylvgl_register_win_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_WIN_MT);
    
    // 设置元方法
    lua_pushcfunction(L, l_win_gc);
    lua_setfield(L, -2, "__gc");
    
    // 设置方法表
    static const luaL_Reg methods[] = {
        {"set_title", l_win_set_title},
        {"add_content", l_win_add_content},
        {NULL, NULL}
    };
    
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    
    lua_pop(L, 1);
}

/**
 * Win 创建函数（供主模块注册）
 */
int easylvgl_win_create(lua_State *L) {
    return l_easylvgl_win(L);
}

