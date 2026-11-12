/** @file luat_plcui_runtime.c Documents, generations and deferred Lua events. */
#include "luat_base.h"
#include "luat_plcui.h"
#include "luat_plcui_perf.h"
#include "luat_plcui_debug.h"
#include "luat_msgbus.h"
#include "luat_mcu.h"
#include <limits.h>
#include <string.h>
#include <stdio.h>

static plcui_runtime_t runtime;

/* Protect the complete token, including on 32-bit MCUs without 64-bit atomics.
   No allocation, queue operation, Lua or LVGL call occurs inside this lock. */
static uint64_t refresh_schedule;
static unsigned refresh_pending;

static uint64_t schedule_load(void)
{
    uint32_t lock = plcui_platform_state_lock();
    uint64_t value = refresh_schedule;
    plcui_platform_state_unlock(lock);
    return value;
}

static uint64_t schedule_exchange(uint64_t value)
{
    uint32_t lock = plcui_platform_state_lock();
    uint64_t previous = refresh_schedule;
    refresh_schedule = value;
    plcui_platform_state_unlock(lock);
    return previous;
}

static void pending_store(unsigned value)
{
    uint32_t lock = plcui_platform_state_lock();
    refresh_pending = value;
    plcui_platform_state_unlock(lock);
}

static bool pending_compare_exchange(unsigned *expected, unsigned value)
{
    uint32_t lock = plcui_platform_state_lock();
    bool equal = refresh_pending == *expected;
    if (equal) refresh_pending = value;
    else *expected = refresh_pending;
    plcui_platform_state_unlock(lock);
    return equal;
}
static unsigned refresh_generation;
static uint32_t refresh_epoch_ms;

static uint64_t refresh_token(unsigned generation, uint32_t deadline)
{
    return ((uint64_t)generation << 32) | deadline;
}

static int refresh_message(lua_State *L, void *parameter)
{
    (void)L;
    unsigned generation = (unsigned)(uintptr_t)parameter;
    uint64_t schedule = schedule_load();
    if ((unsigned)(schedule >> 32) != generation || !runtime.initialized) return 0;
    unsigned expected = generation;
    pending_compare_exchange(&expected, 0);
    uint32_t now = (uint32_t)luat_mcu_tick64_ms();
    if ((int32_t)(now - (uint32_t)schedule) < 0) return 0;

    /* Absolute fractional deadlines avoid rounding every 60Hz frame to 20ms
       when the platform wakeup interval is 5ms. Late frames are skipped. */
    uint32_t elapsed = now - refresh_epoch_ms;
    uint64_t next_frame = (uint64_t)elapsed * PLCUI_REFRESH_RATE_HZ / 1000U + 1U;
    uint32_t offset = (uint32_t)((next_frame * 1000U + PLCUI_REFRESH_RATE_HZ - 1U) / PLCUI_REFRESH_RATE_HZ);
    schedule_exchange(refresh_token(generation, refresh_epoch_ms + offset));

    /* Only this display uses the 60Hz gate. A paused, unchanged display stays
       paused; a dirty display can render at the next scheduled frame. */
    lv_timer_t *display_timer = lv_display_get_refr_timer(plcui_platform_display());
    if (display_timer) lv_timer_ready(display_timer);
    for (lv_indev_t *input = lv_indev_get_next(NULL); input; input = lv_indev_get_next(input)) {
        if (lv_indev_get_display(input) == plcui_platform_display()) {
            lv_timer_t *input_timer = lv_indev_get_read_timer(input);
            if (input_timer) lv_timer_ready(input_timer);
        }
    }
    runtime.auto_refresh_count++;
    luat_plcui_refresh();
    return 0;
}

static void refresh_tick(void *parameter)
{
    unsigned generation = (unsigned)(uintptr_t)parameter;
    uint64_t schedule = schedule_load();
    if ((unsigned)(schedule >> 32) != generation) return;
    uint32_t now = (uint32_t)luat_mcu_tick64_ms();
    if ((int32_t)(now - (uint32_t)schedule) < 0) return;
    unsigned expected = 0;
    if (!pending_compare_exchange(&expected, generation)) return;

    /* A stop/restart may race with this callback. Never clear another session's
       pending flag, and leave stale messages harmless in the main-thread queue. */
    if ((unsigned)(schedule_load() >> 32) != generation) {
        expected = generation;
        pending_compare_exchange(&expected, 0);
        return;
    }
    rtos_msg_t message = {
        .handler = refresh_message,
        .ptr = parameter,
        .arg1 = (int)generation,
        .arg2 = 0
    };
    if (luat_msgbus_put(&message, 0) != 0) {
        expected = generation;
        pending_compare_exchange(&expected, 0);
    }
}

