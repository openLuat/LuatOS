/*
@module input
@summary Unified keyboard, mouse and touch input
@tag LUAT_USE_INPUT_LUA
*/
#include "luat_base.h"
#ifdef LUAT_USE_INPUT_LUA
#include "luat_input_service.h"
#include "luat_msgbus.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include <string.h>
#define LUAT_LOG_TAG "input.lua"
#include "luat_log.h"
#include "rotable2.h"

#define SUB_MT "input.subscription"
#define FRAME_MT "input.frame"
#define OWN_MT "input.snapshots"
#define SUBS_KEY "luat.input.subscriptions"
#define FRAME_BUDGET 8U

typedef struct {
    luat_input_subscription_t sub;
    void *buffer;
    int callback, slot;
    uint8_t closed, registered;
} lua_input_sub_t;
typedef struct {
    luat_input_frame_t header;
    luat_input_event_t events[];
} lua_input_frame_t;
typedef struct {
    luat_input_service_info_t *items[LUAT_INPUT_SERVICE_DEVICES];
} lua_input_owned_t;

static luat_rtos_timer_t retry_timer;
static unsigned active_subscriptions; /* Lua thread only. */
static uint32_t pending;
static int dispatch(lua_State *L, void *ptr);

static void notify(void *userdata)
{
    (void)userdata;
    if (__atomic_exchange_n(&pending, 1, __ATOMIC_ACQ_REL)) return;
    rtos_msg_t msg = {.handler = dispatch};
    if (luat_msgbus_put(&msg, 0)) __atomic_store_n(&pending, 0, __ATOMIC_RELEASE);
}

static void integer(lua_State *L, const char *key, lua_Integer value)
{
    lua_pushinteger(L, value); lua_setfield(L, -2, key);
}
static void string(lua_State *L, const char *key, const char *value)
{
    lua_pushstring(L, value); lua_setfield(L, -2, key);
}
static int error_result(lua_State *L, const char *error)
{
    lua_pushnil(L); lua_pushstring(L, error); return 2;
}
static void release_owned(lua_input_owned_t *owned)
{
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++) {
        luat_heap_free(owned->items[i]); owned->items[i] = NULL;
    }
}
static int owned_gc(lua_State *L)
{
    release_owned(luaL_checkudata(L, 1, OWN_MT));
    return 0;
}
static lua_input_owned_t *new_owned(lua_State *L)
{
    lua_input_owned_t *owned = lua_newuserdata(L, sizeof(*owned));
    memset(owned, 0, sizeof(*owned));
    luaL_setmetatable(L, OWN_MT);
    return owned;
}

