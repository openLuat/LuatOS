/**
 * @file easylvgl_button.c
 * @summary EasyLVGL 按钮组件实现 (LVGL 9.4)
 * @version 0.0.2
 */

#include "easylvgl.h"
#include "luat_base.h"
#include "luat_log.h"
#include "../lvgl9/lvgl.h"
#include "../lvgl9/src/widgets/button/lv_button.h"
#include "../lvgl9/src/widgets/label/lv_label.h"
#include "../inc/easylvgl_component.h"

#define LUAT_LOG_TAG "easylvgl_button"
#include "luat_log.h"

/**
 * 按钮点击事件回调（LVGL 9 格式）
 */
static void easylvgl_button_event_cb(lv_event_t *e) {
    if (lv_event_get_code(e) == LV_EVENT_CLICKED) {
        lv_obj_t *btn = lv_event_get_target_obj(e);
        easylvgl_component_call_callback(btn);
    }
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
    
    easylvgl_component_ensure_meta(btn);
    easylvgl_component_attach_click_event(btn);
    
    return btn;
}

/**
 * 设置按钮点击回调
 */
void easylvgl_button_set_callback(lv_obj_t *btn, int callback_ref) {
    if (btn == NULL) {
        return;
    }
    
    easylvgl_component_set_callback_ref(btn, callback_ref);
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

