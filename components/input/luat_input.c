#include "luat_input.h"

#ifdef LUAT_USE_INPUT
#include <string.h>
#ifdef _MSC_VER
#include <intrin.h>
#endif

/* Counters can be touched by serialized producer/configuration tasks. Atomics
 * do not replace the external serialization required for the rest of the core. */
static uint32_t increment(uint32_t *counter)
{
#ifdef _MSC_VER
    return (uint32_t)_InterlockedIncrement((volatile long *)counter);
#else
    return __sync_add_and_fetch(counter, UINT32_C(1));
#endif
}

_Static_assert(sizeof(luat_input_event_t) == 8, "input event ABI");
_Static_assert(sizeof(luat_input_frame_t) == 16, "input frame ABI");

static int is_mt(uint16_t code)
{
    return code >= 0x30 && code <= 0x3f;
}

static int axis_index(const luat_input_axis_t *axes, uint16_t count, uint16_t code)
{
    unsigned lo = 0, hi = count;
    while (lo < hi) {
        unsigned mid = lo + (hi - lo) / 2;
        if (axes[mid].code < code) lo = mid + 1;
        else hi = mid;
    }
    return lo < count && axes[lo].code == code ? (int)lo : -1;
}

static int valid_axes(const luat_input_axis_t *axes, uint16_t count, int mt)
{
    if (count && !axes) return 0;
    for (unsigned i = 0; i < count; i++) {
        const luat_input_axis_t *a = axes + i;
        if (a->code == LUAT_INPUT_ABS_MT_SLOT || is_mt(a->code) != mt ||
            (i && axes[i - 1].code >= a->code) || a->minimum > a->maximum ||
            a->initial < a->minimum || a->initial > a->maximum) return 0;
        if (a->code == LUAT_INPUT_ABS_MT_TRACKING_ID &&
            (a->minimum != -1 || a->initial != -1 || a->maximum < 0)) return 0;
    }
    return 1;
}

size_t luat_input_state_words(const luat_input_caps_t *caps)
{
    if (!caps || caps->key_words > LUAT_INPUT_KEY_WORDS_MAX ||
        (caps->key_words && !caps->keys) || caps->mt_slots > LUAT_INPUT_MT_SLOTS_MAX ||
        (!!caps->mt_count != !!caps->mt_slots) ||
        !valid_axes(caps->abs, caps->abs_count, 0) ||
        !valid_axes(caps->mt, caps->mt_count, 1)) return SIZE_MAX;
    if (caps->mt_count && axis_index(caps->mt, caps->mt_count,
                                    LUAT_INPUT_ABS_MT_TRACKING_ID) < 0) return SIZE_MAX;
    return (size_t)caps->key_words + caps->abs_count + (size_t)caps->mt_count * caps->mt_slots;
}

void luat_input_init(luat_input_core_t *core)
{
    if (!core) return;
    memset(core, 0, sizeof(*core));
    core->next_id = 1;
}

static int live(luat_input_handle_t handle)
{
    return handle.device && handle.id && handle.device->core && handle.device->id == handle.id;
}

static int key_supported(const luat_input_caps_t *caps, uint16_t code)
{
    return code / 32U < caps->key_words && (caps->keys[code / 32U] & (UINT32_C(1) << (code % 32U)));
}

static size_t word_count(const luat_input_caps_t *caps)
{
    return (size_t)caps->key_words + caps->abs_count + (size_t)caps->mt_count * caps->mt_slots;
}

static void reset_state(luat_input_device_t *dev)
{
    const luat_input_caps_t *c = &dev->desc->caps;
    if (c->key_words) memset(dev->state, 0, c->key_words * sizeof(uint32_t));
    for (unsigned i = 0; i < c->abs_count; i++) dev->state[c->key_words + i] = (uint32_t)c->abs[i].initial;
    for (unsigned s = 0; s < c->mt_slots; s++) {
        for (unsigned i = 0; i < c->mt_count; i++) {
            dev->state[c->key_words + c->abs_count + (size_t)s * c->mt_count + i] = (uint32_t)c->mt[i].initial;
        }
    }
    dev->mt_slot = 0;
}

