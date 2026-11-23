/** @file luat_plcui_animimg.c Bounded frame leases on the existing UI scheduler. */
#include "luat_plcui_component.h"
#include "luat_plcui_debug.h"
#include "luat_mcu.h"

static uint32_t now_ms(void) { return (uint32_t)luat_mcu_tick64_ms(); }

static bool active(plcui_widget_t *widget)
{
    return luat_plcui_component_interactive(widget) && luat_plcui_component_visible(widget);
}

static bool select_frame(plcui_widget_t *widget, uint16_t frame, plcui_error_t *error)
{
    plcui_animimg_t *a = widget->animation;
    if (a->current && a->current_frame == frame) {
        if (!luat_plcui_image_bind(widget, a->frames[frame], a->current, error)) return false;
        a->frame = frame;
        return true;
    }
    /* This runs on the UI thread outside drawing. Retiring entries from an
       earlier synchronous setter have no queued draw readers. */
    luat_plcui_image_release(&a->retiring);
    if (!a->next || a->next_frame != frame) {
        luat_plcui_image_release(&a->next);
        if (!luat_plcui_image_acquire(widget, a->frames[frame], &a->next, error)) return false;
        a->next_frame = frame;
    }
    if (!luat_plcui_image_bind(widget, a->frames[frame], a->next, error)) {
        luat_plcui_image_release(&a->next);
        return false;
    }
    a->retiring = a->current;
    a->current = a->next; a->next = NULL;
    a->frame = frame; a->current_frame = frame;
    a->awaiting_present = true;
    return true;
}

bool luat_plcui_animimg_prepare(plcui_widget_t *widget, plcui_error_t *error)
{
    plcui_animimg_t *a = widget->animation;
    return select_frame(widget, a->frame, error);
}

lv_obj_t *luat_plcui_animimg_create(plcui_widget_t *widget, lv_obj_t *parent)
{
    lv_obj_t *object = lv_image_create(parent);
    if (!object) return NULL;
    luat_plcui_component_init(widget, object);
    lv_obj_remove_flag(object, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_CLICK_FOCUSABLE);
    lv_image_set_inner_align(object, LV_IMAGE_ALIGN_TOP_LEFT);
    plcui_animimg_t *a = widget->animation;
    a->frame = 0; a->completed_loops = 0; a->failed_frame = 0;
    a->ready = false; a->suspended = true;
    a->awaiting_present = true;
    a->remaining = a->interval_ms;
    a->state = a->auto_start ? PLCUI_ANIM_PLAYING : PLCUI_ANIM_STOPPED;
    return object;
}

bool luat_plcui_animimg_play(plcui_widget_t *widget, plcui_error_t *error)
{
    plcui_animimg_t *a = widget->animation;
    if (a->state == PLCUI_ANIM_PLAYING) return true;
    uint16_t target = a->state == PLCUI_ANIM_ERROR ? a->failed_frame :
        a->state == PLCUI_ANIM_PAUSED ? a->frame : 0;
    bool completed_loop = a->state == PLCUI_ANIM_ERROR && !target && a->frame + 1U == a->count;
    if (widget->document->preparing_page < 0 && active(widget) && !select_frame(widget, target, error)) return false;
    if (a->state != PLCUI_ANIM_PAUSED) a->remaining = a->interval_ms;
    if (a->state == PLCUI_ANIM_FINISHED || a->state == PLCUI_ANIM_STOPPED) a->completed_loops = 0;
    else if (completed_loop) a->completed_loops++;
    a->frame = target;
    a->state = PLCUI_ANIM_PLAYING;
    a->suspended = !a->ready || !active(widget);
    a->deadline = now_ms() + a->remaining;
    return true;
}

void luat_plcui_animimg_pause(plcui_widget_t *widget)
{
    plcui_animimg_t *a = widget->animation;
    if (a->state != PLCUI_ANIM_PLAYING) return;
    if (!a->suspended) {
        int32_t left = (int32_t)(a->deadline - now_ms());
        a->remaining = left > 0 ? (uint32_t)left : 0;
    }
    a->state = PLCUI_ANIM_PAUSED;
    luat_plcui_image_release(&a->next);
}

bool luat_plcui_animimg_stop(plcui_widget_t *widget, plcui_error_t *error)
{
    plcui_animimg_t *a = widget->animation;
    a->state = PLCUI_ANIM_STOPPED; a->completed_loops = 0;
    a->remaining = a->interval_ms; a->suspended = true;
    luat_plcui_image_release(&a->next);
    if (widget->document->preparing_page < 0 && active(widget)) return select_frame(widget, 0, error);
    a->frame = 0;
    return true;
}

void luat_plcui_animimg_destroy(plcui_widget_t *widget)
{
    plcui_animimg_t *a = widget->animation;
    if (!a) return;
    a->ready = false;
    luat_plcui_image_release(&a->current);
    luat_plcui_image_release(&a->next);
    luat_plcui_image_release(&a->retiring);
}

static void animation_error(plcui_widget_t *widget, uint16_t target, const plcui_error_t *error)
{
    plcui_animimg_t *a = widget->animation;
    a->state = PLCUI_ANIM_ERROR; a->failed_frame = target;
    luat_plcui_image_release(&a->next);
    luat_plcui_animimg_emit(widget, PLCUI_ERROR, error);
}