bool luat_plcui_start_refresh(void)
{
    if (runtime.auto_refresh) return true;
    refresh_generation = refresh_generation >= INT_MAX ? 1U : refresh_generation + 1U;
    refresh_epoch_ms = (uint32_t)luat_mcu_tick64_ms();
    pending_store(0);
    schedule_exchange(refresh_token(refresh_generation, refresh_epoch_ms + PLCUI_REFRESH_PERIOD_MS));
    if (plcui_platform_timer_start(PLCUI_HANDLER_PERIOD_MS, refresh_tick, (void *)(uintptr_t)refresh_generation) != 0) {
        schedule_exchange(0);
        return false;
    }
    runtime.auto_refresh = true;
    return true;
}

void luat_plcui_stop_refresh(void)
{
    unsigned generation = (unsigned)(schedule_exchange(0) >> 32);
    unsigned expected = generation;
    if (generation) pending_compare_exchange(&expected, 0);
    plcui_platform_timer_stop();
    runtime.auto_refresh = false;
}

plcui_runtime_t *luat_plcui_runtime(void) { return &runtime; }

static size_t utf8_unit(const unsigned char *text, size_t remaining)
{
    if (!remaining || text[0] == 0) return 0;
    if (text[0] < 0x80) return 1;
    size_t bytes = text[0] >= 0xc2 && text[0] <= 0xdf ? 2U : text[0] >= 0xe0 && text[0] <= 0xef ? 3U : text[0] >= 0xf0 && text[0] <= 0xf4 ? 4U : 0U;
    if (!bytes || bytes > remaining) return 0;
    for (size_t i = 1; i < bytes; i++) if ((text[i] & 0xc0U) != 0x80U) return 0;
    if ((text[0] == 0xe0 && text[1] < 0xa0) || (text[0] == 0xed && text[1] >= 0xa0) || (text[0] == 0xf0 && text[1] < 0x90) || (text[0] == 0xf4 && text[1] >= 0x90)) return 0;
    return bytes;
}

bool luat_plcui_check_text(plcui_widget_t *widget, const char *text, size_t length, plcui_error_t *error)
{
    if (length >= PLCUI_TEXT_MAX) { luat_plcui_error(error, "E_SCHEMA", "Text exceeds the 511-byte runtime limit"); return false; }
    unsigned characters = 0;
    for (size_t offset = 0; offset < length;) {
        size_t unit = utf8_unit((const unsigned char *)text + offset, length - offset);
        if (!unit) { luat_plcui_error(error, "E_SCHEMA", "Text must contain valid UTF-8 without NUL bytes"); return false; }
        if (widget->type == PLCUI_TEXTAREA) {
            if (widget->one_line && (text[offset] == '\n' || text[offset] == '\r')) { luat_plcui_error(error, "E_SCHEMA", "Single-line textarea cannot contain line breaks"); return false; }
            if (widget->accepted_chars[0]) {
                bool accepted = false;
                size_t accepted_length = strlen(widget->accepted_chars);
                for (size_t at = 0; at < accepted_length;) {
                    size_t candidate = utf8_unit((const unsigned char *)widget->accepted_chars + at, accepted_length - at);
                    if (!candidate) break;
                    if (candidate == unit && !memcmp(widget->accepted_chars + at, text + offset, unit)) { accepted = true; break; }
                    at += candidate;
                }
                if (!accepted) { luat_plcui_error(error, "E_SCHEMA", "Input contains a character excluded by accepted-chars"); return false; }
            }
        }
        characters++; offset += unit;
    }
    if (widget->type == PLCUI_TEXTAREA && characters > widget->max_length) { luat_plcui_error(error, "E_SCHEMA", "Input exceeds max-length"); return false; }
    return true;
}

void luat_plcui_emit(plcui_widget_t *w, plcui_event_type_t type)
{
    plcui_document_t *doc = w->document;
    if (doc->closed || doc->pending_close || runtime.pending_deinit || doc->silent
        || doc->preparing_page >= 0 || w->page_index != (unsigned)doc->current_page
        || !w->handler[type][0]) return;
    if (type == PLCUI_CHANGE) {
        for (unsigned i = 0; i < doc->event_count; i++) {
            plcui_event_t *event = &doc->events[(doc->event_head + i) % PLCUI_EVENT_CAPACITY];
            if (event->type == type && event->generation == doc->generation && event->page_index == w->page_index && event->widget_index == w->widget_index) {
                snprintf(event->text, sizeof(event->text), "%s", w->text);
                return;
            }
        }
    }
    if (doc->event_count >= PLCUI_EVENT_CAPACITY) { doc->events_dropped++; return; }
    plcui_event_t *event = &doc->events[(doc->event_head + doc->event_count++) % PLCUI_EVENT_CAPACITY];
    memset(event, 0, sizeof(*event));
    event->generation = doc->generation; event->page_index = w->page_index;
    event->widget_index = w->widget_index; event->type = type;
    if (w->type == PLCUI_TEXTAREA) snprintf(event->text, sizeof(event->text), "%s", w->text);
}

