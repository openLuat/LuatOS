/** @file luat_plcui_image.c Image creation, state resources and pointer events. */
#include "luat_plcui_component.h"
#include "lvgl9/src/core/lv_obj_event_private.h"

void luat_plcui_apply_image(plcui_widget_t *widget)
{
    if (!widget->obj || widget->type != PLCUI_IMAGE) return;
    bool disabled = widget->disabled || lv_obj_has_state(widget->obj, LV_STATE_DISABLED);
    unsigned state = disabled ? 3U : widget->pressed ? 1U : widget->checked ? 2U : 0U;
    const char *id = widget->source[state][0] ? widget->source[state] : widget->source[0];
    plcui_resource_t *resource = luat_plcui_resource(widget->document, id, PLCUI_RES_IMAGE);
    if (resource) lv_image_set_src(widget->obj, resource->path);
}

static void image_event(lv_event_t *event)
{
    plcui_widget_t *widget = lv_event_get_user_data(event);
    if (widget->document->closed || !widget->obj) return;
    lv_event_code_t code = lv_event_get_code(event);
    if (code == LV_EVENT_HIT_TEST && widget->has_hit_rect) {
        lv_hit_test_info_t *info = lv_event_get_hit_test_info(event);
        lv_area_t bounds;
        lv_obj_get_coords(widget->obj, &bounds);
        if (info && info->res) info->res = info->point->x >= bounds.x1 + widget->hit_x
            && info->point->x < bounds.x1 + widget->hit_x + widget->hit_w
            && info->point->y >= bounds.y1 + widget->hit_y
            && info->point->y < bounds.y1 + widget->hit_y + widget->hit_h;
    } else if (code == LV_EVENT_PRESSED && luat_plcui_component_interactive(widget)) {
        widget->pressed = true;
        luat_plcui_apply_image(widget);
    } else if (code == LV_EVENT_RELEASED || code == LV_EVENT_PRESS_LOST) {
        widget->pressed = false;
        luat_plcui_apply_image(widget);
    } else if (code == LV_EVENT_CLICKED && widget->clickable && luat_plcui_component_interactive(widget)) {
        luat_plcui_emit(widget, PLCUI_CLICK);
    }
}

lv_obj_t *luat_plcui_image_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    lv_obj_t *object = lv_image_create(parent);
    if (!object) return NULL;
    luat_plcui_component_init(widget, object);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_CLICK_FOCUSABLE);
    if (widget->clickable) lv_obj_add_flag(object, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(object, image_event, LV_EVENT_ALL, widget);
    widget->pressed = false;
    luat_plcui_apply_image(widget);
    lv_image_set_inner_align(object, LV_IMAGE_ALIGN_STRETCH);
    return object;
}
