/**
 * @file luat_easylvgl_event.c
 * @summary 组件事件绑定与回调调用
 * @responsible 事件绑定、Lua 回调调用、GC 处理
 */

#include "luat_easylvgl_component.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/widgets/button/lv_button.h"
#include "lvgl9/src/misc/lv_event.h"
#include <string.h>

/**
 * 捕获配置表中的回调函数
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @param key 回调函数键名（如 "on_click"）
 * @return Lua registry 引用，未找到返回 LUA_NOREF
 */
int easylvgl_component_capture_callback(void *L, int idx, const char *key)
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
    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(obj);
    
    if (meta == NULL || meta->ctx == NULL) {
        return;
    }
    
    lv_event_code_t code = lv_event_get_code(e);
    easylvgl_event_type_t event_type = EASYLVGL_EVENT_MAX;
    
    // 映射 LVGL 事件到 EasyLVGL 事件类型
    switch (code) {
        case LV_EVENT_CLICKED:
            event_type = EASYLVGL_EVENT_CLICKED;
            break;
        case LV_EVENT_PRESSED:
            event_type = EASYLVGL_EVENT_PRESSED;
            break;
        case LV_EVENT_RELEASED:
            event_type = EASYLVGL_EVENT_RELEASED;
            break;
        case LV_EVENT_VALUE_CHANGED:
            event_type = EASYLVGL_EVENT_VALUE_CHANGED;
            break;
        default:
            return;
    }
    
    // 调用 Lua 回调
    easylvgl_component_call_callback(meta, event_type, meta->ctx->L);
}

/**
 * 绑定组件事件
 * @param meta 组件元数据
 * @param event_type 事件类型
 * @param callback_ref Lua 回调引用
 * @return 0 成功，<0 失败
 */
int easylvgl_component_bind_event(
    easylvgl_component_meta_t *meta,
    easylvgl_event_type_t event_type,
    int callback_ref)
{
    if (meta == NULL || meta->obj == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    if (callback_ref == LUA_NOREF || callback_ref < 0) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    // 保存回调引用
    if (event_type < EASYLVGL_EVENT_MAX) {
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
    if (event_type == EASYLVGL_EVENT_CLOSE) {
        // CLOSE 事件由组件自己处理，这里只保存回调引用
        return EASYLVGL_OK;
    }
    
    lv_event_code_t lv_event_code = LV_EVENT_CLICKED;
    switch (event_type) {
        case EASYLVGL_EVENT_CLICKED:
            lv_event_code = LV_EVENT_CLICKED;
            break;
        case EASYLVGL_EVENT_PRESSED:
            lv_event_code = LV_EVENT_PRESSED;
            break;
        case EASYLVGL_EVENT_RELEASED:
            lv_event_code = LV_EVENT_RELEASED;
            break;
        case EASYLVGL_EVENT_VALUE_CHANGED:
            lv_event_code = LV_EVENT_VALUE_CHANGED;
            break;
        default:
            return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    lv_obj_add_event_cb(meta->obj, lvgl_event_cb, lv_event_code, meta);
    
    return EASYLVGL_OK;
}

/**
 * 调用 Lua 回调函数
 * @param meta 组件元数据
 * @param event_type 事件类型
 * @param L Lua 状态
 */
void easylvgl_component_call_callback(
    easylvgl_component_meta_t *meta,
    easylvgl_event_type_t event_type,
    void *L)
{
    if (meta == NULL || L == NULL) {
        return;
    }
    
    if (event_type >= EASYLVGL_EVENT_MAX) {
        return;
    }
    
    int callback_ref = meta->callback_refs[event_type];
    if (callback_ref == LUA_NOREF || callback_ref < 0) {
        return;
    }
    
    lua_State *L_state = (lua_State *)L;
    
    // 从 registry 获取回调函数
    lua_rawgeti(L_state, LUA_REGISTRYINDEX, callback_ref);
    
    if (lua_type(L_state, -1) == LUA_TFUNCTION) {
        // 推送组件 userdata（如果有）
        // TODO: 需要推送组件的 userdata，阶段一先简化
        lua_pushlightuserdata(L_state, meta->obj);
        
        // 调用回调函数
        if (lua_pcall(L_state, 1, 0, 0) != LUA_OK) {
            // 错误处理
            const char *err = lua_tostring(L_state, -1);
            // TODO: 记录错误日志
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
void easylvgl_component_release_callbacks(easylvgl_component_meta_t *meta, void *L)
{
    if (meta == NULL || L == NULL) {
        return;
    }
    
    lua_State *L_state = (lua_State *)L;
    
    for (int i = 0; i < EASYLVGL_EVENT_MAX; i++) {
        if (meta->callback_refs[i] != LUA_NOREF) {
            luaL_unref(L_state, LUA_REGISTRYINDEX, meta->callback_refs[i]);
            meta->callback_refs[i] = LUA_NOREF;
        }
    }
}