void luat_plcui_dispatch(plcui_document_t *doc)
{
    if (doc->closed || doc->dispatching) return;
    lua_State *L = doc->L;
    doc->dispatching = true;
    unsigned processed = 0;
    while (doc->event_count && processed++ < PLCUI_EVENT_CAPACITY && !doc->closed && !doc->pending_close && !runtime.pending_deinit) {
        plcui_event_t event = doc->events[doc->event_head];
        doc->event_head = (doc->event_head + 1U) % PLCUI_EVENT_CAPACITY; doc->event_count--;
        if (event.generation != doc->generation || event.page_index >= doc->page_count) continue;
        plcui_page_t *page = &doc->pages[event.page_index];
        if (event.widget_index >= page->count) continue;
        plcui_widget_t *widget = &page->widgets[event.widget_index];
        int stack = lua_gettop(L);
        lua_rawgeti(L, LUA_REGISTRYINDEX, doc->handlers_ref);
        lua_getfield(L, -1, widget->handler[event.type]);
        if (lua_isfunction(L, -1)) {
            static const char *names[] = {"click", "change", "submit", "cancel"};
            lua_createtable(L, 0, 5);
            lua_pushstring(L, names[event.type]); lua_setfield(L, -2, "type");
            lua_pushstring(L, page->id); lua_setfield(L, -2, "page");
            lua_pushstring(L, widget->id); lua_setfield(L, -2, "id");
            if (widget->type == PLCUI_TEXTAREA) { lua_pushstring(L, event.text); lua_setfield(L, -2, "text"); }
            if (lua_pcall(L, 1, 0, 0) != LUA_OK) fprintf(stderr, "[plcui] handler %s failed: %s\n", widget->handler[event.type], lua_tostring(L, -1));
        }
        lua_settop(L, stack);
    }
    doc->dispatching = false;
}

static bool prepare_business(plcui_document_t *doc, int page, plcui_error_t *error)
{
    if (doc->prepare_ref == LUA_NOREF) return true;
    lua_State *L = doc->L;
    int top = lua_gettop(L);
    lua_rawgeti(L, LUA_REGISTRYINDEX, doc->prepare_ref);
    lua_rawgeti(L, LUA_REGISTRYINDEX, doc->self_ref);
    lua_pushstring(L, doc->pages[page].id);
    int result = lua_pcall(L, 2, 0, 0);
    if (result != LUA_OK) {
        const char *message = lua_tostring(L, -1);
        luat_plcui_error(error, "E_PREPARE", "Page prepare callback failed: %s", message ? message : "non-string error");
    }
    lua_settop(L, top);
    return result == LUA_OK;
}

bool luat_plcui_show(plcui_document_t *doc, int index, plcui_error_t *error)
{
    if (runtime.preparing_document) { luat_plcui_error(error, "E_BUSY", "Page preparation is in progress"); return false; }
    if (doc->closed) { luat_plcui_error(error, "E_OBJECT_CLOSED", "Document is closed"); return false; }
    if (index < 0 || (unsigned)index >= doc->page_count) { luat_plcui_error(error, "E_SCHEMA", "Page does not exist"); return false; }
    if (doc->dispatching || doc->switching) {
        plcui_perf_request(doc, index);
        doc->pending_page = index; return true;
    }
    if (index == doc->current_page) { plcui_perf_request(doc, -1); return true; }
    plcui_perf_begin(doc, index);
    doc->switching = true;
    doc->preparing_page = index;
    runtime.preparing_document = doc;
    plcui_perf_phase(PERF_CREATE);
    uint32_t started = plcui_perf_now();
    bool created = luat_plcui_create_page(doc, index, error);
    plcui_perf_step(PERF_STEP_CREATE, plcui_perf_now() - started);
    if (!created) goto failed;
    started = plcui_perf_now();
    bool initialized = prepare_business(doc, index, error);
    plcui_perf_step(PERF_STEP_INIT, plcui_perf_now() - started);
    if (!initialized) goto failed;
    if (doc->pending_close || runtime.pending_deinit) {
        luat_plcui_error(error, "E_BUSY", "Preparation was cancelled"); goto failed;
    }
    plcui_perf_phase(PERF_CHECK);
    started = plcui_perf_now();
    bool ready = luat_plcui_prepare_page_images(doc, index, error);
    plcui_perf_step(PERF_STEP_CHECK, plcui_perf_now() - started);
    if (!ready) goto failed;
    doc->preparing_page = -1;
    runtime.preparing_document = NULL;
    int old_page = doc->current_page;
    plcui_perf_phase(PERF_SWITCH);
    started = plcui_perf_now();
    luat_plcui_input_finish(doc, false, true);
    plcui_perf_step(PERF_STEP_INPUT, plcui_perf_now() - started);
    started = plcui_perf_now();
    luat_plcui_dispatch(doc);
    plcui_perf_step(PERF_STEP_DISPATCH, plcui_perf_now() - started);
    doc->generation++;
    doc->current_page = index;
    started = plcui_perf_now();
    lv_screen_load(doc->pages[index].screen);
    plcui_perf_step(PERF_STEP_ACTIVATE, plcui_perf_now() - started);
    started = plcui_perf_now();
    luat_plcui_destroy_page(doc, old_page);
    plcui_perf_step(PERF_STEP_DESTROY, plcui_perf_now() - started);
    doc->event_count = 0; doc->event_head = 0;
    doc->switching = false;
    plcui_perf_arm(doc->pages[index].screen);
    return true;
failed:
    doc->preparing_page = -1;
    runtime.preparing_document = NULL;
    luat_plcui_destroy_page(doc, index);
    doc->switching = false;
    plcui_perf_fail(error && error->code ? error->code : "prepare_failed");
    return false;
}