static void push_state(lua_State *L, const luat_input_service_info_t *info)
{
    const luat_input_axis_t *abs = (const void *)(info->data + info->key_words);
    const luat_input_axis_t *mt = abs + info->abs_count;
    const uint32_t *state = (const void *)(mt + info->mt_count);
    lua_createtable(L, 0, 7);
    integer(L, "id", info->snapshot.device_id);
    integer(L, "sequence", info->snapshot.sequence);
    integer(L, "timestamp_ms", info->snapshot.timestamp_ms);
    integer(L, "slot", info->snapshot.mt_slot);
    lua_newtable(L);
    for (unsigned i = 0; i < info->key_words * 32U; i++) {
        if (!(state[i / 32U] & (UINT32_C(1) << (i % 32U)))) continue;
        lua_pushboolean(L, 1); lua_rawseti(L, -2, i);
    }
    lua_setfield(L, -2, "keys");
    state += info->key_words;
    lua_newtable(L);
    for (unsigned i = 0; i < info->abs_count; i++) {
        lua_pushinteger(L, (int32_t)state[i]); lua_rawseti(L, -2, abs[i].code);
    }
    lua_setfield(L, -2, "abs");
    state += info->abs_count;
    lua_newtable(L);
    for (unsigned slot = 0; slot < info->mt_slots; slot++) {
        lua_newtable(L);
        for (unsigned i = 0; i < info->mt_count; i++) {
            lua_pushinteger(L, (int32_t)state[slot * info->mt_count + i]);
            lua_rawseti(L, -2, mt[i].code);
        }
        lua_rawseti(L, -2, slot);
    }
    lua_setfield(L, -2, "slots");
}
static void push_axes(lua_State *L, const luat_input_axis_t *axes, unsigned count)
{
    lua_newtable(L);
    for (unsigned i = 0; i < count; i++) {
        lua_createtable(L, 0, 3);
        integer(L, "min", axes[i].minimum); integer(L, "max", axes[i].maximum);
        integer(L, "initial", axes[i].initial);
        lua_rawseti(L, -2, axes[i].code);
    }
}
static void push_bits(lua_State *L, const uint32_t *bits, unsigned words)
{
    lua_newtable(L);
    unsigned n = 0;
    for (unsigned i = 0; i < words * 32U; i++) {
        if (!(bits[i / 32U] & (UINT32_C(1) << (i % 32U)))) continue;
        lua_pushinteger(L, i); lua_rawseti(L, -2, ++n);
    }
}
static void push_info(lua_State *L, const luat_input_service_info_t *info, int brief)
{
    lua_createtable(L, 0, brief ? 7 : 9);
    integer(L, "id", info->snapshot.device_id); string(L, "name", info->name);
    integer(L, "bus", info->bus); integer(L, "vendor", info->vendor);
    integer(L, "product", info->product); integer(L, "version", info->version);
    integer(L, "properties", info->properties);
    if (brief) return;
    lua_newtable(L);
    push_bits(L, info->data, info->key_words); lua_setfield(L, -2, "keys");
    push_bits(L, &info->rel_bits, 1); lua_setfield(L, -2, "rel");
    push_bits(L, &info->msc_bits, 1); lua_setfield(L, -2, "msc");
    const luat_input_axis_t *axes = (const void *)(info->data + info->key_words);
    push_axes(L, axes, info->abs_count); lua_setfield(L, -2, "abs");
    push_axes(L, axes + info->abs_count, info->mt_count); lua_setfield(L, -2, "mt");
    integer(L, "mt_slots", info->mt_slots);
    lua_setfield(L, -2, "caps");
    push_state(L, info); lua_setfield(L, -2, "state");
}

/** @api input.list() @return table Current device summaries. */
static int l_list(lua_State *L)
{
    uint32_t ids[LUAT_INPUT_SERVICE_DEVICES];
    lua_input_owned_t *owned = new_owned(L);
    luat_input_service_lock();
    size_t count = luat_input_service_list(ids, LUAT_INPUT_SERVICE_DEVICES);
    int failed = 0;
    for (size_t i = 0; i < count; i++) {
        owned->items[i] = luat_input_service_info(ids[i]);
        if (!owned->items[i]) failed = 1;
    }
    luat_input_service_unlock();
    if (failed) { release_owned(owned); return error_result(L, "no_memory"); }
    lua_createtable(L, (int)count, 0);
    for (size_t i = 0; i < count; i++) {
        push_info(L, owned->items[i], 1); lua_rawseti(L, -2, (lua_Integer)i + 1);
    }
    release_owned(owned);
    return 1;
}
static uint32_t check_id(lua_State *L, int index)
{
    lua_Integer id = luaL_checkinteger(L, index);
    luaL_argcheck(L, id > 0 && (uint64_t)id <= UINT32_MAX, index, "invalid device id");
    return (uint32_t)id;
}
static int query(lua_State *L, int state_only)
{
    uint32_t id = check_id(L, 1);
    lua_input_owned_t *owned = new_owned(L);
    luat_input_handle_t handle;
    luat_input_service_lock();
    int ret = luat_input_lookup(luat_input_service_core(), id, &handle);
    if (!ret) owned->items[0] = luat_input_service_info(id);
    luat_input_service_unlock();
    if (ret) return error_result(L, "not_found");
    if (!owned->items[0]) return error_result(L, "no_memory");
    if (state_only) push_state(L, owned->items[0]); else push_info(L, owned->items[0], 0);
    release_owned(owned);
    return 1;
}
/** @api input.info(id) @return table|nil Capabilities and current state. */
static int l_info(lua_State *L) { return query(L, 0); }
/** @api input.state(id) @return table|nil Current state snapshot. */
static int l_state(lua_State *L) { return query(L, 1); }

