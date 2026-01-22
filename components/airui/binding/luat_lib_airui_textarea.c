/*
@module  airui.textarea
@summary AIRUI Textarea 组件 Lua 绑定
@version 0.3.0
@date    2025.12.15
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airui.textarea"
#include "luat_log.h"

#define AIRUI_TEXTAREA_MT "airui.textarea"
#define AIRUI_KEYBOARD_MT "airui.keyboard"

/************************************************************************
 * Lua 接口定义
 ************************************************************************/

/**
 * 创建 Textarea 组件
 * @api airui.textarea(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 ctx->width - x 或 200
 * @int config.h 高度，默认 120
 * @int config.max_len 最大字符数，默认 256
 * @string config.text 初始文本
 * @string config.placeholder 占位提示
 * @function config.on_text_change 文本变更回调
 * @table config.keyboard 内嵌 Keyboard 配置（table）
 * @userdata config.parent 父对象，可选
 * @return userdata Textarea 对象，失败返回 nil
 */
static int l_airui_textarea(lua_State *L) {
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
    lv_obj_t *textarea = airui_textarea_create_from_config(L, 1);
    if (textarea == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, textarea, AIRUI_TEXTAREA_MT);
    return 1;
}

/**
 * Textarea:set_text(text)
 * @api textarea:set_text(text)
 * @string text 文本内容
 * @return nil
 */
static int l_textarea_set_text(lua_State *L) {
    lv_obj_t *textarea = airui_check_component(L, 1, AIRUI_TEXTAREA_MT);
    const char *text = luaL_checkstring(L, 2);
    airui_textarea_set_text(textarea, text);
    return 0;
}

/**
 * Textarea:get_text()
 * @api textarea:get_text()
 * @return string 当前文本
 */
static int l_textarea_get_text(lua_State *L) {
    lv_obj_t *textarea = airui_check_component(L, 1, AIRUI_TEXTAREA_MT);
    const char *text = airui_textarea_get_text(textarea);
    lua_pushstring(L, text ? text : "");
    return 1;
}

/**
 * Textarea:set_cursor(pos)
 * @api textarea:set_cursor(pos)
 * @int pos 光标位置
 * @return nil
 */
static int l_textarea_set_cursor(lua_State *L) {
    lv_obj_t *textarea = airui_check_component(L, 1, AIRUI_TEXTAREA_MT);
    uint32_t pos = (uint32_t)luaL_checkinteger(L, 2);
    airui_textarea_set_cursor(textarea, pos);
    return 0;
}

/**
 * Textarea:set_on_text_change(callback)
 * @api textarea:set_on_text_change(callback)
 * @function callback 文本变化回调
 * @return nil
 */
static int l_textarea_set_on_change(lua_State *L) {
    lv_obj_t *textarea = airui_check_component(L, 1, AIRUI_TEXTAREA_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    airui_textarea_set_on_text_change(textarea, ref);
    return 0;
}

/**
 * Textarea:attach_keyboard(keyboard)
 * @api textarea:attach_keyboard(keyboard)
 * @userdata keyboard Keyboard 对象
 * @return nil
 */
static int l_textarea_attach_keyboard(lua_State *L) {
    lv_obj_t *textarea = airui_check_component(L, 1, AIRUI_TEXTAREA_MT);
    lv_obj_t *keyboard = airui_check_component(L, 2, AIRUI_KEYBOARD_MT);
    airui_textarea_attach_keyboard(textarea, keyboard);
    return 0;
}

/**
 * Textarea:get_keyboard()
 * @api textarea:get_keyboard()
 * @return userdata|null 当前绑定的 Keyboard
 */
static int l_textarea_get_keyboard(lua_State *L) {
    lv_obj_t *textarea = airui_check_component(L, 1, AIRUI_TEXTAREA_MT);
    lv_obj_t *keyboard = airui_textarea_get_keyboard(textarea);
    if (keyboard == NULL) {
        lua_pushnil(L);
        return 1;
    }
    airui_push_component_userdata(L, keyboard, AIRUI_KEYBOARD_MT);
    return 1;
}

/**
 * Textarea:destroy（手动销毁）
 */
static int l_textarea_destroy(lua_State *L) {
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_TEXTAREA_MT);
    if (ud != NULL && ud->obj != NULL) {
        airui_component_meta_t *meta = airui_component_meta_get(ud->obj);
        if (meta != NULL) {
            if (meta->user_data != NULL) {
                luat_heap_free(meta->user_data);
                meta->user_data = NULL;
            }
            airui_component_meta_free(meta);
        }
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

/**
 * 注册 Textarea 元表
 * @param L Lua 状态
 */
void airui_register_textarea_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_TEXTAREA_MT);

    static const luaL_Reg functions[] = {
        {"set_text", l_textarea_set_text},
        {"get_text", l_textarea_get_text},
        {"set_cursor", l_textarea_set_cursor},
        {"set_on_text_change", l_textarea_set_on_change},
        {"attach_keyboard", l_textarea_attach_keyboard},
        {"get_keyboard", l_textarea_get_keyboard},
        {"destroy", l_textarea_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, functions);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Textarea 创建函数（供主模块注册）
 */
int airui_textarea_create(lua_State *L) {
    return l_airui_textarea(L);
}

