/**
 * @file luat_easylvgl_button.c
 * @summary Button 组件实现
 * @responsible Button 组件创建、属性设置、事件绑定
 */

#include "luat_easylvgl_component.h"
#include "lvgl9/src/widgets/button/lv_button.h"
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lua.h"
#include "lauxlib.h"
#include <string.h>
#include <stdint.h>

/**
 * 从配置表创建 Button 组件
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL 对象指针，失败返回 NULL
 */
lv_obj_t *easylvgl_button_create_from_config(void *L, int idx)
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
    
    // 创建 Button 对象
    lv_obj_t *btn = lv_button_create(parent);
    if (btn == NULL) {
        return NULL;
    }
    
    // 设置位置和大小
    lv_obj_set_pos(btn, x, y);
    lv_obj_set_size(btn, w, h);
    
    // 设置文本
    if (text != NULL && strlen(text) > 0) {
        lv_obj_t *label = lv_label_create(btn);
        lv_label_set_text(label, text);
        lv_obj_center(label);
    }
    
    // 分配元数据
    easylvgl_component_meta_t *meta = easylvgl_component_meta_alloc(
        ctx, btn, EASYLVGL_COMPONENT_BUTTON);
    if (meta == NULL) {
        lv_obj_delete(btn);
        return NULL;
    }
    
    // 绑定点击事件
    int callback_ref = easylvgl_component_capture_callback(L, idx, "on_click");
    if (callback_ref != LUA_NOREF) {
        easylvgl_component_bind_event(meta, EASYLVGL_EVENT_CLICKED, callback_ref);
    }
    
    return btn;
}

/**
 * 设置 Button 文本
 * @param btn Button 对象指针
 * @param text 文本内容
 * @return 0 成功，<0 失败
 */
int easylvgl_button_set_text(lv_obj_t *btn, const char *text)
{
    if (btn == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    // 查找或创建 label
    // Button 的第一个子对象通常是 label
    lv_obj_t *label = NULL;
    uint32_t child_cnt = lv_obj_get_child_cnt(btn);
    
    if (child_cnt > 0) {
        label = lv_obj_get_child(btn, 0);
        // 检查是否是 label（简化处理，假设第一个子对象就是 label）
    }
    
    if (label == NULL) {
        // 创建新的 label
        label = lv_label_create(btn);
        lv_obj_center(label);
    }
    
    if (label != NULL) {
        lv_label_set_text(label, text != NULL ? text : "");
    }
    
    return EASYLVGL_OK;
}

/**
 * 设置 Button 点击回调
 * @param btn Button 对象指针
 * @param callback_ref Lua 回调引用
 * @return 0 成功，<0 失败
 */
int easylvgl_button_set_on_click(lv_obj_t *btn, int callback_ref)
{
    if (btn == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(btn);
    if (meta == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    return easylvgl_component_bind_event(meta, EASYLVGL_EVENT_CLICKED, callback_ref);
}

