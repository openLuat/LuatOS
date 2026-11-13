/** @file luat_plcui_page.c Page assembly and shared component hierarchy behavior. */
#include "luat_plcui_component.h"
#include "luat_plcui_perf.h"
#include "luat_plcui_debug.h"
#include "lvgl9/src/core/lv_obj_event_private.h"
#include "lvgl9/src/indev/lv_indev_private.h"

static const plcui_widget_t *parent_of(const plcui_widget_t *widget)
{
    if (!widget || !widget->document || widget->parent_index < 0 || widget->page_index >= widget->document->page_count) return NULL;
    const plcui_page_t *page = &widget->document->pages[widget->page_index];
    if ((unsigned)widget->parent_index >= page->count || (unsigned)widget->parent_index >= widget->widget_index) return NULL;
    return &page->widgets[widget->parent_index];
}

bool luat_plcui_component_is_within(const plcui_widget_t *widget, const plcui_widget_t *ancestor)
{
    if (!widget || !ancestor || widget->document != ancestor->document || widget->page_index != ancestor->page_index) return false;
    for (const plcui_widget_t *current = widget; current; current = parent_of(current)) {
        if (current == ancestor) return true;
    }
    return false;
}

static bool effective_disabled(const plcui_widget_t *widget)
{
    for (const plcui_widget_t *current = widget; current; current = parent_of(current)) {
        if (current->disabled) return true;
    }
    return false;
}

bool luat_plcui_component_ancestors_interactive(const plcui_widget_t *widget)
{
    if (!widget || !widget->document || widget->document->closed) return false;
    for (const plcui_widget_t *current = parent_of(widget); current; current = parent_of(current)) {
        if (!current->obj || current->disabled || lv_obj_has_flag(current->obj, LV_OBJ_FLAG_HIDDEN)) return false;
    }
    return true;
}

bool luat_plcui_component_interactive(const plcui_widget_t *widget)
{
    return widget && widget->obj && !widget->disabled
        && !lv_obj_has_flag(widget->obj, LV_OBJ_FLAG_HIDDEN)
        && luat_plcui_component_ancestors_interactive(widget);
}

bool luat_plcui_component_sync_disabled(plcui_widget_t *root, plcui_error_t *error)
{
    if (!root || !root->document || root->page_index >= root->document->page_count) return true;
    plcui_page_t *page = &root->document->pages[root->page_index];
    for (unsigned i = 0; i < page->count; ++i) {
        plcui_widget_t *widget = &page->widgets[i];
        if (!widget->obj || !luat_plcui_component_is_within(widget, root)) continue;
        if (effective_disabled(widget)) {
            lv_obj_add_state(widget->obj, LV_STATE_DISABLED);
        } else {
            lv_obj_remove_state(widget->obj, LV_STATE_DISABLED);
        }
    }
    bool ready = root->document->preparing_page >= 0
        || luat_plcui_prepare_page_images(root->document, (int)root->page_index, error);
    if (ready) {
        for (unsigned i = 0; i < page->count; ++i) {
            plcui_widget_t *widget = &page->widgets[i];
            if (luat_plcui_component_is_within(widget, root) && effective_disabled(widget)) widget->pressed = false;
        }
    }
    return ready;
}

static void component_hit_test(lv_event_t *event)
{
    plcui_widget_t *widget = lv_event_get_user_data(event);
    lv_hit_test_info_t *info = lv_event_get_hit_test_info(event);
    if (info && !luat_plcui_component_interactive(widget)) info->res = false;
}

void luat_plcui_component_init(plcui_widget_t *widget, lv_obj_t *object)
{
    widget->obj = object;
    lv_obj_set_align(object, LV_ALIGN_TOP_LEFT);
    lv_obj_set_pos(object, widget->x, widget->y);
    lv_obj_set_size(object, widget->w, widget->h);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(object, LV_OBJ_FLAG_EVENT_BUBBLE | LV_OBJ_FLAG_ADV_HITTEST);
    lv_obj_add_event_cb(object, component_hit_test, LV_EVENT_HIT_TEST, widget);
    if (widget->hidden) lv_obj_add_flag(object, LV_OBJ_FLAG_HIDDEN);
    if (effective_disabled(widget)) lv_obj_add_state(object, LV_STATE_DISABLED);
}

