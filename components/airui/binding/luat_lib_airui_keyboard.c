/*
@module  airui.keyboard
@summary AIRUI Keyboard 组件 Lua 绑定
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

#define LUAT_LOG_TAG "airui.keyboard"
#include "luat_log.h"

#define AIRUI_KEYBOARD_MT "airui.keyboard"
#define AIRUI_TEXTAREA_MT "airui.textarea"

/**
 * 创建 Keyboard 组件
 * @api airui.keyboard(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0，注意键盘默认打开ALIGN_BOTTOM_MID，位置从中下方开始计算
 * @int config.w 宽度，默认 ctx->width（或 480）
 * @int config.h 高度，默认 160
 * @string config.mode 键盘模式，如 "text"/"upper"/"special"/"numeric"/"pinyin_26"/"pinyin_9"/"pinyin_9_number"
 * @boolean config.popovers 是否启用提示弹窗，默认 true
 * @int config.font_size 键盘字体大小，使用 hzfont 时生效
 * @boolean config.auto_hide 是否在目标 textarea 聚焦时自动显示、失焦时自动隐藏，默认 false
 * @boolean config.preview 是否启用输入预览框（显示当前 textarea 文本），默认 false
 * @int config.preview_height 预览框固定高度（像素），默认 40
 * @int config.bg_color 键盘背景颜色，16 进制整数（如 0xffffff），可选，不提供则使用键盘默认主题色
 * @table config.style 按键样式表，可选，仅覆盖传入字段。作用在每个按键上，字段与 airui.button 的 style 一致
 * @int config.style.bg_color 按键默认态背景色（0xRRGGBB），同时作为渐变起点色
 * @int config.style.bg_opa 按键默认态背景透明度（0-255）
 * @int config.style.bg_grad_color 按键渐变终点色（0xRRGGBB）
 * @string config.style.bg_grad_dir 渐变方向："none" 纯色、"ver" 上到下、"hor" 左到右；也可传 0/1/2。只给 bg_grad_color 时默认 "ver"
 * @int config.style.border_color 按键默认态边框颜色（0xRRGGBB）
 * @int config.style.border_width 按键默认态边框宽度
 * @int config.style.radius 按键圆角半径
 * @int config.style.pad 按键内边距
 * @int config.style.text_color 按键默认态文字颜色（0xRRGGBB）
 * @int config.style.pressed_bg_color 按键按下态背景色（0xRRGGBB）
 * @int config.style.pressed_bg_opa 按键按下态背景透明度（0-255）
 * @int config.style.pressed_text_color 按键按下态文字颜色（0xRRGGBB）
 * @int config.style.focus_outline_color 按键焦点态描边颜色（0xRRGGBB）
 * @int config.style.focus_outline_width 按键焦点态描边宽度
 * @userdata config.target 关联的 Textarea 对象，可选
 *        当不在创建时指定 target 时，textarea 的焦点事件会自动将共享 keyboard 绑定至当前焦点控件，用户只需调用 `textarea:attach_keyboard(shared_keyboard)`。
 * @return userdata Keyboard 对象，失败返回 nil
 */
static int l_airui_keyboard(lua_State *L) {
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
    lv_obj_t *keyboard = airui_keyboard_create_from_config(L, 1);
    if (keyboard == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, keyboard, AIRUI_KEYBOARD_MT);
    return 1;
}

/**
 * Keyboard:set_target(textarea)
 * @api keyboard:set_target(textarea)
 * @userdata textarea 目标 Textarea 对象
 * @return nil
 */
static int l_keyboard_set_target(lua_State *L) {
    lv_obj_t *keyboard = airui_check_component(L, 1, AIRUI_KEYBOARD_MT);
    lv_obj_t *textarea = airui_check_component(L, 2, AIRUI_TEXTAREA_MT);
    airui_keyboard_set_target(keyboard, textarea);
    return 0;
}

/**
 * Keyboard:show()
 * @api keyboard:show()
 * @return nil
 */
static int l_keyboard_show(lua_State *L) {
    lv_obj_t *keyboard = airui_check_component(L, 1, AIRUI_KEYBOARD_MT);
    airui_keyboard_show(keyboard);
    return 0;
}

