/**
 * @file luat_easylvgl_label.c
 * @summary Label 组件实现
 * @responsible Label 组件创建、属性设置
 */

#include "luat_easylvgl_component.h"
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lua.h"
#include "lauxlib.h"
#include <string.h>
#include <stdint.h>

#define LUAT_LOG_TAG "easylvgl_label"
#include "luat_log.h"

/**
 * 从配置表创建 Label 组件
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL 对象指针，失败返回 NULL
 */
lv_obj_t *easylvgl_label_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }
    
    lua_State *L_state = (lua_State *)L;
    
    // 获取上下文（从注册表中获取）
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    
    if (ctx == NULL) {
        return NULL;
    }
    
    // 读取配置
    lv_obj_t *parent = easylvgl_marshal_parent(L, idx);
    int x = easylvgl_marshal_integer(L, idx, "x", 0);
    int y = easylvgl_marshal_integer(L, idx, "y", 0);
    int w = easylvgl_marshal_integer(L, idx, "w", 100);
    int h = easylvgl_marshal_integer(L, idx, "h", 40);
    const char *text = easylvgl_marshal_string(L, idx, "text", NULL);
    const char *symbol = easylvgl_marshal_string(L, idx, "symbol", NULL);
    
    // 创建 Label 对象
    lv_obj_t *label = lv_label_create(parent);
    if (label == NULL) {
        return NULL;
    }
    
    // 设置位置和大小
    lv_obj_set_pos(label, x, y);
    lv_obj_set_size(label, w, h);
    
    // 设置文本
    const char *display_text = NULL;
    if (symbol != NULL && strlen(symbol) > 0) {
        display_text = symbol;
        LLOGI("symbol found");
    } else if (text != NULL && strlen(text) > 0) {
        display_text = text;
        LLOGI("text found");
    }

    if (display_text != NULL) {
        lv_label_set_text(label, display_text);
    }
    
    // 分配元数据
    easylvgl_component_meta_t *meta = easylvgl_component_meta_alloc(
        ctx, label, EASYLVGL_COMPONENT_LABEL);
    if (meta == NULL) {
        lv_obj_delete(label);
        return NULL;
    }

    int click_ref = easylvgl_component_capture_callback(L, idx, "on_click");
    if (click_ref != LUA_NOREF) {
        lv_obj_add_flag(label, LV_OBJ_FLAG_CLICKABLE);
        easylvgl_component_bind_event(meta, EASYLVGL_EVENT_CLICKED, click_ref);
    }
    
    return label;
}

/**
 * 设置 Label 文本
 * @param label Label 对象指针
 * @param text 文本内容
 * @return 0 成功，<0 失败
 */
int easylvgl_label_set_text(lv_obj_t *label, const char *text)
{
    if (label == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    lv_label_set_text(label, text != NULL ? text : "");
    return EASYLVGL_OK;
}

/**
 * 获取 Label 文本
 * @param label Label 对象指针
 * @return 文本内容指针，失败返回 NULL
 */
const char *easylvgl_label_get_text(lv_obj_t *label)
{
    if (label == NULL) {
        return NULL;
    }
    
    return lv_label_get_text(label);
}