static void emit(luat_input_device_t *dev, const luat_input_event_t *events,
                 uint16_t count, uint16_t flags)
{
    const luat_input_frame_t frame = {dev->id, dev->sequence, dev->timestamp_ms, count, flags};
    dev->core->dispatching = 1;
    for (luat_input_link_t *link = dev->links; link; link = link->next) {
        link->receive(link->userdata, &frame, events);
    }
    dev->core->dispatching = 0;
}

int luat_input_register(luat_input_core_t *core, luat_input_device_t *dev,
    const luat_input_device_desc_t *desc, uint32_t *state, size_t words,
    luat_input_handle_t *handle)
{
    if (!core || !dev || !desc || !handle) return LUAT_INPUT_EINVAL;
    if (core->dispatching || dev->core) return LUAT_INPUT_EBUSY;
    size_t need = luat_input_state_words(&desc->caps);
    if (need == SIZE_MAX || (need && !state)) return LUAT_INPUT_EINVAL;
    if (words < need || !core->next_id) return LUAT_INPUT_ENOSPC;
    memset(dev, 0, sizeof(*dev));
    dev->core = core;
    dev->desc = desc;
    dev->state = state;
    dev->id = core->next_id;
    increment(&core->next_id);
    reset_state(dev);
    dev->next = core->devices;
    core->devices = dev;
    handle->device = dev;
    handle->id = dev->id;
    return LUAT_INPUT_OK;
}

int luat_input_bind(luat_input_handle_t handle, luat_input_link_t *link,
    luat_input_receive_t receive, void *userdata)
{
    if (!live(handle)) return LUAT_INPUT_ESTALE;
    if (!link || !receive) return LUAT_INPUT_EINVAL;
    luat_input_device_t *dev = handle.device;
    if (dev->core->dispatching || link->device) return LUAT_INPUT_EBUSY;
    for (luat_input_link_t *p = dev->links; p; p = p->next) {
        if (p->receive == receive && p->userdata == userdata) return LUAT_INPUT_EBUSY;
    }
    link->device = dev;
    link->receive = receive;
    link->userdata = userdata;
    link->next = dev->links;
    dev->links = link;
    const luat_input_frame_t frame = {dev->id, dev->sequence, dev->timestamp_ms, 0, LUAT_INPUT_FRAME_ATTACH};
    dev->core->dispatching = 1;
    receive(userdata, &frame, NULL);
    dev->core->dispatching = 0;
    return LUAT_INPUT_OK;
}

int luat_input_unbind(luat_input_link_t *link)
{
    if (!link || !link->device) return LUAT_INPUT_EINVAL;
    luat_input_device_t *dev = link->device;
    if (dev->core->dispatching) return LUAT_INPUT_EBUSY;
    luat_input_link_t **p = &dev->links;
    while (*p && *p != link) p = &(*p)->next;
    if (!*p) return LUAT_INPUT_EINVAL;
    *p = link->next;
    increment(&dev->sequence); /* A post-snapshot REMOVE must sort after it. */
    const luat_input_frame_t frame = {dev->id, dev->sequence, dev->timestamp_ms, 0, LUAT_INPUT_FRAME_REMOVE};
    dev->core->dispatching = 1;
    link->receive(link->userdata, &frame, NULL);
    dev->core->dispatching = 0;
    memset(link, 0, sizeof(*link));
    return LUAT_INPUT_OK;
}

