/**
 * @file luat_airui_win.c
 * @summary Win 组件实现
 * @responsible Win 组件创建、属性设置、事件绑定
 */

#include "luat_airui_component.h"
#include "lvgl9/src/widgets/win/lv_win.h"
#include "lvgl9/src/widgets/button/lv_button.h"
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_event.h"
#include "lvgl9/src/misc/lv_color.h"
#include "lua.h"
#include "lauxlib.h"
#include <string.h>
#include <stdint.h>
#include "luat_malloc.h"

/**
 * Win 组件私有数据结构
 */
typedef struct {
    lv_obj_t *title_label;  /**< 标题标签指针 */
    lv_obj_t *content;      /**< 内容容器指针 */
    lv_obj_t *close_btn;    /**< 关闭按钮指针 */
    airui_text_font_state_t header_font;
} airui_win_data_t;

static void airui_win_apply_header_font(airui_win_data_t *win_data)
{
    if (win_data == NULL || !win_data->header_font.prefer_hzfont || win_data->header_font.hzfont_size == 0) {
        return;
    }

    if (win_data->title_label != NULL) {
        airui_text_font_attach(win_data->title_label, &win_data->header_font);
        airui_text_font_apply_to_obj(win_data->title_label, &win_data->header_font);
    }
    if (win_data->close_btn != NULL) {
        (void)airui_text_font_apply_hzfont(win_data->close_btn, win_data->header_font.hzfont_size,
            (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT));
    }
}

/**
 * Win 关闭事件回调
 */
static void airui_win_close_event_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    lv_obj_t *win = NULL;
    
    if (code == LV_EVENT_CLICKED) {
        // 直接使用回调参数中的 win 对象，避免遍历导致误命中 header
        win = (lv_obj_t *)lv_event_get_user_data(e);

        // 兜底逻辑：从按钮开始向上查找 Window 组件
        if (win == NULL) {
            lv_obj_t *btn = lv_event_get_target(e);
            if (btn != NULL) {
                win = lv_obj_get_parent(btn);
                while (win != NULL) {
                    airui_component_meta_t *meta = airui_component_meta_get(win);
                    if (meta != NULL && meta->component_type == AIRUI_COMPONENT_WIN) {
                        break;
                    }
                    win = lv_obj_get_parent(win);
                }
            }
        }
    } else if (code == LV_EVENT_DELETE) {
        // 从窗口删除事件
        win = lv_event_get_target(e);
    }
    
    if (win != NULL) {
        airui_component_meta_t *meta = airui_component_meta_get(win);
        if (meta != NULL && meta->ctx != NULL) {
            // 调用 on_close 回调
            airui_component_call_callback(meta, AIRUI_EVENT_CLOSE, meta->ctx->L);
        }
        
        // 删除窗口（如果是从点击事件触发）
        if (code == LV_EVENT_CLICKED) {
            lv_obj_delete(win);
        }
    }
}

/**
 * 从配置表创建 Win 组件
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @return LVGL 对象指针，失败返回 NULL
 */
