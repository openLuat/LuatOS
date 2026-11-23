/** @file luat_plcui_slider.c Bounded native slider and pointer transaction handling. */
#include "luat_plcui_component.h"
#include "lvgl9/src/core/lv_obj_event_private.h"

int32_t luat_plcui_slider_snap(int32_t value, int32_t minimum, int32_t maximum, uint32_t step)
{
    if (value < minimum) value = minimum;
    if (value > maximum) value = maximum;
    return minimum + (int32_t)(((uint32_t)(value - minimum) + step / 2U) / step * step);
}

#if LV_USE_SLIDER
static const lv_style_prop_t knob_transition_props[] = {
    LV_STYLE_TRANSFORM_WIDTH, LV_STYLE_TRANSFORM_HEIGHT, 0,
};

static const lv_style_transition_dsc_t knob_transition = {
    .props = knob_transition_props,
    .path_xcb = lv_anim_path_ease_out,
    .time = 80,
};

void luat_plcui_slider_cancel(plcui_widget_t *widget, const char *reason)
{
    if (!widget || !widget->slider || !widget->slider->dragging) return;
    plcui_slider_t *slider = widget->slider;
    lv_indev_t *indev = slider->indev;
    slider->dragging = false;
    slider->resetting = true;
    /* Native INDEV_RESET does not clear lv_slider's own drag state. A guarded
       release resets it; restoring afterwards also discards its final sample. */
    if (widget->obj) {
        lv_obj_send_event(widget->obj, LV_EVENT_RELEASED, NULL);
        lv_slider_set_value(widget->obj, slider->start_value, LV_ANIM_OFF);
    }
    slider->value = slider->start_value;
    slider->indev = NULL;
    if (indev) {
        lv_indev_reset(indev, widget->obj);
        lv_indev_wait_release(indev);
    }
    slider->resetting = false;
    luat_plcui_slider_emit(widget, PLCUI_CANCEL, reason);
}

static void slider_event(lv_event_t *event)
{
    plcui_widget_t *widget = lv_event_get_user_data(event);
    plcui_slider_t *slider = widget->slider;
    if (widget->document->closed || !widget->obj || !slider || slider->resetting) return;
    if (lv_event_get_target(event) != widget->obj) return;
    lv_event_code_t code = lv_event_get_code(event);
    if (code == LV_EVENT_HIT_TEST) {
        /* Native ADV_HITTEST only accepts the knob. PLCUI also accepts the
           track, while preserving hierarchy visibility/disabled checks. */
        lv_hit_test_info_t *info = lv_event_get_hit_test_info(event);
        lv_area_t bounds;
        lv_obj_get_coords(widget->obj, &bounds);
        if (info) info->res = luat_plcui_component_interactive(widget)
            && info->point->x >= bounds.x1 && info->point->x <= bounds.x2
            && info->point->y >= bounds.y1 && info->point->y <= bounds.y2;
    } else if (code == LV_EVENT_PRESSED && luat_plcui_component_interactive(widget)) {
        slider->start_value = slider->value;
        slider->dragging = true;
        slider->indev = lv_indev_active();
    } else if (code == LV_EVENT_VALUE_CHANGED) {
        if (!slider->dragging || !luat_plcui_component_interactive(widget)) {
            /* Discard native samples outside an active drag. */
            lv_slider_set_value(widget->obj, slider->value, LV_ANIM_OFF);
            return;
        }
        /* Keep LVGL's pointer position for drawing. Only the preview sent
           to the application follows the step grid until release. */
        int32_t value = luat_plcui_slider_snap(lv_slider_get_value(widget->obj),
            slider->minimum, slider->maximum, slider->step);
        if (slider->value != value) {
            slider->value = value;
            luat_plcui_slider_emit(widget, PLCUI_CHANGE, NULL);
        }
    } else if (code == LV_EVENT_RELEASED && slider->dragging) {
        if (!luat_plcui_component_interactive(widget)) {
            luat_plcui_slider_cancel(widget, "input_reset");
            return;
        }
        slider->dragging = false;
        slider->indev = NULL;
        lv_slider_set_value(widget->obj, slider->value, LV_ANIM_OFF);
        luat_plcui_slider_emit(widget, PLCUI_SUBMIT, NULL);
    } else if (code == LV_EVENT_PRESS_LOST || code == LV_EVENT_INDEV_RESET) {
        luat_plcui_slider_cancel(widget, code == LV_EVENT_PRESS_LOST ? "press_lost" : "input_reset");
    }
}

