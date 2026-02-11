/**
 * @file luat_airui_button.c
 * @summary Button 组件实现
 * @responsible Button 组件创建、属性设置、事件绑定
 */

#include "luat_airui_component.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/widgets/button/lv_button.h"
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/core/lv_group.h"
#include "lvgl9/src/misc/lv_color.h"
#include "lua.h"
#include "lauxlib.h"
#include <string.h>
#include <stdint.h>

#define LUAT_LOG_TAG "airui_button"
#include "luat_log.h"

/**
 * 从配置表创建 Button 组件
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL 对象指针，失败返回 NULL
 */
lv_obj_t *airui_button_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }
    
    lua_State *L_state = (lua_State *)L;
    
    // 获取上下文（从注册表中获取）
    airui_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    
    if (ctx == NULL) {
        return NULL;
    }
    
    // 读取配置
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);
    int w = airui_marshal_integer(L, idx, "w", 100);
    int h = airui_marshal_integer(L, idx, "h", 40);
    const char *text = airui_marshal_string(L, idx, "text", NULL);
    
    // 创建 Button 对象
    lv_obj_t *btn = lv_button_create(parent);
    if (btn == NULL) {
        return NULL;
    }
    
    // 设置位置和大小
    lv_obj_set_pos(btn, x, y);
    lv_obj_set_size(btn, w, h);

    // 默认风格：白底淡蓝边
    lv_color_t border_color = lv_color_make(0x1e, 0x90, 0xff); // 天蓝色边框 (Dodger Blue)
    lv_color_t normal_bg = lv_color_make(0xff, 0xff, 0xff); // 白色背景
    lv_color_t pressed_bg = lv_color_make(0xe5, 0xed, 0xff); // 按下时蓝色背景
    lv_color_t text_color = lv_color_make(0x11, 0x2b, 0x63); // 黑色文字
    lv_obj_set_style_border_color(btn, border_color, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(btn, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(btn, 10, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(btn, normal_bg, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(btn, pressed_bg, LV_PART_MAIN | LV_STATE_PRESSED);
    lv_obj_set_style_text_color(btn, text_color, LV_PART_MAIN | LV_STATE_DEFAULT);
    
    // 设置文本
    if (text != NULL && strlen(text) > 0) {
        lv_obj_t *label = lv_label_create(btn);
        lv_label_set_text(label, text);
        lv_obj_center(label);
    }
    
    // 分配元数据
    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, btn, AIRUI_COMPONENT_BUTTON);
    if (meta == NULL) {
        lv_obj_delete(btn);
        return NULL;
    }
    
    // 绑定点击事件
    int callback_ref = airui_component_capture_callback(L, idx, "on_click");
    if (callback_ref != LUA_NOREF) {
        airui_component_bind_event(meta, AIRUI_EVENT_CLICKED, callback_ref);
    }
    
    // 将按钮添加到默认按键组，以便支持按键导航
    lv_group_t *default_group = lv_group_get_default();
    if (default_group != NULL) {
        lv_group_add_obj(default_group, btn);
    }
    
    return btn;
}

/**
 * 设置 Button 文本
 * @param btn Button 对象指针
 * @param text 文本内容
 * @return 0 成功，<0 失败
 */
int airui_button_set_text(lv_obj_t *btn, const char *text)
{
    if (btn == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
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
    
    return AIRUI_OK;
}

/**
 * 设置 Button 点击回调
 * @param btn Button 对象指针
 * @param callback_ref Lua 回调引用
 * @return 0 成功，<0 失败
 */
int airui_button_set_on_click(lv_obj_t *btn, int callback_ref)
{
    if (btn == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    airui_component_meta_t *meta = airui_component_meta_get(btn);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    return airui_component_bind_event(meta, AIRUI_EVENT_CLICKED, callback_ref);
}

