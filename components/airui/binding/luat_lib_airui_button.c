/*
@module  airui.button
@summary AIRUI Button 组件 Lua 绑定
@version 0.1.0
@date    2025.12.02
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"
#include "lvgl9/src/core/lv_group.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.button"
#include "luat_log.h"

// 元表名称
#define AIRUI_BUTTON_MT "airui.button"

/**
 * 创建 Button 组件
 * @api airui.button(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 100
 * @int config.h 高度，默认 40
 * @string config.text 文本内容，可选
 * @table config.style 样式表，可选
 * @int config.style.bg_color 默认态背景色（0xRRGGBB）
 * @int config.style.bg_opa 默认态背景透明度（0-255）
 * @int config.style.border_color 默认态边框颜色（0xRRGGBB）
 * @int config.style.border_width 默认态边框宽度
 * @int config.style.radius 圆角半径
 * @int config.style.pad 内边距
 * @int config.style.text_color 默认态文字颜色（0xRRGGBB）
 * @int config.style.pressed_bg_color 按下态背景色（0xRRGGBB）
 * @int config.style.pressed_bg_opa 按下态背景透明度（0-255）
 * @int config.style.pressed_text_color 按下态文字颜色（0xRRGGBB）
 * @int config.style.focus_outline_color 焦点态描边颜色（0xRRGGBB）
 * @int config.style.focus_outline_width 焦点态描边宽度
 * @table config.stype 兼容旧样式表，可选，已废弃并将在 1.2.0 版本后移除
 * @function config.on_click 点击回调函数，可选
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Button 对象
 */
static int l_airui_button(lua_State *L) {
    // 检查上下文是否已初始化（从注册表获取）
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
    
    lv_obj_t *btn = airui_button_create_from_config(L, 1);
    if (btn == NULL) {
        lua_pushnil(L);
        return 1;
    }
    
    airui_push_component_userdata(L, btn, AIRUI_BUTTON_MT);
    return 1;
}

/**
 * Button:set_text(text)
 * @api button:set_text(text)
 * @string text 文本内容
 * @return nil
 */
static int l_button_set_text(lua_State *L) {
    lv_obj_t *btn = airui_check_component(L, 1, AIRUI_BUTTON_MT);
    const char *text = luaL_checkstring(L, 2);
    airui_button_set_text(btn, text);
    return 0;
}

/**
 * Button:set_on_click(callback)
 * @api button:set_on_click(callback)
 * @function callback 回调函数
 * @return nil
 */
static int l_button_set_on_click(lua_State *L) {
    lv_obj_t *btn = airui_check_component(L, 1, AIRUI_BUTTON_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    
    // 保存回调函数到 registry
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    
    airui_button_set_on_click(btn, ref);
    return 0;
}

/**
 * Button:set_style(style)
 * @api button:set_style(style)
 * @table style 样式表，仅覆盖传入字段
 * @return nil
 */
static int l_button_set_style(lua_State *L) {
    lv_obj_t *btn = airui_check_component(L, 1, AIRUI_BUTTON_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    airui_button_set_style(btn, L, 2);
    return 0;
}

/**
 * Button:set_stype(stype)
 * @api button:set_stype(stype)
 * @table stype 兼容旧样式表，仅覆盖传入字段，已废弃并将在 1.2.0 版本后移除
 * @return nil
 */
static int l_button_set_stype(lua_State *L) {
    lv_obj_t *btn = airui_check_component(L, 1, AIRUI_BUTTON_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    LLOGW("button stype 接口已废弃，请改用 style；该接口将在 1.2.0 版本后移除，当前版本 %s", AIRUI_VERSION);
    airui_button_set_style(btn, L, 2);
    return 0;
}

/**
 * Button:focus() - 设置按钮获得焦点
 * @api button:focus()
 * @return nil
 */
static int l_button_focus(lua_State *L) {
    lv_obj_t *btn = airui_check_component(L, 1, AIRUI_BUTTON_MT);
    lv_group_t *default_group = lv_group_get_default();
    if (default_group != NULL) {
        lv_group_focus_obj(btn);
    }
    return 0;
}

/**
 * Button:destroy（手动销毁）
 */
static int l_button_destroy(lua_State *L) {
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_BUTTON_MT);
    if (ud != NULL && ud->obj != NULL) {
        // 获取元数据并释放
        airui_component_meta_t *meta = airui_component_meta_get(ud->obj);
        if (meta != NULL) {
            airui_component_meta_free(meta);
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
void airui_register_button_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_BUTTON_MT);
    // 设置方法表
    static const luaL_Reg methods[] = {
        {"set_text", l_button_set_text},
        {"set_style", l_button_set_style},
        {"set_stype", l_button_set_stype},
        {"set_on_click", l_button_set_on_click},
        {"focus", l_button_focus},
        {"destroy", l_button_destroy},
        {NULL, NULL}
    };
    
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    
    lua_pop(L, 1);
}

/**
 * Button 创建函数（供主模块注册）
 */
int airui_button_create(lua_State *L) {
    return l_airui_button(L);
}