void luat_plcui_components_sync(plcui_document_t *document)
{
    if (!document || document->closed || document->current_page < 0 || document->preparing_page >= 0) return;
    plcui_page_t *page = &document->pages[document->current_page];
    lv_obj_update_layout(page->screen);
    for (unsigned i = 0; i < page->count; ++i) {
        plcui_widget_t *widget = &page->widgets[i];
        if (widget->label) luat_plcui_label_sync(widget);
        plcui_animimg_t *a = widget->animation;
        if (a && a->state == PLCUI_ANIM_PLAYING && !a->suspended && !active(widget)) {
            int32_t left = (int32_t)(a->deadline - now_ms());
            a->remaining = left > 0 ? (uint32_t)left : 0;
            a->suspended = true;
            luat_plcui_image_release(&a->next);
        }
    }
}

void luat_plcui_components_tick(plcui_document_t *document)
{
    if (!document || document->closed || document->current_page < 0) return;
    plcui_page_t *page = &document->pages[document->current_page];
    lv_obj_update_layout(page->screen);
    /* Rotate the first candidate for fair IO admission; at most one new frame
       decode per UI iteration, including failed attempts. Never catch up in a loop. */
    static unsigned first;
    bool io_used = false;
    unsigned start = page->count ? first % page->count : 0;
    for (unsigned n = 0; n < page->count; ++n) {
        plcui_widget_t *widget = &page->widgets[(start + n) % page->count];
        if (widget->label) luat_plcui_label_sync(widget);
        plcui_animimg_t *a = widget->animation;
        if (!a || !a->ready || a->state != PLCUI_ANIM_PLAYING) continue;
        uint32_t now = now_ms();
        if (!active(widget)) {
            if (!a->suspended) {
                int32_t left = (int32_t)(a->deadline - now);
                a->remaining = left > 0 ? (uint32_t)left : 0;
                a->suspended = true;
                luat_plcui_image_release(&a->next);
            }
            continue;
        }
        if (!a->current || a->current_frame != a->frame) {
            if (io_used) continue;
            io_used = true;
            first = (start + n + 1U) % page->count;
            plcui_error_t error;
            if (!select_frame(widget, a->frame, &error)) { animation_error(widget, a->frame, &error); continue; }
            a->remaining = a->interval_ms;
            now = now_ms();
            a->deadline = now + a->remaining;
        }
        if (a->awaiting_present) continue;
        if (a->suspended) { a->deadline = now + a->remaining; a->suspended = false; }
        if ((int32_t)(now - a->deadline) >= 0 && a->frame + 1U == a->count
            && a->repeat_count > 0 && a->completed_loops + 1U >= (uint32_t)a->repeat_count) {
            a->completed_loops++; a->state = PLCUI_ANIM_FINISHED;
            luat_plcui_image_release(&a->next);
            luat_plcui_animimg_emit(widget, PLCUI_FINISHED, NULL);
            continue;
        }
        uint16_t target = (uint16_t)((a->frame + 1U) % a->count);
        bool final = a->frame + 1U == a->count && a->repeat_count > 0
            && a->completed_loops + 1U >= (uint32_t)a->repeat_count;
        if (!final && !a->next && !a->retiring && !io_used) {
            io_used = true;
            first = (start + n + 1U) % page->count;
            plcui_error_t error;
            uint32_t began = plcui_debug_now();
            bool ok = luat_plcui_image_acquire(widget, a->frames[target], &a->next, &error);
            if (plcui_debug_enabled()) plcui_debug_record(PLCUI_ANIMIMG, "update", "prepare_frame", page->id, widget->id, plcui_debug_now() - began, ok);
            if (!ok) { animation_error(widget, target, &error); continue; }
            a->next_frame = target;
        }
        if (a->next && (int32_t)(now_ms() - a->deadline) >= 0) {
            plcui_error_t error;
            if (!select_frame(widget, target, &error)) { animation_error(widget, target, &error); continue; }
            if (!target) a->completed_loops++;
            a->remaining = a->interval_ms;
            /* Slow IO extends a frame; do not shorten the newly displayed one. */
            a->deadline = now_ms() + a->interval_ms;
        }
    }
}

void luat_plcui_components_presented(plcui_document_t *document)
{
    if (!document || document->closed || document->current_page < 0) return;
    plcui_page_t *page = &document->pages[document->current_page];
    for (unsigned i = 0; i < page->count; ++i) {
        plcui_widget_t *widget = &page->widgets[i];
        if (widget->label) widget->label->ready = true;
        if (widget->animation) {
            plcui_animimg_t *a = widget->animation;
            a->ready = true;
            if (a->awaiting_present && a->current && a->current_frame == a->frame && active(widget)) {
                a->awaiting_present = false;
                a->suspended = false;
                a->deadline = now_ms() + a->remaining;
            }
        }
    }
}

void luat_plcui_components_retire(plcui_document_t *document)
{
    if (!document || document->closed || document->current_page < 0) return;
    plcui_page_t *page = &document->pages[document->current_page];
    for (unsigned i = 0; i < page->count; ++i)
        if (page->widgets[i].animation) luat_plcui_image_release(&page->widgets[i].animation->retiring);
}
