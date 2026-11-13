/** @file luat_plcui_label.c Dynamic labels and native overflow scrolling. */
#include "luat_plcui_component.h"
#include "lvgl9/src/misc/lv_area_private.h"
#include <stdlib.h>

plcui_label_t *luat_plcui_label_config(plcui_widget_t *widget, plcui_error_t *error)
{
    if (widget->label) return widget->label;
    plcui_label_t *label = calloc(1, sizeof(*label));
    if (!label) {
        luat_plcui_error(error, "E_MEMORY", "Cannot allocate label scroll configuration");
        return NULL;
    }
    label->mode = LV_LABEL_LONG_MODE_CLIP;
    label->duration_ms = 4000;
    label->delay_ms = 500;
    label->ready = widget->obj && widget->document && widget->document->preparing_page < 0
        && widget->page_index == (unsigned)widget->document->current_page;
    widget->label = label;
    return label;
}

static bool label_visible(plcui_widget_t *widget)
{
    if (!widget->label->ready || !widget->document || widget->document->closed
        || widget->document->preparing_page >= 0
        || widget->page_index != (unsigned)widget->document->current_page
        || !luat_plcui_component_interactive(widget)) return false;
    lv_area_t visible;
    lv_obj_get_coords(widget->obj, &visible);
    lv_area_t screen = {0, 0, widget->document->width - 1, widget->document->height - 1};
    if (!lv_area_intersect(&visible, &visible, &screen)) return false;
    for (lv_obj_t *parent = lv_obj_get_parent(widget->obj); parent; parent = lv_obj_get_parent(parent)) {
        lv_area_t bounds;
        lv_obj_get_coords(parent, &bounds);
        if (!lv_area_intersect(&visible, &visible, &bounds)) return false;
    }
    return true;
}

/* Desired mode survives visibility changes; CLIP actually removes native
   offset animations, unlike merely setting the object's HIDDEN flag. */
void luat_plcui_label_sync(plcui_widget_t *widget)
{
    if (!widget || !widget->obj || widget->type != PLCUI_LABEL || !widget->label) return;
    plcui_label_t *label = widget->label;
    bool run = label->mode != LV_LABEL_LONG_MODE_CLIP && label_visible(widget);
    if (!run) {
        if (label->running || lv_label_get_long_mode(widget->obj) != LV_LABEL_LONG_MODE_CLIP)
            lv_label_set_long_mode(widget->obj, LV_LABEL_LONG_MODE_CLIP);
        label->running = false;
        return;
    }
    if (label->running) return;
    lv_anim_init(&label->animation);
    lv_anim_set_delay(&label->animation, label->delay_ms);
    lv_anim_set_repeat_delay(&label->animation, label->delay_ms);
    lv_anim_set_reverse_delay(&label->animation, label->delay_ms);
    lv_anim_set_repeat_count(&label->animation, LV_ANIM_REPEAT_INFINITE);
    lv_obj_set_style_anim(widget->obj, &label->animation, LV_PART_MAIN);
    lv_obj_set_style_anim_duration(widget->obj, label->duration_ms, LV_PART_MAIN);
    lv_label_set_long_mode(widget->obj, label->mode);
    label->running = true;
}

void luat_plcui_label_restart(plcui_widget_t *widget)
{
    if (!widget || !widget->obj || widget->type != PLCUI_LABEL || !widget->label) return;
    lv_label_set_long_mode(widget->obj, LV_LABEL_LONG_MODE_CLIP);
    widget->label->running = false;
    luat_plcui_label_sync(widget);
}

static void label_deleted(lv_event_t *event)
{
    plcui_widget_t *widget = lv_event_get_user_data(event);
    if (widget->label) {
        widget->label->running = false;
        widget->label->ready = false;
    }
}

lv_obj_t *luat_plcui_label_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    lv_obj_t *object = lv_label_create(parent);
    if (!object) return NULL;
    lv_obj_remove_style_all(object);
    luat_plcui_component_init(widget, object);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICKABLE);
    lv_label_set_long_mode(object, LV_LABEL_LONG_MODE_CLIP);
    lv_obj_set_style_text_font(object, widget->font, 0);
    lv_obj_set_style_text_color(object, lv_color_hex(widget->color), 0);
    lv_obj_set_style_text_align(object, widget->align, 0);
    lv_obj_set_style_base_dir(object, LV_BASE_DIR_LTR, 0);
    lv_label_set_text(object, widget->text);
    if (widget->label) {
        widget->label->running = false;
        widget->label->ready = false;
    }
    lv_obj_add_event_cb(object, label_deleted, LV_EVENT_DELETE, widget);
    return object;
}
