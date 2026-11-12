/** @file luat_plcui_container.c Nested component host and container appearance. */
#include "luat_plcui_component.h"

lv_obj_t *luat_plcui_container_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    lv_obj_t *object = lv_obj_create(parent);
    if (!object) return NULL;
    lv_obj_remove_style_all(object);
    luat_plcui_component_init(widget, object);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_CLICK_FOCUSABLE | LV_OBJ_FLAG_OVERFLOW_VISIBLE);
    lv_obj_set_style_bg_color(object, lv_color_hex(widget->background), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(object, widget->bg_opa, LV_PART_MAIN);
    lv_obj_set_style_border_color(object, lv_color_hex(widget->border_color), LV_PART_MAIN);
    lv_obj_set_style_border_width(object, widget->border_width, LV_PART_MAIN);
    lv_obj_set_style_radius(object, widget->radius, LV_PART_MAIN);
    lv_obj_set_style_pad_all(object, widget->padding, LV_PART_MAIN);
    return object;
}