static int frame_get(lua_State *L)
{
    lua_input_frame_t *frame = luaL_checkudata(L, 1, FRAME_MT);
    lua_Integer index = luaL_checkinteger(L, 2);
    luaL_argcheck(L, index >= 1 && index <= frame->header.count, 2, "event index out of range");
    const luat_input_event_t *event = &frame->events[index - 1];
    lua_pushinteger(L, event->type); lua_pushinteger(L, event->code); lua_pushinteger(L, event->value);
    return 3;
}
static int frame_index(lua_State *L)
{
    lua_input_frame_t *frame = luaL_checkudata(L, 1, FRAME_MT);
    const char *key = luaL_checkstring(L, 2);
    if (!strcmp(key, "get")) lua_pushcfunction(L, frame_get);
    else if (!strcmp(key, "count")) lua_pushinteger(L, frame->header.count);
    else if (!strcmp(key, "device_id")) lua_pushinteger(L, frame->header.device_id);
    else if (!strcmp(key, "sequence")) lua_pushinteger(L, frame->header.sequence);
    else if (!strcmp(key, "timestamp_ms")) lua_pushinteger(L, frame->header.timestamp_ms);
    else lua_pushnil(L);
    return 1;
}
static int readonly(lua_State *L) { return luaL_error(L, "input frame is read-only"); }
static int frame_len(lua_State *L)
{
    lua_input_frame_t *frame = luaL_checkudata(L, 1, FRAME_MT);
    lua_pushinteger(L, frame->header.count); return 1;
}

static void close_sub(lua_State *L, lua_input_sub_t *sub)
{
    if (sub->closed) return;
    sub->closed = 1;
    luat_input_service_lock();
    luat_input_service_close(&sub->sub);
    luat_input_service_unlock();
    luat_heap_free(sub->buffer); sub->buffer = NULL;
    if (sub->callback != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, sub->callback);
    sub->callback = LUA_NOREF;
    if (sub->registered) {
        lua_getfield(L, LUA_REGISTRYINDEX, SUBS_KEY);
        lua_pushnil(L); lua_rawseti(L, -2, sub->slot + 1); lua_pop(L, 1);
        sub->registered = 0;
        active_subscriptions--;
        if (!active_subscriptions && retry_timer) {
            luat_rtos_timer_stop(retry_timer); luat_rtos_timer_delete(retry_timer); retry_timer = NULL;
        }
    }
}
static int l_close(lua_State *L)
{
    lua_input_sub_t *sub = luaL_checkudata(L, 1, SUB_MT);
    close_sub(L, sub); return 0;
}
static int l_stats(lua_State *L)
{
    lua_input_sub_t *sub = luaL_checkudata(L, 1, SUB_MT);
    luat_input_service_lock();
    luat_input_subscription_t *s = &sub->sub;
    uint32_t frames = s->frames, overflows = s->overflows, required = s->required_bytes;
    size_t capacity = s->queue.capacity;
    size_t used = s->queue.full ? capacity : s->queue.tail >= s->queue.head ?
        s->queue.tail - s->queue.head : capacity - s->queue.head + s->queue.tail;
    luat_input_service_unlock();
    lua_newtable(L);
    integer(L, "frames", frames); integer(L, "overflows", overflows);
    integer(L, "queue_bytes", capacity); integer(L, "queued_bytes", used);
    integer(L, "required_bytes", required);
    lua_pushboolean(L, sub->closed); lua_setfield(L, -2, "closed");
    return 1;
}

