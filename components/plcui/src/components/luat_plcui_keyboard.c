/** @file luat_plcui_keyboard.c Native keyboard layout, styling and session events. */
#include "luat_plcui_component.h"

static void keyboard_event(lv_event_t *event)
{
    plcui_widget_t *widget = lv_event_get_user_data(event);
    if (widget->document->closed || !widget->obj) return;
    lv_event_code_t code = lv_event_get_code(event);
    if (code == LV_EVENT_READY) luat_plcui_input_finish(widget->document, true, true);
    else if (code == LV_EVENT_CANCEL) luat_plcui_input_finish(widget->document, false, true);
}

lv_obj_t *luat_plcui_keyboard_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    lv_obj_t *object = lv_keyboard_create(parent);
    if (!object) return NULL;
    luat_plcui_component_init(widget, object);
    lv_keyboard_set_mode(object, widget->numeric_keyboard ? LV_KEYBOARD_MODE_NUMBER : LV_KEYBOARD_MODE_TEXT_LOWER);
    lv_keyboard_set_popovers(object, false);
    lv_obj_set_style_bg_color(object, lv_color_hex(0x111e28), LV_PART_MAIN);
    lv_obj_set_style_border_width(object, 1, LV_PART_MAIN);
    lv_obj_set_style_border_color(object, lv_color_hex(0x3c596b), LV_PART_MAIN);
    lv_obj_set_style_pad_all(object, 8, LV_PART_MAIN);
    lv_obj_set_style_bg_color(object, lv_color_hex(0x243746), LV_PART_ITEMS);
    lv_obj_set_style_bg_color(object, lv_color_hex(0x1caa8d), (lv_style_selector_t)LV_PART_ITEMS | (lv_style_selector_t)LV_STATE_PRESSED);
    lv_obj_set_style_text_color(object, lv_color_hex(0xedf7fb), LV_PART_ITEMS);
    lv_obj_set_style_text_font(object, widget->font, LV_PART_ITEMS);
    lv_obj_add_flag(object, LV_OBJ_FLAG_HIDDEN);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICK_FOCUSABLE);
    lv_obj_add_event_cb(object, keyboard_event, LV_EVENT_ALL, widget);
    return object;
}