void luat_plcui_close(plcui_document_t *doc)
{
    if (!doc || doc->closed) return;
    if (doc->dispatching || doc->switching || doc->preparing_page >= 0) { doc->pending_close = true; return; }
    plcui_perf_cancel(doc);
    luat_plcui_input_finish(doc, false, false);
    doc->closed = true; doc->generation++;
    doc->event_count = 0; doc->event_head = 0;
    if (runtime.document == doc) {
        if (runtime.idle_screen && runtime.initialized) lv_screen_load(runtime.idle_screen);
        runtime.document = NULL;
    }
    for (unsigned i = 0; i < doc->page_count; ++i) luat_plcui_destroy_page(doc, (int)i);
    doc->current_page = -1;
    luat_plcui_free_description(doc);
    if (doc->prepare_ref != LUA_NOREF) { luaL_unref(doc->L, LUA_REGISTRYINDEX, doc->prepare_ref); doc->prepare_ref = LUA_NOREF; }
    if (doc->handlers_ref != LUA_NOREF) { luaL_unref(doc->L, LUA_REGISTRYINDEX, doc->handlers_ref); doc->handlers_ref = LUA_NOREF; }
    if (doc->self_ref != LUA_NOREF) { luaL_unref(doc->L, LUA_REGISTRYINDEX, doc->self_ref); doc->self_ref = LUA_NOREF; }
}

void luat_plcui_deinit(void)
{
    if (!runtime.initialized) { plcui_debug_set(false); return; }
    if (runtime.preparing_document || runtime.refreshing || (runtime.document && (runtime.document->dispatching || runtime.document->switching))) { runtime.pending_deinit = true; return; }
    luat_plcui_stop_refresh();
    if (runtime.document) luat_plcui_close(runtime.document);
    plcui_perf_reset();
    plcui_debug_set(false);
    lua_pushnil(runtime.L);
    lua_setfield(runtime.L, LUA_REGISTRYINDEX, "plcui_active");
    plcui_platform_deinit();
    plcui_platform_image_deinit();
    lua_pushnil(runtime.L);
    lua_setfield(runtime.L, LUA_REGISTRYINDEX, "plcui_touch");
    lv_deinit();
    memset(&runtime, 0, sizeof(runtime));
}

void luat_plcui_refresh(void)
{
    if (!runtime.initialized || runtime.refreshing || runtime.preparing_document) return;
    runtime.refreshing = true;
    plcui_document_t *doc = runtime.document;
    lua_State *L = runtime.L;
    bool anchored = doc && doc->self_ref != LUA_NOREF;
    if (anchored) lua_rawgeti(L, LUA_REGISTRYINDEX, doc->self_ref);
    plcui_platform_poll();
    lv_timer_handler();
    if (doc && !doc->closed) {
        luat_plcui_dispatch(doc);
        if (doc->pending_close) luat_plcui_close(doc);
        else if (doc->pending_page >= 0) {
            int page = doc->pending_page;
            doc->pending_page = -1;
            plcui_error_t error;
            if (!luat_plcui_show(doc, page, &error)) fprintf(stderr, "[plcui] deferred page switch failed: %s\n", error.message);
        }
    }
    plcui_perf_poll();
    plcui_debug_poll();
    runtime.refreshing = false;
    if (runtime.pending_deinit) luat_plcui_deinit();
    if (anchored) lua_pop(L, 1);
}
