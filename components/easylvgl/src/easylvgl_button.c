/**
 * @file easylvgl_button.c
 * @summary EasyLVGL 按钮组件实现 (LVGL 9.4)
 * @version 0.0.2
 */

#include "easylvgl.h"
#include "luat_base.h"
#include "luat_mem.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../lvgl9/lvgl.h"
#include "../lvgl9/src/widgets/button/lv_button.h"
#include "../lvgl9/src/widgets/label/lv_label.h"
#include "../inc/easylvgl_component.h"

#define LUAT_LOG_TAG "easylvgl_button"
#include "luat_log.h"

static lua_State *g_L = NULL;

/**
 * 按钮点击事件回调（LVGL 9 格式）
 */
static void easylvgl_button_event_cb(lv_event_t *e) {
    lv_event_code_t code = lv_event_get_code(e);
    
    if (code == LV_EVENT_CLICKED) {
        lv_obj_t *btn = lv_event_get_target_obj(e);
        if (btn == NULL) {
            return;
        }
        
        // 获取用户数据（Lua 回调函数引用）
        int *callback_ref = (int *)lv_obj_get_user_data(btn);
        if (callback_ref == NULL || *callback_ref == LUA_NOREF) {
            return;
        }
        
        // 调用 Lua 回调函数
        if (g_L != NULL) {
            lua_rawgeti(g_L, LUA_REGISTRYINDEX, *callback_ref);
            if (lua_isfunction(g_L, -1)) {
                // 将按钮对象作为 userdata 推入栈
                lua_pushlightuserdata(g_L, btn);
                if (lua_pcall(g_L, 1, 0, 0) != LUA_OK) {
                    LLOGE("Error calling button callback: %s", lua_tostring(g_L, -1));
                    lua_pop(g_L, 1);
                }
            } else {
                lua_pop(g_L, 1);
            }
        }
    }
}

/**
 * 设置全局 Lua 状态（用于回调）
 */
void easylvgl_set_lua_state(lua_State *L) {
    g_L = L;
}

/**
 * 创建按钮对象
 */
lv_obj_t *easylvgl_button_create(lv_obj_t *parent) {
    if (parent == NULL) {
        // 如果没有父对象，使用默认屏幕
        parent = lv_screen_active();
        if (parent == NULL) {
            parent = lv_display_get_screen_active(lv_display_get_default());
        }
    }
    
    lv_obj_t *btn = lv_button_create(parent);
    if (btn == NULL) {
        LLOGE("Failed to create button");
        return NULL;
    }
    
    // 分配用户数据存储回调引用
    int *callback_ref = (int *)luat_heap_malloc(sizeof(int));
    if (callback_ref == NULL) {
        lv_obj_delete(btn);
        LLOGE("Failed to allocate callback ref");
        return NULL;
    }
    *callback_ref = LUA_NOREF;
    lv_obj_set_user_data(btn, callback_ref);
    
    // 添加点击事件回调
    lv_obj_add_event_cb(btn, easylvgl_button_event_cb, LV_EVENT_CLICKED, NULL);
    
    return btn;
}

/**
 * 设置按钮点击回调
 */
void easylvgl_button_set_callback(lv_obj_t *btn, int callback_ref) {
    if (btn == NULL) {
        return;
    }
    
    int *old_ref = (int *)lv_obj_get_user_data(btn);
    if (old_ref == NULL) {
        // 分配新的用户数据
        old_ref = (int *)luat_heap_malloc(sizeof(int));
        if (old_ref == NULL) {
            LLOGE("Failed to allocate callback ref");
            return;
        }
        lv_obj_set_user_data(btn, old_ref);
    }
    
    // 释放旧的引用
    if (g_L != NULL && *old_ref != LUA_NOREF) {
        luaL_unref(g_L, LUA_REGISTRYINDEX, *old_ref);
    }
    
    // 设置新的引用
    *old_ref = callback_ref;
}

void easylvgl_button_set_text(lv_obj_t *btn, const char *text) {
    if (btn == NULL || text == NULL) {
        return;
    }

    lv_obj_t *label = lv_obj_get_child(btn, 0);
    if (label == NULL) {
        label = lv_label_create(btn);
        lv_obj_center(label);
    }
    lv_label_set_text(label, text);
}

lv_obj_t *easylvgl_button_create_from_config(lua_State *L, int table_index) {
    lv_obj_t *parent = NULL;
    if (lua_istable(L, table_index)) {
        parent = easylvgl_component_get_parent_from_table(L, table_index);
    } else {
        parent = easylvgl_component_get_lv_obj_from_value(L, table_index);
    }

    lv_obj_t *btn = easylvgl_button_create(parent);
    if (btn == NULL) {
        return NULL;
    }

    if (lua_istable(L, table_index)) {
        const char *text = easylvgl_component_get_string_field(L, table_index, "text");
        if (text != NULL) {
            easylvgl_button_set_text(btn, text);
        }
        easylvgl_component_apply_geometry(L, table_index, btn);
        int callback_ref = easylvgl_component_capture_callback(L, table_index, "on_click");
        if (callback_ref != LUA_NOREF) {
            easylvgl_button_set_callback(btn, callback_ref);
        }
    }

    return btn;
}