/* Takes one callback payload from the top. The userdata is rooted by dispatch.
 * Callback may query, close itself or create another subscription. */
static void invoke(lua_State *L, lua_input_sub_t *sub, const char *kind, uint32_t id)
{
    if (sub->closed) { lua_pop(L, 1); return; }
    lua_rawgeti(L, LUA_REGISTRYINDEX, sub->callback); lua_insert(L, -2);
    lua_pushstring(L, kind); lua_insert(L, -2);
    if (id) lua_pushinteger(L, id); else lua_pushnil(L);
    lua_insert(L, -2);
    if (lua_pcall(L, 3, 0, 0) != LUA_OK) {
        const char *error = lua_tostring(L, -1);
        LLOGE("callback error: %s", error ? error : "non-string error");
        lua_pop(L, 1);
        close_sub(L, sub); /* A failing consumer cannot flood the GUI task. */
    }
}

static int drain(lua_State *L, lua_input_sub_t *sub)
{
    for (unsigned budget = 0; budget < FRAME_BUDGET && !sub->closed; budget++) {
        int base = lua_gettop(L);
        luat_input_frame_t next;
        luat_input_service_lock();
        int fault = sub->sub.fault;
        uint32_t required = sub->sub.required_bytes;
        int ret = fault ? fault : luat_input_queue_peek(&sub->sub.queue, &next);
        luat_input_service_unlock();
        if (fault) {
            lua_newtable(L);
            string(L, "reason", fault == LUAT_INPUT_ENOSPC ? "frame_too_large" : "resource_error");
            integer(L, "required_bytes", required);
            invoke(L, sub, "overflow", 0);
            close_sub(L, sub);
            return 0;
        }
        if (ret == LUAT_INPUT_EEMPTY) return 0;
        if (ret == LUAT_INPUT_ELOST) {
            lua_input_owned_t *owned = new_owned(L);
            size_t count = 0;
            luat_input_service_lock();
            ret = luat_input_service_recover(&sub->sub, owned->items, LUAT_INPUT_SERVICE_DEVICES, &count);
            luat_input_service_unlock();
            if (ret) { lua_settop(L, base); return 0; } /* Retry on next timer tick. */
            lua_newtable(L); string(L, "reason", "queue_full");
            invoke(L, sub, "overflow", 0);
            for (size_t i = 0; i < count && !sub->closed; i++) {
                push_info(L, owned->items[i], 0);
                lua_pushboolean(L, 1); lua_setfield(L, -2, "resync");
                invoke(L, sub, "attach", owned->items[i]->snapshot.device_id);
            }
            release_owned(owned);
            lua_settop(L, base);
            continue;
        }
        if (ret) return 0;
        /* Lua allocation may run GC, so it occurs outside the service lock.
         * Producers never remove a queued head except on sticky overflow. */
        lua_input_frame_t *frame = lua_newuserdata(L, sizeof(*frame) + (size_t)next.count * sizeof(frame->events[0]));
        memset(frame, 0, sizeof(*frame));
        luaL_setmetatable(L, FRAME_MT);
        luat_input_service_lock();
        ret = luat_input_queue_read(&sub->sub.queue, &frame->header, frame->events, next.count);
        luat_input_service_unlock();
        if (ret) { lua_settop(L, base); continue; }
        uint16_t flags = frame->header.flags;
        uint32_t id = frame->header.device_id;
        if (flags & LUAT_INPUT_FRAME_REMOVE) {
            lua_pop(L, 1); lua_pushnil(L); invoke(L, sub, "remove", id);
        } else if (flags & (LUAT_INPUT_FRAME_ATTACH | LUAT_INPUT_FRAME_RESET)) {
            const luat_input_service_info_t *info = (const void *)frame->events;
            push_info(L, info, 0);
            invoke(L, sub, flags & LUAT_INPUT_FRAME_ATTACH ? "attach" : "reset", id);
        } else invoke(L, sub, "frame", id);
        lua_settop(L, base);
    }
    return !sub->closed; /* Continue a backlog through another bounded message. */
}
static int dispatch(lua_State *L, void *ptr)
{
    (void)ptr;
    __atomic_store_n(&pending, 0, __ATOMIC_RELEASE);
    int base = lua_gettop(L);
    lua_getfield(L, LUA_REGISTRYINDEX, SUBS_KEY);
    if (!lua_istable(L, -1)) { lua_settop(L, base); return 0; }
    int again = 0;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_SUBSCRIPTIONS; i++) {
        lua_rawgeti(L, -1, i + 1);
        lua_input_sub_t *sub = luaL_testudata(L, -1, SUB_MT);
        if (sub && !sub->closed && drain(L, sub)) again = 1;
        lua_pop(L, 1);
    }
    lua_settop(L, base);
    if (again) notify(NULL);
    return 0;
}

