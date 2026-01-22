/*
@module  easylvgl.keyboard
@summary EasyLVGL Keyboard 组件 Lua 绑定
@version 0.3.0
@date    2025.12.15
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "easylvgl.keyboard"
#include "luat_log.h"

#define EASYLVGL_KEYBOARD_MT "easylvgl.keyboard"
#define EASYLVGL_TEXTAREA_MT "easylvgl.textarea"

/**
 * 创建 Keyboard 组件
 * @api easylvgl.keyboard(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 ctx->height-160（或 0）
 * @int config.w 宽度，默认 ctx->width（或 480）
 * @int config.h 高度，默认 160
 * @string config.mode 键盘模式，如 "text"/"upper"/"special"/"numeric"
 * @boolean config.popovers 是否启用提示弹窗，默认 true
 * @boolean config.auto_hide 是否在目标 textarea 聚焦时自动显示、失焦时自动隐藏，默认 false
 * @userdata config.target 关联的 Textarea 对象，可选
 * @return userdata Keyboard 对象，失败返回 nil
 */
static int l_easylvgl_keyboard(lua_State *L) {
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
    lv_obj_t *keyboard = easylvgl_keyboard_create_from_config(L, 1);
    if (keyboard == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, keyboard, EASYLVGL_KEYBOARD_MT);
    return 1;
}

/**
 * Keyboard:set_target(textarea)
 * @api keyboard:set_target(textarea)
 * @userdata textarea 目标 Textarea 对象
 * @return nil
 */
static int l_keyboard_set_target(lua_State *L) {
    lv_obj_t *keyboard = easylvgl_check_component(L, 1, EASYLVGL_KEYBOARD_MT);
    lv_obj_t *textarea = easylvgl_check_component(L, 2, EASYLVGL_TEXTAREA_MT);
    easylvgl_keyboard_set_target(keyboard, textarea);
    return 0;
}

/**
 * Keyboard:show()
 * @api keyboard:show()
 * @return nil
 */
static int l_keyboard_show(lua_State *L) {
    lv_obj_t *keyboard = easylvgl_check_component(L, 1, EASYLVGL_KEYBOARD_MT);
    easylvgl_keyboard_show(keyboard);
    return 0;
}

/**
 * Keyboard:hide()
 * @api keyboard:hide()
 * @return nil
 */
static int l_keyboard_hide(lua_State *L) {
    lv_obj_t *keyboard = easylvgl_check_component(L, 1, EASYLVGL_KEYBOARD_MT);
    easylvgl_keyboard_hide(keyboard);
    return 0;
}

/**
 * Keyboard:set_on_commit(callback)
 * @api keyboard:set_on_commit(callback)
 * @function callback 提交事件回调
 * @return nil
 */
static int l_keyboard_set_on_commit(lua_State *L) {
    lv_obj_t *keyboard = easylvgl_check_component(L, 1, EASYLVGL_KEYBOARD_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    easylvgl_keyboard_set_on_commit(keyboard, ref);
    return 0;
}

/**
 * Keyboard:set_layout(layout)
 * @api keyboard:set_layout(layout)
 * @string layout 布局名称
 * @return nil
 */
static int l_keyboard_set_layout(lua_State *L) {
    lv_obj_t *keyboard = easylvgl_check_component(L, 1, EASYLVGL_KEYBOARD_MT);
    const char *layout = luaL_checkstring(L, 2);
    easylvgl_keyboard_set_layout(keyboard, layout);
    return 0;
}

/**
 * Keyboard:get_target()
 * @api keyboard:get_target()
 * @return userdata|null 当前关联 Textarea
 */
static int l_keyboard_get_target(lua_State *L) {
    lv_obj_t *keyboard = easylvgl_check_component(L, 1, EASYLVGL_KEYBOARD_MT);
    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(keyboard);
    if (meta == NULL || meta->user_data == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_keyboard_data_t *data = (easylvgl_keyboard_data_t *)meta->user_data;
    if (data == NULL || data->target == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, data->target, EASYLVGL_TEXTAREA_MT);
    return 1;
}

/**
 * Keyboard:destroy（手动销毁）
 */
static int l_keyboard_destroy(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_KEYBOARD_MT);
    if (ud != NULL && ud->obj != NULL) {
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
        if (meta != NULL) {
            if (meta->user_data != NULL) {
                easylvgl_keyboard_data_t *data = (easylvgl_keyboard_data_t *)meta->user_data;
                easylvgl_keyboard_detach_auto_hide_target(ud->obj, data);
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
 * 注册 Keyboard 元表
 * @param L Lua 状态
 */
void easylvgl_register_keyboard_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_KEYBOARD_MT);

    static const luaL_Reg methods[] = {
        {"set_target", l_keyboard_set_target},
        {"show", l_keyboard_show},
        {"hide", l_keyboard_hide},
        {"set_on_commit", l_keyboard_set_on_commit},
        {"set_layout", l_keyboard_set_layout},
        {"get_target", l_keyboard_get_target},
        {"destroy", l_keyboard_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Keyboard 创建函数（供主模块注册）
 */
int easylvgl_keyboard_create(lua_State *L) {
    return l_easylvgl_keyboard(L);
}