/* First pass validates every value, including all slot selectors, without mutation. */
static int validate(const luat_input_device_t *dev, const luat_input_event_t *events, uint16_t count)
{
    const luat_input_caps_t *c = &dev->desc->caps;
    for (unsigned i = 0; i < count; i++) {
        const luat_input_event_t *e = events + i;
        int index;
        const luat_input_axis_t *axis;
        switch (e->type) {
        case LUAT_INPUT_EV_SYN:
            if (e->code != LUAT_INPUT_SYN_REPORT || e->value || i + 1 != count) return LUAT_INPUT_EINVAL;
            break;
        case LUAT_INPUT_EV_KEY:
            if (!key_supported(c, e->code)) return LUAT_INPUT_ENOTSUP;
            if (e->value < 0 || e->value > LUAT_INPUT_REPEAT) return LUAT_INPUT_EINVAL;
            break;
        case LUAT_INPUT_EV_REL:
        case LUAT_INPUT_EV_MSC:
            if (e->code >= 32 || !((e->type == LUAT_INPUT_EV_REL ? c->rel_bits : c->msc_bits) &
                                  (UINT32_C(1) << e->code))) return LUAT_INPUT_ENOTSUP;
            break;
        case LUAT_INPUT_EV_ABS:
            if (e->code == LUAT_INPUT_ABS_MT_SLOT) {
                if (e->value < 0 || e->value >= c->mt_slots) return LUAT_INPUT_EINVAL;
                break;
            }
            index = is_mt(e->code) ? axis_index(c->mt, c->mt_count, e->code) : axis_index(c->abs, c->abs_count, e->code);
            if (index < 0) return LUAT_INPUT_ENOTSUP;
            axis = (is_mt(e->code) ? c->mt : c->abs) + index;
            if (e->value < axis->minimum || e->value > axis->maximum) return LUAT_INPUT_EINVAL;
            break;
        default:
            return LUAT_INPUT_ENOTSUP;
        }
    }
    return LUAT_INPUT_OK;
}

int luat_input_submit(luat_input_handle_t handle, uint32_t timestamp_ms,
    const luat_input_event_t *events, uint16_t count)
{
    if (!live(handle)) return LUAT_INPUT_ESTALE;
    luat_input_device_t *dev = handle.device;
    if (dev->core->dispatching) return LUAT_INPUT_EBUSY;
    if (count && !events) return LUAT_INPUT_EINVAL;
    int ret = validate(dev, events, count);
    if (ret) return ret;
    const luat_input_caps_t *c = &dev->desc->caps;
    for (unsigned i = 0; i < count; i++) {
        const luat_input_event_t *e = events + i;
        if (e->type == LUAT_INPUT_EV_KEY && e->value != LUAT_INPUT_REPEAT) {
            uint32_t bit = UINT32_C(1) << (e->code % 32U);
            if (e->value) dev->state[e->code / 32U] |= bit;
            else dev->state[e->code / 32U] &= ~bit;
        } else if (e->type == LUAT_INPUT_EV_ABS) {
            if (e->code == LUAT_INPUT_ABS_MT_SLOT) dev->mt_slot = (uint16_t)e->value;
            else {
                size_t offset = c->key_words;
                if (is_mt(e->code)) offset += c->abs_count + (size_t)dev->mt_slot * c->mt_count + axis_index(c->mt, c->mt_count, e->code);
                else offset += axis_index(c->abs, c->abs_count, e->code);
                dev->state[offset] = (uint32_t)e->value;
            }
        }
    }
    dev->timestamp_ms = timestamp_ms;
    increment(&dev->sequence);
    emit(dev, events, count, 0);
    return LUAT_INPUT_OK;
}

int luat_input_reset(luat_input_handle_t handle, uint32_t timestamp_ms)
{
    if (!live(handle)) return LUAT_INPUT_ESTALE;
    luat_input_device_t *dev = handle.device;
    if (dev->core->dispatching) return LUAT_INPUT_EBUSY;
    reset_state(dev);
    dev->timestamp_ms = timestamp_ms;
    increment(&dev->sequence);
    emit(dev, NULL, 0, LUAT_INPUT_FRAME_RESET);
    return LUAT_INPUT_OK;
}