lv_obj_t *luat_plcui_slider_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    lv_obj_t *object = lv_slider_create(parent);
    if (!object) return NULL;
    plcui_slider_t *slider = widget->slider;
    lv_obj_remove_style_all(object);
    luat_plcui_component_init(widget, object);
    lv_obj_set_style_base_dir(object, LV_BASE_DIR_LTR, LV_PART_MAIN);
    lv_obj_set_ext_click_area(object, 0);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICK_FOCUSABLE | LV_OBJ_FLAG_SCROLL_ON_FOCUS
        | LV_OBJ_FLAG_SCROLL_CHAIN_HOR | LV_OBJ_FLAG_SCROLL_CHAIN_VER);
    lv_obj_add_flag(object, LV_OBJ_FLAG_CLICKABLE);
    int32_t size = slider->vertical ? widget->w : widget->h;
    bool has_knob_image = slider->knob_source[0] != '\0';
    /* Inset the rail across the slider so the knob stands out while the
       value axis and XML hit area keep their original dimensions. */
    int32_t rail_inset = has_knob_image || size < 8 ? 0 : size / 5;
    int32_t rail_radius = has_knob_image ? size / 2 : LV_MIN(size / 4, 4);
    int32_t knob_inset = has_knob_image ? 0 : LV_MIN(size / 8, 2);
    lv_obj_set_style_bg_color(object, lv_color_hex(slider->track_color), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(object, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(object, rail_radius, LV_PART_MAIN);
    lv_obj_set_style_border_width(object, 0, LV_PART_MAIN);
    lv_obj_set_style_shadow_width(object, 0, LV_PART_MAIN);
    lv_obj_set_style_transform_width(object, slider->vertical ? -rail_inset : 0, LV_PART_MAIN);
    lv_obj_set_style_transform_height(object, slider->vertical ? 0 : -rail_inset, LV_PART_MAIN);
    lv_obj_set_style_pad_all(object, 0, LV_PART_MAIN);
    if (slider->vertical) {
        lv_obj_set_style_pad_top(object, size / 2, LV_PART_MAIN);
        lv_obj_set_style_pad_bottom(object, (size - 1) / 2, LV_PART_MAIN);
    } else {
        lv_obj_set_style_pad_left(object, size / 2, LV_PART_MAIN);
        lv_obj_set_style_pad_right(object, (size - 1) / 2, LV_PART_MAIN);
    }
    lv_obj_set_style_bg_color(object, lv_color_hex(slider->indicator_color), LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(object, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_radius(object, rail_radius, LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(object, lv_color_hex(slider->knob_color), LV_PART_KNOB);
    lv_obj_set_style_bg_opa(object, has_knob_image ? LV_OPA_TRANSP : LV_OPA_COVER, LV_PART_KNOB);
    lv_obj_set_style_radius(object, has_knob_image ? 0 : LV_MIN(size / 6, 4), LV_PART_KNOB);
    lv_obj_set_style_pad_all(object, 0, LV_PART_KNOB);
    lv_obj_set_style_border_width(object, 0, LV_PART_KNOB);
    lv_obj_set_style_shadow_width(object, 0, LV_PART_KNOB);
    lv_obj_set_style_transform_width(object, -knob_inset, LV_PART_KNOB);
    lv_obj_set_style_transform_height(object, -knob_inset, LV_PART_KNOB);
    if (knob_inset > 0) {
        const lv_style_selector_t pressed = (lv_style_selector_t)LV_PART_KNOB | LV_STATE_PRESSED;
        lv_obj_set_style_transform_width(object, 0, pressed);
        lv_obj_set_style_transform_height(object, 0, pressed);
        lv_obj_set_style_transition(object, &knob_transition, LV_PART_KNOB);
    }
    lv_slider_set_mode(object, LV_SLIDER_MODE_NORMAL);
    lv_slider_set_orientation(object, slider->vertical ? LV_SLIDER_ORIENTATION_VERTICAL : LV_SLIDER_ORIENTATION_HORIZONTAL);
    lv_slider_set_range(object, slider->minimum, slider->maximum);
    lv_slider_set_value(object, slider->value, LV_ANIM_OFF);
    slider->start_value = slider->value;
    slider->dragging = false;
    slider->resetting = false;
    slider->indev = NULL;
    lv_obj_add_event_cb(object, slider_event, LV_EVENT_ALL, widget);
    return object;
}
#else
void luat_plcui_slider_cancel(plcui_widget_t *widget, const char *reason)
{
    (void)widget;
    (void)reason;
}

lv_obj_t *luat_plcui_slider_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    (void)widget;
    (void)parent;
    return NULL;
}
#endif