static bool object_within(lv_obj_t *object, lv_obj_t *ancestor)
{
    if (!ancestor) return false;
    for (; object; object = lv_obj_get_parent(object)) if (object == ancestor) return true;
    return false;
}

void luat_plcui_component_cancel_pointer(plcui_widget_t *root, const char *reason)
{
    if (!root || !root->obj) return;
    plcui_page_t *page = &root->document->pages[root->page_index];
    for (unsigned i = 0; i < page->count; ++i) {
        plcui_widget_t *widget = &page->widgets[i];
        if (luat_plcui_component_is_within(widget, root) && widget->slider)
            luat_plcui_slider_cancel(widget, reason);
    }
    for (lv_indev_t *input = lv_indev_get_next(NULL); input; input = lv_indev_get_next(input)) {
        if (lv_indev_get_type(input) != LV_INDEV_TYPE_POINTER || !object_within(input->pointer.act_obj, root->obj)) continue;
        lv_indev_reset(input, input->pointer.act_obj);
        lv_indev_wait_release(input);
    }
}

bool luat_plcui_component_set_pos(plcui_widget_t *widget, int32_t x, int32_t y, plcui_error_t *error)
{
    if (x < -4096 || x > 4096 || y < -4096 || y > 4096) {
        luat_plcui_error(error, "E_SCHEMA", "Position must be between -4096 and 4096"); return false;
    }
    if (widget->x == x && widget->y == y) return true;
    int32_t old_x = widget->x, old_y = widget->y;
    widget->x = x; widget->y = y;
    lv_obj_set_pos(widget->obj, x, y);
    plcui_document_t *doc = widget->document;
    if (doc->preparing_page < 0 && !luat_plcui_prepare_page_images(doc, (int)widget->page_index, error)) {
        widget->x = old_x; widget->y = old_y;
        lv_obj_set_pos(widget->obj, old_x, old_y);
        lv_obj_update_layout(widget->obj);
        return false;
    }
    luat_plcui_component_cancel_pointer(widget, "position_changed");
    if ((luat_plcui_component_is_within(doc->editing, widget) || luat_plcui_component_is_within(doc->keyboard, widget))
        && doc->editing
        && (!luat_plcui_component_visible(doc->editing) || (doc->keyboard && !luat_plcui_component_visible(doc->keyboard))))
        luat_plcui_input_finish(doc, false, true);
    luat_plcui_components_sync(doc);
    return true;
}

static void screen_event(lv_event_t *event)
{
    plcui_document_t *document = lv_event_get_user_data(event);
    if (document->closed || !document->editing) return;
    lv_obj_t *target = lv_event_get_target(event);
    if (object_within(target, document->editing->obj)
        || (document->keyboard && object_within(target, document->keyboard->obj))) return;
    luat_plcui_input_finish(document, false, true);
}

static lv_obj_t *create_widget(plcui_widget_t *widget, lv_obj_t *parent)
{
    switch (widget->type) {
    case PLCUI_IMAGE: return luat_plcui_image_create(widget, parent);
    case PLCUI_LABEL: return luat_plcui_label_create(widget, parent);
    case PLCUI_TEXTAREA: return luat_plcui_textarea_create(widget, parent);
    case PLCUI_KEYBOARD: return luat_plcui_keyboard_create(widget, parent);
    case PLCUI_CONTAINER: return luat_plcui_container_create(widget, parent);
    case PLCUI_TABLE: return luat_plcui_table_create(widget, parent);
    case PLCUI_CHART: return luat_plcui_chart_create(widget, parent);
    case PLCUI_ANIMIMG: return luat_plcui_animimg_create(widget, parent);
    case PLCUI_SLIDER: return luat_plcui_slider_create(widget, parent);
    }
    return NULL;
}

