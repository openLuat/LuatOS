/**
 * @file luat_airui_label.c
 * @summary Label 组件实现
 * @responsible Label 组件创建、属性设置
 */

#include "luat_airui.h"
#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lua.h"
#include "lauxlib.h"
#include <string.h>

#define LUAT_LOG_TAG "airui_label"
#include "luat_log.h"

static airui_label_data_t *airui_label_get_data(lv_obj_t *label);

/**
 * 从配置表创建 Label 组件
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL 对象指针，失败返回 NULL
 */
lv_obj_t *airui_label_create_from_config(void *L, int idx)
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
    int align = airui_marshal_integer(L, idx, "align", LV_TEXT_ALIGN_LEFT);
    const char *text = airui_marshal_string(L, idx, "text", NULL);
    const char *symbol = airui_marshal_string(L, idx, "symbol", NULL);
    
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
    } else if (text != NULL && strlen(text) > 0) {
        display_text = text;
    }

    if (display_text != NULL) {
        lv_label_set_text(label, display_text);
    }

    if (align == LV_TEXT_ALIGN_LEFT || align == LV_TEXT_ALIGN_CENTER || align == LV_TEXT_ALIGN_RIGHT) {
        airui_label_set_text_align(label, (lv_text_align_t)align);
    }
    
    // 分配元数据
    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, label, AIRUI_COMPONENT_LABEL);
    if (meta == NULL) {
        lv_obj_delete(label);
        return NULL;
    }

    
    // 设置文本颜色
    lv_color_t text_color;
    if (airui_marshal_color(L, idx, "color", &text_color)) {
        airui_label_set_text_color(label, text_color);
    }

    // 设置字号
    airui_label_data_t *data = (airui_label_data_t *)luat_heap_malloc(sizeof(airui_label_data_t));
    if (data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(label);
        return NULL;
    }
    airui_text_font_state_init(&data->font, 0);
    airui_text_font_read_config(&data->font, L, idx);
    airui_component_meta_set_user_data(meta, data, luat_heap_free);
    airui_text_font_attach(label, &data->font);
    airui_text_font_apply_to_obj(label, &data->font);

    int click_ref = airui_component_capture_callback(L, idx, "on_click");
    if (click_ref != LUA_NOREF) {
        lv_obj_add_flag(label, LV_OBJ_FLAG_CLICKABLE);
        airui_component_bind_event(meta, AIRUI_EVENT_CLICKED, click_ref);
    }
    
    return label;
}

/**
 * 设置 Label 文本
 * @param label Label 对象指针
 * @param text 文本内容
 * @return 0 成功，<0 失败
 */
int airui_label_set_text(lv_obj_t *label, const char *text)
{
    if (label == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_label_set_text(label, text != NULL ? text : "");
    return AIRUI_OK;
}

/**
 * 获取 Label 文本
 * @param label Label 对象指针
 * @return 文本内容指针，失败返回 NULL
 */
const char *airui_label_get_text(lv_obj_t *label)
{
    if (label == NULL) {
        return NULL;
    }
    return lv_label_get_text(label);
}

/**
 * 设置 Label 文本颜色
 */
int airui_label_set_text_color(lv_obj_t *label, lv_color_t color)
{
    if (label == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_set_style_text_color(label, color, LV_PART_MAIN | LV_STATE_DEFAULT);
    return AIRUI_OK;
}

/**
 * 设置 Label 字体大小
 */
int airui_label_set_font_size(lv_obj_t *label, int font_size)
{
    airui_label_data_t *data = airui_label_get_data(label);
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    if (font_size <= 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->font.prefer_hzfont = true;
    data->font.use_hzfont = true;
    data->font.hzfont_size = (uint16_t)font_size;
    if (airui_text_font_apply_hzfont(label, font_size,
        (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT)) != AIRUI_OK) {
        return AIRUI_ERR_NOT_SUPPORTED;
    }
    lv_obj_refresh_self_size(label);
    lv_obj_mark_layout_as_dirty(label);
    lv_obj_update_layout(label);
    lv_obj_invalidate(label);
    return AIRUI_OK;
}

// 设置标签对齐
int airui_label_set_text_align(lv_obj_t *label, lv_text_align_t align)
{
    if (label == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (align != LV_TEXT_ALIGN_LEFT && align != LV_TEXT_ALIGN_CENTER && align != LV_TEXT_ALIGN_RIGHT) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_set_style_text_align(label, align, LV_PART_MAIN | LV_STATE_DEFAULT);
    return AIRUI_OK;
}

// 获取私有数据
static airui_label_data_t *airui_label_get_data(lv_obj_t *label)
{
    airui_component_meta_t *meta = airui_component_meta_get(label);
    if (meta == NULL) {
        return NULL;
    }
    return (airui_label_data_t *)meta->user_data;
}