/**
@api input.subscribe(filter, callback)
@table filter Optional device instance id, types array and queue_bytes (default 4096).
@function callback function(kind, device_id, data); must not yield.
@return userdata|nil Subscription. Retain it until close(); GC also closes it.
*/
static int l_subscribe(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE); luaL_checktype(L, 2, LUA_TFUNCTION);
    uint32_t id = 0, types = (1U << LUAT_INPUT_EV_KEY) | (1U << LUAT_INPUT_EV_REL) |
        (1U << LUAT_INPUT_EV_ABS) | (1U << LUAT_INPUT_EV_MSC);
    lua_getfield(L, 1, "device");
    if (!lua_isnil(L, -1)) id = check_id(L, -1);
    lua_pop(L, 1);
    lua_getfield(L, 1, "queue_bytes");
    lua_Integer bytes = luaL_optinteger(L, -1, 4096);
    luaL_argcheck(L, bytes >= 256 && bytes <= 65536, 1, "queue_bytes must be 256..65536");
    lua_pop(L, 1);
    lua_getfield(L, 1, "types");
    if (!lua_isnil(L, -1)) {
        luaL_checktype(L, -1, LUA_TTABLE);
        types = 0;
        size_t count = lua_rawlen(L, -1);
        for (size_t i = 1; i <= count; i++) {
            lua_rawgeti(L, -1, i);
            lua_Integer type = luaL_checkinteger(L, -1);
            luaL_argcheck(L, type >= LUAT_INPUT_EV_SYN && type <= LUAT_INPUT_EV_MSC, 1, "invalid event type");
            types |= UINT32_C(1) << type;
            lua_pop(L, 1);
        }
        luaL_argcheck(L, types != 0, 1, "empty event types");
    }
    lua_pop(L, 1);
    lua_input_sub_t *sub = lua_newuserdata(L, sizeof(*sub));
    memset(sub, 0, sizeof(*sub)); sub->callback = LUA_NOREF; sub->slot = -1;
    luaL_setmetatable(L, SUB_MT);
    sub->buffer = luat_heap_malloc((size_t)bytes);
    if (!sub->buffer) return error_result(L, "no_memory");
    lua_pushvalue(L, 2); sub->callback = luaL_ref(L, LUA_REGISTRYINDEX);
    int created_timer = !retry_timer;
    if (created_timer) {
        if (luat_rtos_timer_create(&retry_timer)) { close_sub(L, sub); return error_result(L, "timer_failed"); }
        if (luat_rtos_timer_start(retry_timer, 20, 1, notify, NULL)) {
            luat_rtos_timer_delete(retry_timer); retry_timer = NULL;
            close_sub(L, sub); return error_result(L, "timer_failed");
        }
    }
    luat_input_service_lock();
    int ret = luat_input_service_subscribe(&sub->sub, id, types, sub->buffer, (size_t)bytes, notify, NULL);
    luat_input_service_unlock();
    if (ret) {
        close_sub(L, sub);
        if (created_timer) { luat_rtos_timer_delete(retry_timer); retry_timer = NULL; }
        return error_result(L, ret == LUAT_INPUT_ESTALE ? "not_found" :
            ret == LUAT_INPUT_SERVICE_ENOMEM ? "no_memory" : "subscription_limit_or_queue_too_small");
    }
    sub->slot = (int)sub->sub.slot; sub->registered = 1; active_subscriptions++;
    lua_getfield(L, LUA_REGISTRYINDEX, SUBS_KEY);
    lua_pushvalue(L, -2); lua_rawseti(L, -2, sub->slot + 1); lua_pop(L, 1);
    return 1;
}

