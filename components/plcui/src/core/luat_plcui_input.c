/** @file luat_plcui_input.c Shared textarea editing and keyboard session coordination. */
#include "luat_plcui_component.h"
#include <stdio.h>
#include <string.h>

void luat_plcui_input_finish(plcui_document_t *document, bool submit, bool notify)
{
    plcui_widget_t *textarea = document->editing;
    if (!textarea) return;
    plcui_widget_t *keyboard = document->keyboard;
    document->editing = NULL;
    document->keyboard = NULL;
    bool was_silent = document->silent;
    document->silent = true;
    if (!submit && textarea->obj) lv_textarea_set_text(textarea->obj, document->edit_original);
    if (textarea->obj) {
        snprintf(textarea->text, sizeof(textarea->text), "%s", lv_textarea_get_text(textarea->obj));
        lv_obj_remove_state(textarea->obj, LV_STATE_FOCUSED);
    }
    if (keyboard && keyboard->obj) {
        lv_keyboard_set_textarea(keyboard->obj, NULL);
        lv_obj_add_flag(keyboard->obj, LV_OBJ_FLAG_HIDDEN);
    }
    document->silent = was_silent;
    if (notify) luat_plcui_emit(textarea, submit ? PLCUI_SUBMIT : PLCUI_CANCEL);
}

void luat_plcui_input_begin(plcui_widget_t *textarea)
{
    plcui_document_t *document = textarea->document;
    if (!luat_plcui_component_interactive(textarea) || document->editing == textarea) return;
    luat_plcui_input_finish(document, false, true);
    document->editing = textarea;
    snprintf(document->edit_original, sizeof(document->edit_original), "%s", lv_textarea_get_text(textarea->obj));
    lv_obj_add_state(textarea->obj, LV_STATE_FOCUSED);
    plcui_page_t *page = &document->pages[textarea->page_index];
    for (unsigned i = 0; i < page->count; ++i) {
        plcui_widget_t *keyboard = &page->widgets[i];
        if (keyboard->type != PLCUI_KEYBOARD || strcmp(keyboard->id, textarea->keyboard_id)
            || !keyboard->obj || keyboard->disabled || !luat_plcui_component_ancestors_interactive(keyboard)) continue;
        document->keyboard = keyboard;
        lv_keyboard_set_textarea(keyboard->obj, textarea->obj);
        lv_obj_remove_flag(keyboard->obj, LV_OBJ_FLAG_HIDDEN);
        /* Reordering remains within the declared container, preserving its clipping. */
        lv_obj_move_foreground(keyboard->obj);
        break;
    }
}