int luat_input_unregister(luat_input_handle_t handle, uint32_t timestamp_ms)
{
    if (!live(handle)) return LUAT_INPUT_ESTALE;
    luat_input_device_t *dev = handle.device;
    if (dev->core->dispatching) return LUAT_INPUT_EBUSY;
    luat_input_device_t **p = &dev->core->devices;
    while (*p && *p != dev) p = &(*p)->next;
    if (!*p) return LUAT_INPUT_EINVAL;
    *p = dev->next;
    reset_state(dev);
    dev->timestamp_ms = timestamp_ms;
    increment(&dev->sequence);
    emit(dev, NULL, 0, LUAT_INPUT_FRAME_REMOVE | LUAT_INPUT_FRAME_RESET);
    while (dev->links) {
        luat_input_link_t *link = dev->links;
        dev->links = link->next;
        memset(link, 0, sizeof(*link));
    }
    memset(dev, 0, sizeof(*dev));
    return LUAT_INPUT_OK;
}

int luat_input_get_value(luat_input_handle_t handle, uint16_t type,
    uint16_t code, uint16_t slot, int32_t *value)
{
    if (!live(handle)) return LUAT_INPUT_ESTALE;
    if (!value) return LUAT_INPUT_EINVAL;
    const luat_input_device_t *dev = handle.device;
    const luat_input_caps_t *c = &dev->desc->caps;
    if (type == LUAT_INPUT_EV_KEY && key_supported(c, code)) {
        *value = !!(dev->state[code / 32U] & (UINT32_C(1) << (code % 32U)));
        return LUAT_INPUT_OK;
    }
    if (type != LUAT_INPUT_EV_ABS) return LUAT_INPUT_ENOTSUP;
    if (code == LUAT_INPUT_ABS_MT_SLOT && c->mt_slots) {
        *value = dev->mt_slot;
        return LUAT_INPUT_OK;
    }
    size_t offset = c->key_words;
    int index;
    if (is_mt(code)) {
        if (slot >= c->mt_slots) return LUAT_INPUT_EINVAL;
        index = axis_index(c->mt, c->mt_count, code);
        offset += c->abs_count + (size_t)slot * c->mt_count;
    } else index = axis_index(c->abs, c->abs_count, code);
    if (index < 0) return LUAT_INPUT_ENOTSUP;
    memcpy(value, &dev->state[offset + index], sizeof(*value));
    return LUAT_INPUT_OK;
}

int luat_input_snapshot(luat_input_handle_t handle, luat_input_snapshot_t *snapshot,
    uint32_t *state, size_t words)
{
    if (!live(handle)) return LUAT_INPUT_ESTALE;
    const luat_input_device_t *dev = handle.device;
    size_t need = word_count(&dev->desc->caps);
    if (!snapshot || (need && !state)) return LUAT_INPUT_EINVAL;
    if (words < need) return LUAT_INPUT_ENOSPC;
    if (need) memmove(state, dev->state, need * sizeof(*state));
    *snapshot = (luat_input_snapshot_t){dev->id, dev->sequence, dev->timestamp_ms, dev->mt_slot, 0};
    return LUAT_INPUT_OK;
}

int luat_input_enumerate(luat_input_core_t *core, luat_input_handle_t *handles,
    size_t capacity, size_t *count)
{
    if (!core || !count || (capacity && !handles)) return LUAT_INPUT_EINVAL;
    size_t n = 0;
    for (luat_input_device_t *dev = core->devices; dev; dev = dev->next) {
        if (n < capacity) handles[n] = (luat_input_handle_t){dev, dev->id};
        n++;
    }
    *count = n;
    return n > capacity ? LUAT_INPUT_ENOSPC : LUAT_INPUT_OK;
}