#define C(name, value) {name, ROREG_INT(value)}
static const rotable_Reg_t reg_input[] = {
    {"list", ROREG_FUNC(l_list)}, {"info", ROREG_FUNC(l_info)},
    {"state", ROREG_FUNC(l_state)}, {"subscribe", ROREG_FUNC(l_subscribe)},
    C("EV_SYN", LUAT_INPUT_EV_SYN), C("EV_KEY", LUAT_INPUT_EV_KEY),
    C("EV_REL", LUAT_INPUT_EV_REL), C("EV_ABS", LUAT_INPUT_EV_ABS), C("EV_MSC", LUAT_INPUT_EV_MSC),
    C("PRESS", LUAT_INPUT_PRESS), C("RELEASE", LUAT_INPUT_RELEASE), C("REPEAT", LUAT_INPUT_REPEAT),
    C("REL_X", LUAT_INPUT_REL_X), C("REL_Y", LUAT_INPUT_REL_Y), C("REL_WHEEL", LUAT_INPUT_REL_WHEEL), C("REL_HWHEEL", LUAT_INPUT_REL_HWHEEL),
    C("ABS_X", LUAT_INPUT_ABS_X), C("ABS_Y", LUAT_INPUT_ABS_Y), C("ABS_PRESSURE", LUAT_INPUT_ABS_PRESSURE),
    C("ABS_MT_SLOT", LUAT_INPUT_ABS_MT_SLOT), C("ABS_MT_POSITION_X", LUAT_INPUT_ABS_MT_POSITION_X), C("ABS_MT_POSITION_Y", LUAT_INPUT_ABS_MT_POSITION_Y),
    C("ABS_MT_TRACKING_ID", LUAT_INPUT_ABS_MT_TRACKING_ID), C("ABS_MT_PRESSURE", LUAT_INPUT_ABS_MT_PRESSURE),
    C("BTN_LEFT", LUAT_INPUT_BTN_LEFT), C("BTN_RIGHT", LUAT_INPUT_BTN_RIGHT), C("BTN_MIDDLE", LUAT_INPUT_BTN_MIDDLE), C("BTN_TOUCH", LUAT_INPUT_BTN_TOUCH),
    C("KEY_ESC", LUAT_INPUT_KEY_ESC), C("KEY_BACKSPACE", LUAT_INPUT_KEY_BACKSPACE), C("KEY_TAB", LUAT_INPUT_KEY_TAB), C("KEY_ENTER", LUAT_INPUT_KEY_ENTER),
    C("KEY_LEFTCTRL", LUAT_INPUT_KEY_LEFTCTRL), C("KEY_LEFTSHIFT", LUAT_INPUT_KEY_LEFTSHIFT), C("KEY_RIGHTSHIFT", LUAT_INPUT_KEY_RIGHTSHIFT),
    C("KEY_LEFTALT", LUAT_INPUT_KEY_LEFTALT), C("KEY_SPACE", LUAT_INPUT_KEY_SPACE), C("KEY_CAPSLOCK", LUAT_INPUT_KEY_CAPSLOCK),
    C("KEY_RIGHTCTRL", LUAT_INPUT_KEY_RIGHTCTRL), C("KEY_RIGHTALT", LUAT_INPUT_KEY_RIGHTALT),
    C("KEY_HOME", LUAT_INPUT_KEY_HOME), C("KEY_UP", LUAT_INPUT_KEY_UP), C("KEY_PAGEUP", LUAT_INPUT_KEY_PAGEUP), C("KEY_LEFT", LUAT_INPUT_KEY_LEFT),
    C("KEY_RIGHT", LUAT_INPUT_KEY_RIGHT), C("KEY_END", LUAT_INPUT_KEY_END), C("KEY_DOWN", LUAT_INPUT_KEY_DOWN), C("KEY_PAGEDOWN", LUAT_INPUT_KEY_PAGEDOWN), C("KEY_DELETE", LUAT_INPUT_KEY_DELETE),
    C("KEY_A", LUAT_INPUT_KEY_A), C("KEY_B", LUAT_INPUT_KEY_B), C("KEY_C", LUAT_INPUT_KEY_C), C("KEY_D", LUAT_INPUT_KEY_D), C("KEY_E", LUAT_INPUT_KEY_E),
    C("KEY_F", LUAT_INPUT_KEY_F), C("KEY_G", LUAT_INPUT_KEY_G), C("KEY_H", LUAT_INPUT_KEY_H), C("KEY_I", LUAT_INPUT_KEY_I), C("KEY_J", LUAT_INPUT_KEY_J),
    C("KEY_K", LUAT_INPUT_KEY_K), C("KEY_L", LUAT_INPUT_KEY_L), C("KEY_M", LUAT_INPUT_KEY_M), C("KEY_N", LUAT_INPUT_KEY_N), C("KEY_O", LUAT_INPUT_KEY_O),
    C("KEY_P", LUAT_INPUT_KEY_P), C("KEY_Q", LUAT_INPUT_KEY_Q), C("KEY_R", LUAT_INPUT_KEY_R), C("KEY_S", LUAT_INPUT_KEY_S), C("KEY_T", LUAT_INPUT_KEY_T),
    C("KEY_U", LUAT_INPUT_KEY_U), C("KEY_V", LUAT_INPUT_KEY_V), C("KEY_W", LUAT_INPUT_KEY_W), C("KEY_X", LUAT_INPUT_KEY_X), C("KEY_Y", LUAT_INPUT_KEY_Y), C("KEY_Z", LUAT_INPUT_KEY_Z),
    C("PROP_POINTER", LUAT_INPUT_PROP_POINTER), C("PROP_DIRECT", LUAT_INPUT_PROP_DIRECT),
    {NULL, ROREG_INT(0)}
};
#undef C

