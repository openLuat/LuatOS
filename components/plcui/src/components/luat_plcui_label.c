/** @file luat_plcui_label.c Dynamic text label creation and styles. */
#include "luat_plcui_component.h"

lv_obj_t *luat_plcui_label_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    lv_obj_t *object = lv_label_create(parent);
    if (!object) return NULL;
    lv_obj_remove_style_all(object);
    luat_plcui_component_init(widget, object);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICKABLE);
    lv_label_set_long_mode(object, LV_LABEL_LONG_CLIP);
    lv_obj_set_style_text_font(object, widget->font, 0);
    lv_obj_set_style_text_color(object, lv_color_hex(widget->color), 0);
    lv_obj_set_style_text_align(object, widget->align, 0);
    lv_label_set_text(object, widget->text);
    return object;
}