lv_obj_t *airui_win_create_from_config(void *L, int idx)
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
    int x = airui_marshal_floor_integer(L, idx, "x", 0);
    int y = airui_marshal_floor_integer(L, idx, "y", 0);
    int w = airui_marshal_floor_integer(L, idx, "w", 400);
    int h = airui_marshal_floor_integer(L, idx, "h", 300);
    const char *title = airui_marshal_string(L, idx, "title", NULL);
    bool close_btn = airui_marshal_bool(L, idx, "close_btn", false);
    bool auto_center = airui_marshal_bool(L, idx, "auto_center", false);
    
    // 创建 Win 对象
    lv_obj_t *win = lv_win_create(parent);
    if (win == NULL) {
        return NULL;
    }
    
    // 设置位置和大小
    lv_obj_set_pos(win, x, y);
    lv_obj_set_size(win, w, h);
    
    // 分配元数据
    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, win, AIRUI_COMPONENT_WIN);
    if (meta == NULL) {
        lv_obj_delete(win);
        return NULL;
    }
    
    // 分配 Win 私有数据
    airui_win_data_t *win_data = luat_heap_malloc(sizeof(airui_win_data_t));
    if (win_data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(win);
        return NULL;
    }
    win_data->title_label = NULL;
    win_data->content = NULL;
    win_data->close_btn = NULL;
    airui_text_font_state_init(&win_data->header_font, 0);
    meta->user_data = win_data;
    
    // 设置标题区域
    lv_obj_t *title_label = NULL;
    lv_obj_t *header = lv_win_get_header(win);
    bool has_title = (title != NULL && strlen(title) > 0);
    if (has_title) {
        title_label = lv_win_add_title(win, title);
        win_data->title_label = title_label;
    } else if (!close_btn) {
        lv_obj_add_flag(header, LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_height(header, 0);
        lv_obj_set_style_pad_all(header, 0, LV_PART_MAIN);
    }
    
    // 添加关闭按钮
    if (close_btn) {
        lv_obj_t *btn = lv_win_add_button(win, LV_SYMBOL_CLOSE, 40);
        win_data->close_btn = btn;
        lv_obj_add_event_cb(btn, airui_win_close_event_cb, LV_EVENT_CLICKED, win);
    }
    
    // 自动居中
    if (auto_center) {
        lv_obj_center(win);
    }
    
    // 应用样式
    lua_getfield(L_state, idx, "style");
    if (lua_type(L_state, -1) == LUA_TTABLE) {
        airui_win_set_style(win, L_state, lua_gettop(L_state));
    }
    lua_pop(L_state, 1);
    
    // 获取内容容器
    lv_obj_t *content = lv_win_get_content(win);
    win_data->content = content;
    airui_win_apply_header_font(win_data);
    
    // 绑定关闭事件
    int callback_ref = airui_component_capture_callback(L, idx, "on_close");
    if (callback_ref != -1) {  // LUA_NOREF
        airui_component_bind_event(meta, AIRUI_EVENT_CLOSE, callback_ref);
        
        // 如果没有关闭按钮，在窗口删除时触发回调
        if (!close_btn) {
            lv_obj_add_event_cb(win, airui_win_close_event_cb, LV_EVENT_DELETE, win);
        }
    }
    
    return win;
}

/**
 * 设置 Win 标题
 * @param win Win 对象指针
 * @param title 标题文本
 * @return 0 成功，<0 失败
 */
