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
#include <stdint.h>
#include <stdbool.h>
#include "luat_hzfont.h"

#define LUAT_LOG_TAG "airui_label"
#include "luat_log.h"

static airui_label_data_t *airui_label_get_data(lv_obj_t *label);
static void airui_label_draw_prepare_cb(lv_event_t *e);
static void airui_label_draw_cleanup_cb(lv_event_t *e);
static airui_label_data_t *airui_label_alloc_data(uint16_t size);

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
    int font_size = airui_marshal_integer(L, idx, "font_size", 0);
    // 分配私有数据用于存储hzfont字号
    airui_label_data_t *data = airui_label_alloc_data(font_size);
    if (data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(label);
        return NULL;
    }
    meta->user_data = data;
    // 添加绘制准备回调，保证每个label的字号都使用自己的字号
    lv_obj_add_event_cb(label, airui_label_draw_prepare_cb, LV_EVENT_DRAW_MAIN_BEGIN, NULL);
    lv_obj_add_event_cb(label, airui_label_draw_cleanup_cb, LV_EVENT_DRAW_MAIN_END, NULL);
    // 设置label字号
    if (font_size > 0) {
        airui_label_set_font_size(label, font_size);
    } 

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
    if (label == NULL || font_size <= 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    // 获取私有数据
    airui_label_data_t *data = airui_label_get_data(label);
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

#ifdef LUAT_USE_HZFONT
    if (luat_hzfont_get_state() != LUAT_HZFONT_STATE_READY) {
        LLOGW("hzfont 未注册，无法设置字号");
        return AIRUI_ERR_NOT_SUPPORTED;
    }
    data->hzfont_size = (uint16_t)font_size;
    // 获取hzfont共享字体对象
    lv_font_t *shared_font = airui_font_get_shared_hzfont();
    if (shared_font != NULL) {
        lv_obj_set_style_text_font(label, shared_font, LV_PART_MAIN | LV_STATE_DEFAULT);
    }

    lv_obj_invalidate(label);
    return AIRUI_OK;
#else
    LLOGW("hzfont 未启用，无法设置字号");
    return AIRUI_ERR_NOT_SUPPORTED;
#endif
}

// 分配私有数据用于存储hzfont字号
static airui_label_data_t *airui_label_alloc_data(uint16_t size)
{
    airui_label_data_t *data = (airui_label_data_t *)luat_heap_malloc(sizeof(airui_label_data_t));
    if (data != NULL) {
        data->hzfont_size = size;
    }
    return data;
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

// 绘制准备回调
static void airui_label_draw_prepare_cb(lv_event_t *e)
{
    lv_obj_t *label = lv_event_get_target(e);
    airui_label_data_t *data = airui_label_get_data(label);
    if (data == NULL) {
        return;
    }
    // 设置字体共享对象渲染字号
    airui_font_hzfont_set_render_size(data->hzfont_size);
}

// 渲染完成后恢复共享字号，避免影响其他组件
static void airui_label_draw_cleanup_cb(lv_event_t *e)
{
    (void)e;
    airui_font_hzfont_set_render_size(0);
}
