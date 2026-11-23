/** @file luat_plcui_textarea.c Editable text, focus and submission events. */
#include "luat_plcui_component.h"
#include "luat_plcui_perf.h"
#include <stdio.h>
#include <string.h>

/* Call only with PLCUI-validated text or a previously accepted edit snapshot.
 * Native filters remain enabled for subsequent keyboard input. */
void luat_plcui_textarea_write(lv_obj_t *object, const char *text)
{
    uint32_t maximum = lv_textarea_get_max_length(object);
    const char *accepted = lv_textarea_get_accepted_chars(object);
    lv_textarea_set_max_length(object, 0);
    lv_textarea_set_accepted_chars(object, NULL);
    lv_textarea_set_text(object, text);
    lv_textarea_set_accepted_chars(object, accepted);
    lv_textarea_set_max_length(object, maximum);
}

static void textarea_event(lv_event_t *event)
{
    plcui_widget_t *widget = lv_event_get_user_data(event);
    plcui_document_t *document = widget->document;
    if (document->closed || !widget->obj) return;
    lv_event_code_t code = lv_event_get_code(event);
    if ((code == LV_EVENT_CLICKED || code == LV_EVENT_FOCUSED) && !document->silent) {
        luat_plcui_input_begin(widget);
    } else if (code == LV_EVENT_VALUE_CHANGED && !document->silent) {
        const char *text = lv_textarea_get_text(widget->obj);
        if (strlen(text) >= sizeof(widget->text)) {
            document->silent = true;
            luat_plcui_textarea_write(widget->obj, widget->text);
            document->silent = false;
        } else {
            snprintf(widget->text, sizeof(widget->text), "%s", text);
            luat_plcui_emit(widget, PLCUI_CHANGE);
        }
    } else if (code == LV_EVENT_READY && document->editing == widget) {
        luat_plcui_input_finish(document, true, true);
    } else if (code == LV_EVENT_CANCEL && document->editing == widget) {
        luat_plcui_input_finish(document, false, true);
    }
}

lv_obj_t *luat_plcui_textarea_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    uint32_t started = plcui_perf_now();
    lv_obj_t *object = lv_textarea_create(parent);
    plcui_perf_textarea(PERF_TA_NATIVE, plcui_perf_now() - started);
    if (!object) return NULL;
    started = plcui_perf_now();
    luat_plcui_component_init(widget, object);
    plcui_perf_textarea(PERF_TA_COMMON, plcui_perf_now() - started);
    started = plcui_perf_now();
    lv_obj_set_style_bg_opa(object, LV_OPA_TRANSP, LV_PART_MAIN);
    lv_obj_set_style_border_width(object, 0, LV_PART_MAIN);
    lv_obj_set_style_outline_width(object, 0, LV_PART_MAIN);
    lv_obj_set_style_shadow_width(object, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(object, 0, LV_PART_MAIN);
    lv_obj_set_style_text_font(object, widget->font, LV_PART_MAIN);
    lv_obj_set_style_text_color(object, lv_color_hex(widget->color), LV_PART_MAIN);
    lv_obj_set_style_text_align(object, widget->align, LV_PART_MAIN);
    lv_obj_set_style_border_color(object, lv_color_hex(0x3ee8c0), LV_PART_CURSOR);
    plcui_perf_textarea(PERF_TA_STYLE, plcui_perf_now() - started);
    started = plcui_perf_now();
    lv_textarea_set_one_line(object, widget->one_line);
    if (!widget->one_line) lv_obj_add_flag(object, LV_OBJ_FLAG_SCROLLABLE);
    plcui_perf_textarea(PERF_TA_MODE, plcui_perf_now() - started);
    started = plcui_perf_now();
    /* XML validation has already checked the initial value. Keep the default
       unrestricted bulk path while writing it, then enable input filters. */
    lv_textarea_set_text(object, widget->text);
    plcui_perf_textarea(PERF_TA_TEXT, plcui_perf_now() - started);
    started = plcui_perf_now();
    lv_textarea_set_max_length(object, widget->max_length);
    if (widget->accepted_chars[0]) lv_textarea_set_accepted_chars(object, widget->accepted_chars);
    plcui_perf_textarea(PERF_TA_LIMITS, plcui_perf_now() - started);
    started = plcui_perf_now();
    lv_obj_set_size(object, widget->w, widget->h);
    lv_obj_add_event_cb(object, textarea_event, LV_EVENT_ALL, widget);
    plcui_perf_textarea(PERF_TA_FINAL, plcui_perf_now() - started);
    return object;
}
