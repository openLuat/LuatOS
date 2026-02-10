/**
 * @file luat_airui_event.c
 * @summary 组件事件绑定与回调调用
 * @responsible 事件绑定、Lua 回调调用、GC 处理
 */

#include "luat_airui_component.h"
#include "lua.h"
#include "lauxlib.h"
#include "../../inc/luat_airui_binding.h"
#include "lvgl9/src/widgets/button/lv_button.h"
#include "lvgl9/src/widgets/dropdown/lv_dropdown.h"
#include "lvgl9/src/misc/lv_event.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.event"
#include "luat_log.h"

// 根据组件类型获取组件元类型, 用于实现组件的类型判断
static const char *airui_component_get_mt_name(uint8_t component_type)
{
    switch (component_type) {
        case AIRUI_COMPONENT_BUTTON:
            return AIRUI_BUTTON_MT;
        case AIRUI_COMPONENT_LABEL:
            return AIRUI_LABEL_MT;
        case AIRUI_COMPONENT_IMAGE:
            return AIRUI_IMAGE_MT;
        case AIRUI_COMPONENT_WIN:
            return AIRUI_WIN_MT;
        case AIRUI_COMPONENT_DROPDOWN:
            return AIRUI_DROPDOWN_MT;
        case AIRUI_COMPONENT_SWITCH:
            return AIRUI_SWITCH_MT;
        case AIRUI_COMPONENT_MSGBOX:
            return AIRUI_MSGBOX_MT;
        case AIRUI_COMPONENT_CONTAINER:
            return AIRUI_CONTAINER_MT;
        case AIRUI_COMPONENT_BAR:
            return AIRUI_BAR_MT;
        case AIRUI_COMPONENT_TABLE:
            return AIRUI_TABLE_MT;
        case AIRUI_COMPONENT_TABVIEW:
            return AIRUI_TABVIEW_MT;
        case AIRUI_COMPONENT_TEXTAREA:
            return AIRUI_TEXTAREA_MT;
        case AIRUI_COMPONENT_KEYBOARD:
            return AIRUI_KEYBOARD_MT;
        case AIRUI_COMPONENT_LOTTIE:
            return AIRUI_LOTTIE_MT;
        default:
            return NULL;
    }
}

/**
 * 捕获配置表中的回调函数
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @param key 回调函数键名（如 "on_click"）
 * @return Lua registry 引用，未找到返回 LUA_NOREF
 */
int airui_component_capture_callback(void *L, int idx, const char *key)
{
    if (L == NULL || key == NULL) {
        return LUA_NOREF;
    }
    
    lua_State *L_state = (lua_State *)L;
    lua_getfield(L_state, idx, key);
    
    if (lua_type(L_state, -1) == LUA_TFUNCTION) {
        // 将函数保存到 registry
        int ref = luaL_ref(L_state, LUA_REGISTRYINDEX);
        return ref;
    }
    
    lua_pop(L_state, 1);
    return LUA_NOREF;
}

/**
 * LVGL 事件回调（内部使用）
 */
static void lvgl_event_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target(e);
    airui_component_meta_t *meta = airui_component_meta_get(obj);
    
    if (meta == NULL || meta->ctx == NULL) {
        return;
    }
    
    lv_event_code_t code = lv_event_get_code(e);
    airui_event_type_t event_type = AIRUI_EVENT_MAX;
    
    // 映射 LVGL 事件到 AIRUI 事件类型
    switch (code) {
        case LV_EVENT_CLICKED:
            event_type = AIRUI_EVENT_CLICKED;
            break;
        case LV_EVENT_PRESSED:
            event_type = AIRUI_EVENT_PRESSED;
            break;
        case LV_EVENT_RELEASED:
            event_type = AIRUI_EVENT_RELEASED;
            break;
        case LV_EVENT_VALUE_CHANGED:
            event_type = AIRUI_EVENT_VALUE_CHANGED;
            break;
        case LV_EVENT_READY:
            event_type = AIRUI_EVENT_READY;
            break;
        default:
            return;
    }
    
    // 调用 Lua 回调
    airui_component_call_callback(meta, event_type, meta->ctx->L);
}

/**
 * 绑定组件事件
 * @param meta 组件元数据
 * @param event_type 事件类型
 * @param callback_ref Lua 回调引用
 * @return 0 成功，<0 失败
 */