/**
 * Keyboard:hide()
 * @api keyboard:hide()
 * @return nil
 */
static int l_keyboard_hide(lua_State *L) {
    lv_obj_t *keyboard = airui_check_component(L, 1, AIRUI_KEYBOARD_MT);
    airui_keyboard_hide(keyboard);
    return 0;
}

/**
 * Keyboard:set_on_commit(callback)
 * @api keyboard:set_on_commit(callback)
 * @function callback 提交事件回调
 * @return nil
 */
static int l_keyboard_set_on_commit(lua_State *L) {
    lv_obj_t *keyboard = airui_check_component(L, 1, AIRUI_KEYBOARD_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    airui_keyboard_set_on_commit(keyboard, ref);
    return 0;
}

/**
 * Keyboard:set_layout(layout)
 * @api keyboard:set_layout(layout)
 * @string layout 布局名称
 * @return nil
 */
static int l_keyboard_set_layout(lua_State *L) {
    lv_obj_t *keyboard = airui_check_component(L, 1, AIRUI_KEYBOARD_MT);
    const char *layout = luaL_checkstring(L, 2);
    airui_keyboard_set_layout(keyboard, layout);
    return 0;
}

/**
 * Keyboard:set_bg_color(color)
 * @api keyboard:set_bg_color(color)
 * @int color 16 进制整数（如 0xff0000）
 * @return nil
 */
static int l_keyboard_set_bg_color(lua_State *L) {
    lv_obj_t *keyboard = airui_check_component(L, 1, AIRUI_KEYBOARD_MT);
    uint32_t raw = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t color = lv_color_hex(raw);
    airui_keyboard_set_bg_color(keyboard, color);
    return 0;
}

/**
 * Keyboard:set_style(style)
 * @api keyboard:set_style(style)
 * @table style 按键样式表，仅覆盖传入字段，字段与 airui.button 的 style 一致
 * @return nil
 */
static int l_keyboard_set_style(lua_State *L) {
    lv_obj_t *keyboard = airui_check_component(L, 1, AIRUI_KEYBOARD_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    airui_keyboard_set_style(keyboard, L, 2);
    return 0;
}

/**
 * Keyboard:get_target()
 * @api keyboard:get_target()
 * @return userdata|null 当前关联 Textarea
 */
static int l_keyboard_get_target(lua_State *L) {
    lv_obj_t *keyboard = airui_check_component(L, 1, AIRUI_KEYBOARD_MT);
    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    if (meta == NULL || meta->user_data == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_keyboard_data_t *data = (airui_keyboard_data_t *)meta->user_data;
    if (data == NULL || data->target == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, data->target, AIRUI_TEXTAREA_MT);
    return 1;
}

/**
 * Keyboard:destroy（手动销毁）
 */
static int l_keyboard_destroy(lua_State *L) {
    lv_obj_t *keyboard = airui_check_component(L, 1, AIRUI_KEYBOARD_MT);
    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    if (meta != NULL && meta->user_data != NULL) {
        airui_keyboard_data_t *data = (airui_keyboard_data_t *)meta->user_data;
        if (data->target != NULL && lv_obj_is_valid(data->target)) {
            airui_textarea_detach_keyboard(data->target, keyboard);
        }
    }

    return airui_component_destroy_userdata(L, 1, AIRUI_KEYBOARD_MT);
}

/**
 * 注册 Keyboard 元表
 * @param L Lua 状态
 */
void airui_register_keyboard_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_KEYBOARD_MT);
    airui_component_set_metatable_gc(L);

    static const luaL_Reg methods[] = {
        {"set_target", l_keyboard_set_target},
        {"show", l_keyboard_show},
        {"hide", l_keyboard_hide},
        {"set_on_commit", l_keyboard_set_on_commit},
        {"set_layout", l_keyboard_set_layout},
        {"set_bg_color", l_keyboard_set_bg_color},
        {"set_style", l_keyboard_set_style},
        {"get_target", l_keyboard_get_target},
        {"destroy", l_keyboard_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Keyboard 创建函数（供主模块注册）
 */
int airui_keyboard_create(lua_State *L) {
    return l_airui_keyboard(L);
}