LUAMOD_API int luaopen_input(lua_State *L)
{
    if (!luat_input_service_is_ready()) return luaL_error(L, "input service not initialized by application startup");
    luaL_newmetatable(L, OWN_MT);
    lua_pushcfunction(L, owned_gc); lua_setfield(L, -2, "__gc"); lua_pop(L, 1);
    luaL_newmetatable(L, FRAME_MT);
    lua_pushcfunction(L, frame_index); lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, readonly); lua_setfield(L, -2, "__newindex");
    lua_pushcfunction(L, frame_len); lua_setfield(L, -2, "__len");
    string(L, "__metatable", FRAME_MT); lua_pop(L, 1);
    luaL_newmetatable(L, SUB_MT);
    lua_pushcfunction(L, l_close); lua_setfield(L, -2, "__gc");
    static const luaL_Reg methods[] = {{"close", l_close}, {"stats", l_stats}, {NULL, NULL}};
    luaL_newlib(L, methods); lua_setfield(L, -2, "__index"); lua_pop(L, 1);
    lua_getfield(L, LUA_REGISTRYINDEX, SUBS_KEY);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1); lua_newtable(L); lua_newtable(L);
        string(L, "__mode", "v"); lua_setmetatable(L, -2);
        lua_pushvalue(L, -1); lua_setfield(L, LUA_REGISTRYINDEX, SUBS_KEY);
    }
    lua_pop(L, 1);
    luat_newlib2(L, reg_input);
    return 1;
}
#endif