int airui_component_bind_event(
    airui_component_meta_t *meta,
    airui_event_type_t event_type,
    int callback_ref)
{
    if (meta == NULL || meta->obj == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    if (callback_ref == LUA_NOREF || callback_ref < 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    // 保存回调引用
    if (event_type < AIRUI_EVENT_MAX) {
        // 如果已有回调，先释放
        if (meta->callback_refs[event_type] != LUA_NOREF) {
            lua_State *L = (lua_State *)meta->ctx->L;
            if (L != NULL) {
                luaL_unref(L, LUA_REGISTRYINDEX, meta->callback_refs[event_type]);
            }
        }
        meta->callback_refs[event_type] = callback_ref;
    }
    
    // 绑定 LVGL 事件
    // 注意：CLOSE 事件由 Win 组件自己处理，不通过通用事件系统
    if (event_type == AIRUI_EVENT_CLOSE) {
        // CLOSE 事件由组件自己处理，这里只保存回调引用
        return AIRUI_OK;
    }
    
    lv_event_code_t lv_event_code = LV_EVENT_CLICKED;
    switch (event_type) {
        case AIRUI_EVENT_CLICKED:
            lv_event_code = LV_EVENT_CLICKED;
            break;
        case AIRUI_EVENT_PRESSED:
            lv_event_code = LV_EVENT_PRESSED;
            break;
        case AIRUI_EVENT_RELEASED:
            lv_event_code = LV_EVENT_RELEASED;
            break;
        case AIRUI_EVENT_VALUE_CHANGED:
            lv_event_code = LV_EVENT_VALUE_CHANGED;
            break;
        case AIRUI_EVENT_READY:
            lv_event_code = LV_EVENT_READY;
            break;
        default:
            return AIRUI_ERR_INVALID_PARAM;
    }
    
    lv_obj_add_event_cb(meta->obj, lvgl_event_cb, lv_event_code, meta);
    
    return AIRUI_OK;
}

/**
 * 调用 Lua 回调函数
 * @param meta 组件元数据
 * @param event_type 事件类型
 * @param L Lua 状态
 */
void airui_component_call_callback(
    airui_component_meta_t *meta,
    airui_event_type_t event_type,
    void *L)
{
    if (meta == NULL || L == NULL) {
        return;
    }
    
    if (event_type >= AIRUI_EVENT_MAX) {
        return;
    }
    
    int callback_ref = meta->callback_refs[event_type];
    if (callback_ref == LUA_NOREF || callback_ref < 0) {
        return;
    }
    
    lua_State *L_state = (lua_State *)L;
    
    // 从 registry 获取回调函数
    lua_rawgeti(L_state, LUA_REGISTRYINDEX, callback_ref);
    
    // 判断回调函数是否存在， 实现可以self自引用回调
    if (lua_type(L_state, -1) == LUA_TFUNCTION) {
        // 获取组件元类型
        const char *mt_name = airui_component_get_mt_name(meta->component_type);
        if (mt_name != NULL) {
            // 如果组件元类型不为空，则将组件元类型推入栈
            airui_push_component_userdata(L_state, meta->obj, mt_name);
        } else {
            // 如果组件元类型为空，则将组件对象推入栈
            lua_pushlightuserdata(L_state, meta->obj);
        }
        int arg_count = 1;
        if (event_type == AIRUI_EVENT_VALUE_CHANGED &&
            meta->component_type == AIRUI_COMPONENT_DROPDOWN) {
            lua_pushinteger(L_state, lv_dropdown_get_selected(meta->obj));
            arg_count++;
        }
        
        // 调用回调函数
        if (lua_pcall(L_state, arg_count, 0, 0) != LUA_OK) {
            // 错误处理
            const char *err = lua_tostring(L_state, -1);
            LLOGE("callback error: %s", err);
            lua_pop(L_state, 1);
        }
    } else {
        lua_pop(L_state, 1);
    }
}

/**
 * 释放组件所有回调引用
 * @param meta 组件元数据
 * @param L Lua 状态
 */
void airui_component_release_callbacks(airui_component_meta_t *meta, void *L)
{
    if (meta == NULL || L == NULL) {
        return;
    }
    
    lua_State *L_state = (lua_State *)L;
    
    for (int i = 0; i < AIRUI_EVENT_MAX; i++) {
        if (meta->callback_refs[i] != LUA_NOREF) {
            luaL_unref(L_state, LUA_REGISTRYINDEX, meta->callback_refs[i]);
            meta->callback_refs[i] = LUA_NOREF;
        }
    }
}

/**
 * 调用 Msgbox Action 回调
 * @param meta 组件元数据
 * @param action_text 按钮文本
 */
void airui_component_call_action_callback(
    airui_component_meta_t *meta,
    const char *action_text)
{
    if (meta == NULL || meta->ctx == NULL || meta->ctx->L == NULL) {
        return;
    }

    int callback_ref = meta->callback_refs[AIRUI_EVENT_ACTION];
    if (callback_ref == LUA_NOREF || callback_ref < 0) {
        return;
    }

    lua_State *L_state = (lua_State *)meta->ctx->L;
    lua_rawgeti(L_state, LUA_REGISTRYINDEX, callback_ref);

    if (lua_type(L_state, -1) == LUA_TFUNCTION) {
        airui_push_component_userdata(L_state, meta->obj, AIRUI_MSGBOX_MT);
        lua_pushstring(L_state, action_text != NULL ? action_text : "");

        if (lua_pcall(L_state, 2, 0, 0) != LUA_OK) {
            const char *err = lua_tostring(L_state, -1);
            lua_pop(L_state, 1);
        }
    } else {
        lua_pop(L_state, 1);
    }
}