bool luat_plcui_create_page(plcui_document_t *document, int index, plcui_error_t *error)
{
    plcui_page_t *page = &document->pages[index];
    page->instance_generation++;
    page->screen = lv_obj_create(NULL);
    if (!page->screen) { luat_plcui_error(error, "E_MEMORY", "Cannot create page"); return false; }
    lv_obj_remove_style_all(page->screen);
    lv_obj_set_size(page->screen, document->width, document->height);
    lv_obj_set_style_bg_color(page->screen, lv_color_hex(page->background), 0);
    lv_obj_set_style_bg_opa(page->screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(page->screen, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(page->screen, screen_event, LV_EVENT_PRESSED, document);
    /* Textarea constructors and cursor updates synchronously lay out their
       entire screen. Build one editor at a time on a separate screen so these
       calls do not repeatedly walk the growing candidate page. */
    lv_obj_t *textarea_stage = NULL;
    for (unsigned pass = 0; pass < 2; ++pass) {
        for (unsigned i = 0; i < page->count; ++i) {
            plcui_widget_t *widget = &page->widgets[i];
            /* Finish non-editors first. Otherwise their later construction forces
               pending editor layout again and merely moves time between widgets. */
            if ((widget->type == PLCUI_TEXTAREA) != (pass == 1)) continue;
            lv_obj_t *parent = page->screen;
            if (widget->parent_index >= 0) {
                if ((unsigned)widget->parent_index >= i
                    || page->widgets[widget->parent_index].type != PLCUI_CONTAINER
                    || !page->widgets[widget->parent_index].obj) {
                    luat_plcui_error(error, "E_SCHEMA", "Component parent must be a preceding container: %s", widget->id);
                    if (textarea_stage) lv_obj_delete(textarea_stage);
                    luat_plcui_destroy_page(document, index);
                    return false;
                }
                parent = page->widgets[widget->parent_index].obj;
            }
            uint32_t started = plcui_debug_now();
            if (widget->type == PLCUI_TEXTAREA && !textarea_stage) {
                textarea_stage = lv_obj_create(NULL);
                if (!textarea_stage) {
                    luat_plcui_destroy_page(document, index);
                    luat_plcui_error(error, "E_MEMORY", "Cannot create textarea staging screen");
                    return false;
                }
                lv_obj_remove_style_all(textarea_stage);
                lv_obj_set_size(textarea_stage, document->width, document->height);
                lv_obj_remove_flag(textarea_stage, LV_OBJ_FLAG_SCROLLABLE);
            }
            lv_obj_t *object = create_widget(widget, widget->type == PLCUI_TEXTAREA ? textarea_stage : parent);
            if (object && widget->type == PLCUI_TEXTAREA) {
                uint32_t attach = plcui_perf_now();
                lv_obj_set_parent(object, parent);
                lv_obj_set_pos(object, widget->x, widget->y);
                lv_obj_set_size(object, widget->w, widget->h);
                unsigned sibling = 0;
                for (unsigned previous = 0; previous < i; ++previous)
                    if (page->widgets[previous].parent_index == widget->parent_index) sibling++;
                lv_obj_move_to_index(object, (int32_t)sibling);
                plcui_perf_textarea(PERF_TA_FINAL, plcui_perf_now() - attach);
            }
            uint32_t elapsed = plcui_debug_now() - started;
            plcui_perf_component(widget->type, elapsed);
            if (plcui_debug_enabled())
                plcui_debug_record(widget->type, "create", "create", page->id, widget->id,
                                   elapsed, object != NULL);
            if (!object) {
                if (textarea_stage) lv_obj_delete(textarea_stage);
                luat_plcui_destroy_page(document, index);
                luat_plcui_error(error, "E_MEMORY", "Cannot create component: %s", widget->id);
                return false;
            }
        }
    }
    if (textarea_stage) lv_obj_delete(textarea_stage);
    return true;
}

void luat_plcui_destroy_page(plcui_document_t *document, int index)
{
    if (index < 0 || (unsigned)index >= document->page_count) return;
    plcui_page_t *page = &document->pages[index];
    if (page->screen) lv_obj_delete(page->screen);
    page->screen = NULL;
    luat_plcui_release_page_images(document, index);
    page->instance_generation++;
    for (unsigned i = 0; i < page->count; ++i) {
        if (page->widgets[i].animation) luat_plcui_animimg_destroy(&page->widgets[i]);
        page->widgets[i].obj = NULL;
        if (page->widgets[i].chart) {
            plcui_chart_t *chart = page->widgets[i].chart;
            for (unsigned j = 0; j < chart->count; ++j) chart->series[j].native = NULL;
        }
    }
}
