/**
 * @file easylvgl_label.c
 * @summary EasyLVGL 标签组件实现 (LVGL 9.4)
 * @version 0.0.2
 */

#include "easylvgl.h"
#include "luat_log.h"
#include "../lvgl9/lvgl.h"
#include "../lvgl9/src/widgets/label/lv_label.h"

#define LUAT_LOG_TAG "easylvgl_label"
#include "luat_log.h"

/**
 * 创建标签对象
 */
lv_obj_t *easylvgl_label_create(lv_obj_t *parent) {
    if (parent == NULL) {
        // 如果没有父对象，使用默认屏幕
        parent = lv_screen_active();
        if (parent == NULL) {
            parent = lv_display_get_screen_active(lv_display_get_default());
        }
    }
    
    lv_obj_t *label = lv_label_create(parent);
    if (label == NULL) {
        LLOGE("Failed to create label");
        return NULL;
    }
    
    return label;
}

/**
 * 设置标签文本
 */
void easylvgl_label_set_text(lv_obj_t *label, const char *text) {
    if (label == NULL) {
        return;
    }
    
    lv_label_set_text(label, text);
}

/**
 * 获取标签文本
 */
const char *easylvgl_label_get_text(lv_obj_t *label) {
    if (label == NULL) {
        return NULL;
    }
    
    return lv_label_get_text(label);
}