int airui_win_set_title(lv_obj_t *win, const char *title)
{
    if (win == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    airui_component_meta_t *meta = airui_component_meta_get(win);
    if (meta == NULL || meta->user_data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    airui_win_data_t *win_data = (airui_win_data_t *)meta->user_data;
    
    // 如果已有标题标签，更新文本
    if (win_data->title_label != NULL) {
        lv_label_set_text(win_data->title_label, title != NULL ? title : "");
    } else {
        // 创建新标题
        lv_obj_t *title_label = lv_win_add_title(win, title != NULL ? title : "");
        win_data->title_label = title_label;
        airui_win_apply_header_font(win_data);
    }
    
    return AIRUI_OK;
}

/**
 * 添加子组件到 Win 内容容器
 * @param win Win 对象指针
 * @param child 子对象指针
 * @return 0 成功，<0 失败
 */
int airui_win_add_content(lv_obj_t *win, lv_obj_t *child)
{
    if (win == NULL || child == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    airui_component_meta_t *meta = airui_component_meta_get(win);
    if (meta == NULL || meta->user_data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    airui_win_data_t *win_data = (airui_win_data_t *)meta->user_data;
    
    // 获取内容容器
    lv_obj_t *content = win_data->content;
    if (content == NULL) {
        content = lv_win_get_content(win);
        if (content == NULL) {
            return AIRUI_ERR_INVALID_PARAM;
        }
        win_data->content = content;
    }
    
    // 将子对象添加到内容容器
    lv_obj_set_parent(child, content);
    
    return AIRUI_OK;
}

// 按样式表设置窗口样式
int airui_win_set_style(lv_obj_t *win, void *L, int idx)
{
    if (win == NULL || L == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lua_State *L_state = (lua_State *)L;
    idx = lua_absindex(L_state, idx);
    if (!lua_istable(L_state, idx)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(win);
    if (meta == NULL || meta->user_data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_win_data_t *win_data = (airui_win_data_t *)meta->user_data;
    lv_obj_t *header = lv_win_get_header(win);
    lv_obj_t *content = win_data->content != NULL ? win_data->content : lv_win_get_content(win);
    lv_obj_t *title_label = win_data->title_label;
    lv_obj_t *close_btn = win_data->close_btn;
    int value = 0;

    if (airui_marshal_integer_opt(L_state, idx, "bg_color", &value)) {
        lv_obj_set_style_bg_color(win, lv_color_hex((uint32_t)value), LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "bg_opa", &value)) {
        lv_obj_set_style_bg_opa(win, airui_marshal_opacity(value), LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "border_color", &value)) {
        lv_obj_set_style_border_color(win, lv_color_hex((uint32_t)value), LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "border_width", &value)) {
        lv_obj_set_style_border_width(win, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "radius", &value)) {
        lv_obj_set_style_radius(win, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pad", &value)) {
        lv_obj_set_style_pad_all(win, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pad_top", &value)) {
        lv_obj_set_style_pad_top(win, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pad_bottom", &value)) {
        lv_obj_set_style_pad_bottom(win, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pad_left", &value)) {
        lv_obj_set_style_pad_left(win, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pad_right", &value)) {
        lv_obj_set_style_pad_right(win, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
    }

    if (header != NULL) {
        if (airui_marshal_integer_opt(L_state, idx, "header_bg_color", &value)) {
            lv_obj_set_style_bg_color(header, lv_color_hex((uint32_t)value), LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        if (airui_marshal_integer_opt(L_state, idx, "header_bg_opa", &value)) {
            lv_obj_set_style_bg_opa(header, airui_marshal_opacity(value), LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        if (airui_marshal_integer_opt(L_state, idx, "header_pad", &value)) {
            lv_obj_set_style_pad_all(header, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        if (airui_marshal_integer_opt(L_state, idx, "header_height", &value)) {
            lv_obj_set_height(header, value < 0 ? 0 : value);
        }
        if (airui_marshal_integer_opt(L_state, idx, "header_font_size", &value) && value > 0) {
            win_data->header_font.prefer_hzfont = true;
            win_data->header_font.hzfont_size = (uint16_t)value;
            airui_win_apply_header_font(win_data);
        }
    }

    if (content != NULL) {
        if (airui_marshal_integer_opt(L_state, idx, "content_bg_color", &value)) {
            lv_obj_set_style_bg_color(content, lv_color_hex((uint32_t)value), LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        if (airui_marshal_integer_opt(L_state, idx, "content_bg_opa", &value)) {
            lv_obj_set_style_bg_opa(content, airui_marshal_opacity(value), LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        if (airui_marshal_integer_opt(L_state, idx, "content_pad", &value)) {
            lv_obj_set_style_pad_all(content, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        win_data->content = content;
    }

    if (title_label != NULL) {
        if (airui_marshal_integer_opt(L_state, idx, "title_text_color", &value)) {
            lv_obj_set_style_text_color(title_label, lv_color_hex((uint32_t)value), LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        if (airui_marshal_integer_opt(L_state, idx, "title_align", &value)) {
            lv_text_align_t align = LV_TEXT_ALIGN_LEFT;
            if (value == (int)LV_TEXT_ALIGN_LEFT || value == (int)LV_TEXT_ALIGN_CENTER || value == (int)LV_TEXT_ALIGN_RIGHT) {
                align = (lv_text_align_t)value;
            }
            lv_obj_set_style_text_align(title_label, align, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
    }

    if (close_btn != NULL) {
        if (airui_marshal_integer_opt(L_state, idx, "close_btn_bg_color", &value)) {
            lv_obj_set_style_bg_color(close_btn, lv_color_hex((uint32_t)value), LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        if (airui_marshal_integer_opt(L_state, idx, "close_btn_bg_opa", &value)) {
            lv_obj_set_style_bg_opa(close_btn, airui_marshal_opacity(value), LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        if (airui_marshal_integer_opt(L_state, idx, "close_btn_radius", &value)) {
            lv_obj_set_style_radius(close_btn, value < 0 ? 0 : value, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        if (airui_marshal_integer_opt(L_state, idx, "close_btn_text_color", &value)) {
            lv_obj_set_style_text_color(close_btn, lv_color_hex((uint32_t)value), LV_PART_MAIN | LV_STATE_DEFAULT);
            uint32_t child_cnt = lv_obj_get_child_cnt(close_btn);
            uint32_t i = 0;
            for (i = 0; i < child_cnt; i++) {
                lv_obj_t *child = lv_obj_get_child(close_btn, i);
                lv_obj_set_style_text_color(child, lv_color_hex((uint32_t)value), LV_PART_MAIN | LV_STATE_DEFAULT);
            }
        }
    }

    return AIRUI_OK;
}