int luat_input_lookup(luat_input_core_t *core, uint32_t device_id,
    luat_input_handle_t *handle)
{
    if (!core || !device_id || !handle) return LUAT_INPUT_EINVAL;
    for (luat_input_device_t *dev = core->devices; dev; dev = dev->next) {
        if (dev->id != device_id) continue;
        *handle = (luat_input_handle_t){dev, dev->id};
        return LUAT_INPUT_OK;
    }
    memset(handle, 0, sizeof(*handle));
    return LUAT_INPUT_ESTALE;
}

int luat_input_get_desc(luat_input_handle_t handle,
    const luat_input_device_desc_t **desc)
{
    if (!live(handle)) return LUAT_INPUT_ESTALE;
    if (!desc) return LUAT_INPUT_EINVAL;
    *desc = handle.device->desc;
    return LUAT_INPUT_OK;
}

int luat_input_get_capability(luat_input_handle_t handle, uint16_t type,
    uint16_t code, const luat_input_axis_t **axis)
{
    if (!live(handle)) return LUAT_INPUT_ESTALE;
    if (axis) *axis = NULL;
    const luat_input_caps_t *caps = &handle.device->desc->caps;
    int index;
    switch (type) {
    case LUAT_INPUT_EV_KEY:
        return key_supported(caps, code) ? LUAT_INPUT_OK : LUAT_INPUT_ENOTSUP;
    case LUAT_INPUT_EV_REL:
    case LUAT_INPUT_EV_MSC:
        if (code >= 32) return LUAT_INPUT_ENOTSUP;
        return ((type == LUAT_INPUT_EV_REL ? caps->rel_bits : caps->msc_bits) &
                (UINT32_C(1) << code)) ? LUAT_INPUT_OK : LUAT_INPUT_ENOTSUP;
    case LUAT_INPUT_EV_ABS:
        if (code == LUAT_INPUT_ABS_MT_SLOT)
            return caps->mt_slots ? LUAT_INPUT_OK : LUAT_INPUT_ENOTSUP;
        index = is_mt(code) ? axis_index(caps->mt, caps->mt_count, code) :
                              axis_index(caps->abs, caps->abs_count, code);
        if (index < 0) return LUAT_INPUT_ENOTSUP;
        if (axis) *axis = (is_mt(code) ? caps->mt : caps->abs) + index;
        return LUAT_INPUT_OK;
    case LUAT_INPUT_EV_SYN:
        return code == LUAT_INPUT_SYN_REPORT ? LUAT_INPUT_OK : LUAT_INPUT_ENOTSUP;
    default:
        return LUAT_INPUT_ENOTSUP;
    }
}

int luat_input_bind_id(luat_input_core_t *core, uint32_t device_id,
    luat_input_link_t *link, luat_input_receive_t receive, void *userdata,
    luat_input_handle_t *handle)
{
    luat_input_handle_t resolved = {0};
    int ret = luat_input_lookup(core, device_id, &resolved);
    if (ret) return ret;
    ret = luat_input_bind(resolved, link, receive, userdata);
    if (!ret && handle) *handle = resolved;
    return ret;
}

int luat_input_enumerate_bound(luat_input_core_t *core,
    luat_input_receive_t receive, void *userdata, luat_input_handle_t *handles,
    size_t capacity, size_t *count)
{
    if (!core || !receive || !count || (capacity && !handles)) return LUAT_INPUT_EINVAL;
    size_t n = 0;
    for (luat_input_device_t *dev = core->devices; dev; dev = dev->next) {
        for (luat_input_link_t *link = dev->links; link; link = link->next) {
            if (link->receive != receive || link->userdata != userdata) continue;
            if (n < capacity) handles[n] = (luat_input_handle_t){dev, dev->id};
            n++;
            break;
        }
    }
    *count = n;
    return n > capacity ? LUAT_INPUT_ENOSPC : LUAT_INPUT_OK;
}
#endif
