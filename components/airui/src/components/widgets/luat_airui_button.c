/**
 * @file luat_airui_button.c
 * @summary Button 组件实现
 * @responsible Button 组件创建、属性设置、事件绑定
 */

#include "luat_airui_component.h"
#include "luat_malloc.h"
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

static void airui_button_apply_default_style(lv_obj_t *btn);
static void airui_button_warn_stype_deprecated(void);
static airui_button_data_t *airui_button_get_data(lv_obj_t *btn);
static lv_obj_t *airui_button_ensure_label(lv_obj_t *btn, airui_button_data_t *data);

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
    
    // 分配元数据
    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, btn, AIRUI_COMPONENT_BUTTON);
    if (meta == NULL) {
        lv_obj_delete(btn);
        return NULL;
    }

    airui_button_data_t *data = (airui_button_data_t *)luat_heap_malloc(sizeof(airui_button_data_t));
    if (data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(btn);
        return NULL;
    }
    memset(data, 0, sizeof(airui_button_data_t));
    airui_text_font_state_init(&data->font, 0);
    airui_text_font_read_config(&data->font, L, idx);
    airui_component_meta_set_user_data(meta, data, luat_heap_free);

    // 设置文本
    if (text != NULL && strlen(text) > 0) {
        lv_obj_t *label = airui_button_ensure_label(btn, data);
        if (label != NULL) {
            lv_label_set_text(label, text);
            lv_obj_center(label);
        }
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
    airui_button_data_t *data;

    if (btn == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data = airui_button_get_data(btn);
    lv_obj_t *label = airui_button_ensure_label(btn, data);
    if (label != NULL) {
        lv_label_set_text(label, text != NULL ? text : "");
        lv_obj_center(label);
    }

    return AIRUI_OK;
}

// 获取按钮文本
const char *airui_button_get_text(lv_obj_t *btn)
{
    airui_button_data_t *data;
    lv_obj_t *label = NULL;

    if (btn == NULL) {
        return NULL;
    }

    data = airui_button_get_data(btn);
    if (data != NULL && data->text_label != NULL) {
        label = data->text_label;
    }
    else if (lv_obj_get_child_cnt(btn) > 0) {
        label = lv_obj_get_child(btn, 0);
    }

    if (label == NULL) {
        return NULL;
    }

    return lv_label_get_text(label);
}

// 设置按钮失活状态
int airui_button_set_disabled(lv_obj_t *btn, bool disabled)
{
    if (btn == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (disabled) {
        lv_obj_add_state(btn, LV_STATE_DISABLED);
    }
    else {
        lv_obj_clear_state(btn, LV_STATE_DISABLED);
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

    if (airui_marshal_integer_opt(L_state, idx, "bg_color", &value)) {
        lv_obj_set_style_bg_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "bg_opa", &value)) {
        lv_obj_set_style_bg_opa(btn, airui_marshal_opacity(value),
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "border_color", &value)) {
        lv_obj_set_style_border_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "border_width", &value)) {
        lv_obj_set_style_border_width(btn, value < 0 ? 0 : value,
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "radius", &value)) {
        lv_obj_set_style_radius(btn, value < 0 ? 0 : value,
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pad", &value)) {
        lv_obj_set_style_pad_all(btn, value < 0 ? 0 : value,
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "text_color", &value)) {
        lv_obj_set_style_text_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pressed_bg_color", &value)) {
        lv_obj_set_style_bg_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_PRESSED);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pressed_bg_opa", &value)) {
        lv_obj_set_style_bg_opa(btn, airui_marshal_opacity(value),
            LV_PART_MAIN | LV_STATE_PRESSED);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pressed_text_color", &value)) {
        lv_obj_set_style_text_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_PRESSED);
    }
    if (airui_marshal_integer_opt(L_state, idx, "focus_outline_color", &value)) {
        lv_obj_set_style_outline_color(btn, lv_color_hex((uint32_t)value),
            LV_PART_MAIN | LV_STATE_FOCUS_KEY);
    }
    if (airui_marshal_integer_opt(L_state, idx, "focus_outline_width", &value)) {
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

// 应用默认样式
static void airui_button_apply_default_style(lv_obj_t *btn)
{
    lv_color_t border_color = lv_color_make(0x1e, 0x90, 0xff);
    lv_color_t focus_border_color = lv_color_make(0x00, 0x90, 0xff);
    lv_color_t normal_bg = lv_color_make(0xff, 0xff, 0xff);
    lv_color_t pressed_bg = lv_color_make(0xe5, 0xed, 0xff);
    lv_color_t text_color = lv_color_make(0x11, 0x2b, 0x63);
    lv_color_t disabled_border_color = lv_color_make(0xc4, 0xc9, 0xd4);
    lv_color_t disabled_bg = lv_color_make(0xee, 0xf1, 0xf5);
    lv_color_t disabled_text_color = lv_color_make(0x8a, 0x93, 0xa5);

    lv_obj_set_style_border_color(btn, border_color, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(btn, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(btn, 10, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(btn, normal_bg, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(btn, pressed_bg, LV_PART_MAIN | LV_STATE_PRESSED);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, LV_PART_MAIN | LV_STATE_PRESSED);
    lv_obj_set_style_text_color(btn, text_color, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(btn, disabled_border_color, LV_PART_MAIN | LV_STATE_DISABLED);
    lv_obj_set_style_bg_color(btn, disabled_bg, LV_PART_MAIN | LV_STATE_DISABLED);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, LV_PART_MAIN | LV_STATE_DISABLED);
    lv_obj_set_style_text_color(btn, disabled_text_color, LV_PART_MAIN | LV_STATE_DISABLED);
    lv_obj_set_style_outline_width(btn, 2, LV_PART_MAIN | LV_STATE_FOCUS_KEY);
    lv_obj_set_style_outline_color(btn, focus_border_color, LV_PART_MAIN | LV_STATE_FOCUS_KEY);
}

static void airui_button_warn_stype_deprecated(void)
{
    LLOGW("button stype 接口已废弃，请改用 style；该接口将在 1.2.0 版本后移除，当前版本 %s", AIRUI_VERSION);
}

static airui_button_data_t *airui_button_get_data(lv_obj_t *btn)
{
    airui_component_meta_t *meta = airui_component_meta_get(btn);
    if (meta == NULL) {
        return NULL;
    }
    return (airui_button_data_t *)meta->user_data;
}

static lv_obj_t *airui_button_ensure_label(lv_obj_t *btn, airui_button_data_t *data)
{
    lv_obj_t *label;

    if (btn == NULL) {
        return NULL;
    }

    if (data != NULL && data->text_label != NULL) {
        return data->text_label;
    }

    if (lv_obj_get_child_cnt(btn) > 0) {
        label = lv_obj_get_child(btn, 0);
    }
    else {
        label = lv_label_create(btn);
    }

    if (label != NULL && data != NULL) {
        data->text_label = label;
        airui_text_font_attach(label, &data->font);
        airui_text_font_apply_to_obj(label, &data->font);
    }

    return label;
}

