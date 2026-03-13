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

static lv_opa_t airui_button_normalize_opacity(int opacity);
static bool airui_button_get_table_integer(lua_State *L, int idx, const char *key, int *out);
static void airui_button_apply_default_style(lv_obj_t *btn);
static void airui_button_warn_stype_deprecated(void);

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

    airui_button_apply_default_style(btn);

    lua_getfield(L_state, idx, "style");
    if (lua_type(L_state, -1) == LUA_TTABLE) {
        airui_button_set_style(btn, L_state, lua_gettop(L_state));
    }
    lua_pop(L_state, 1);

    lua_getfield(L_state, idx, "stype");
    if (lua_type(L_state, -1) == LUA_TTABLE) {
        airui_button_warn_stype_deprecated();
        airui_button_set_style(btn, L_state, lua_gettop(L_state));
    }
    lua_pop(L_state, 1);
    
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

/**
 * 设置 Button 样式
 * 可设置的参数包括：
 *   - bg_color: 背景色，格式 0xRRGGBB
 *   - bg_opa: 背景透明度，范围 0~255
 *   - border_color: 边框颜色，格式 0xRRGGBB
 *   - border_width: 边框宽度，单位像素
 *   - radius: 圆角半径
 *   - pad: 内边距，影响文字与边框距离
 *   - text_color: 文字颜色
 * 
 *   - pressed_bg_color: 按下态背景色
 *   - pressed_bg_opa: 按下态背景透明度，范围 0~255
 *   - pressed_text_color: 按下态文字颜色
 * 
 *   - focus_outline_color: 焦点态描边颜色（键盘/编码器聚焦时可见）
 *   - focus_outline_width: 焦点态描边宽度
 * @param btn Button 对象指针
 * @param L Lua 状态
 * @param idx 样式表在栈中的索引
 * @return 0 成功，<0 失败
 */
int airui_button_set_style(lv_obj_t *btn, void *L, int idx)
{
    if (btn == NULL || L == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lua_State *L_state = (lua_State *)L;
    idx = lua_absindex(L_state, idx);
    if (!lua_istable(L_state, idx)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    int value = 0;

    if (airui_button_get_table_integer(L_state, idx, "bg_color", &value)) {
        lv_obj_set_style_bg_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_button_get_table_integer(L_state, idx, "bg_opa", &value)) {
        lv_obj_set_style_bg_opa(btn, airui_button_normalize_opacity(value),
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_button_get_table_integer(L_state, idx, "border_color", &value)) {
        lv_obj_set_style_border_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_button_get_table_integer(L_state, idx, "border_width", &value)) {
        lv_obj_set_style_border_width(btn, value < 0 ? 0 : value,
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_button_get_table_integer(L_state, idx, "radius", &value)) {
        lv_obj_set_style_radius(btn, value < 0 ? 0 : value,
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_button_get_table_integer(L_state, idx, "pad", &value)) {
        lv_obj_set_style_pad_all(btn, value < 0 ? 0 : value,
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_button_get_table_integer(L_state, idx, "text_color", &value)) {
        lv_obj_set_style_text_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_button_get_table_integer(L_state, idx, "pressed_bg_color", &value)) {
        lv_obj_set_style_bg_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_PRESSED);
    }
    if (airui_button_get_table_integer(L_state, idx, "pressed_bg_opa", &value)) {
        lv_obj_set_style_bg_opa(btn, airui_button_normalize_opacity(value),
            LV_PART_MAIN | LV_STATE_PRESSED);
    }
    if (airui_button_get_table_integer(L_state, idx, "pressed_text_color", &value)) {
        lv_obj_set_style_text_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_PRESSED);
    }
    if (airui_button_get_table_integer(L_state, idx, "focus_outline_color", &value)) {
        lv_obj_set_style_outline_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_FOCUS_KEY);
    }
    if (airui_button_get_table_integer(L_state, idx, "focus_outline_width", &value)) {
        lv_obj_set_style_outline_width(btn, value < 0 ? 0 : value,
            LV_PART_MAIN | LV_STATE_FOCUS_KEY);
    }

    return AIRUI_OK;
}

int airui_button_set_stype(lv_obj_t *btn, void *L, int idx)
{
    airui_button_warn_stype_deprecated();
    return airui_button_set_style(btn, L, idx);
}

// 归一化透明度
static lv_opa_t airui_button_normalize_opacity(int opacity)
{
    if (opacity < 0) {
        return LV_OPA_COVER;
    }
    if (opacity > LV_OPA_COVER) {
        return LV_OPA_COVER;
    }
    return (lv_opa_t)opacity;
}

// 从 Lua 表中获取整数
static bool airui_button_get_table_integer(lua_State *L, int idx, const char *key, int *out)
{
    if (L == NULL || key == NULL || out == NULL) {
        return false;
    }

    idx = lua_absindex(L, idx);
    lua_getfield(L, idx, key);
    if (lua_type(L, -1) != LUA_TNUMBER) {
        lua_pop(L, 1);
        return false;
    }

    *out = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);
    return true;
}

// 应用默认样式
static void airui_button_apply_default_style(lv_obj_t *btn)
{
    lv_color_t border_color = lv_color_make(0x1e, 0x90, 0xff);
    lv_color_t focus_border_color = lv_color_make(0x00, 0x90, 0xff);
    lv_color_t normal_bg = lv_color_make(0xff, 0xff, 0xff);
    lv_color_t pressed_bg = lv_color_make(0xe5, 0xed, 0xff);
    lv_color_t text_color = lv_color_make(0x11, 0x2b, 0x63);

    lv_obj_set_style_border_color(btn, border_color, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(btn, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(btn, 10, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(btn, normal_bg, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(btn, pressed_bg, LV_PART_MAIN | LV_STATE_PRESSED);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, LV_PART_MAIN | LV_STATE_PRESSED);
    lv_obj_set_style_text_color(btn, text_color, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_outline_width(btn, 2, LV_PART_MAIN | LV_STATE_FOCUS_KEY);
    lv_obj_set_style_outline_color(btn, focus_border_color, LV_PART_MAIN | LV_STATE_FOCUS_KEY);
}

static void airui_button_warn_stype_deprecated(void)
{
    LLOGW("button stype 接口已废弃，请改用 style；该接口将在 1.2.0 版本后移除，当前版本 %s", AIRUI_VERSION);
}

