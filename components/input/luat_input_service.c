#include "luat_base.h"
#ifdef LUAT_USE_INPUT_SERVICE
#include "luat_input_service.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include <string.h>
#include <limits.h>

static luat_input_core_t core;
static luat_rtos_mutex_t mutex;
enum { SERVICE_STOPPED, SERVICE_STARTING, SERVICE_READY };
static unsigned init_state;
static luat_input_handle_t devices[LUAT_INPUT_SERVICE_DEVICES];
static luat_input_subscription_t *subscriptions[LUAT_INPUT_SERVICE_SUBSCRIPTIONS];
static luat_input_service_observer_t *observers;

int luat_input_service_observe(luat_input_service_observer_t *o)
{
    if (!o || !o->attach || !o->detach) return LUAT_INPUT_EINVAL;
    if (o->active) return LUAT_INPUT_EBUSY;
    o->next = observers;
    observers = o;
    o->active = 1;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
        if (devices[i].id) o->attach(o->userdata, devices[i]);
    return 0;
}

void luat_input_service_unobserve(luat_input_service_observer_t *o)
{
    if (!o || !o->active) return;
    luat_input_service_observer_t **p = &observers;
    while (*p && *p != o) p = &(*p)->next;
    if (!*p) return;
    *p = o->next;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
        if (devices[i].id) o->detach(o->userdata, devices[i]);
    o->active = 0;
    o->next = NULL;
}

int luat_input_service_init(void)
{
    /* The application startup owns init; never wait for a preempted initializer. */
    unsigned expected = SERVICE_STOPPED;
    if (!__atomic_compare_exchange_n(&init_state, &expected, SERVICE_STARTING, 0,
                                     __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
        return expected == SERVICE_READY ? LUAT_INPUT_OK : LUAT_INPUT_EBUSY;
    luat_rtos_mutex_t created = NULL;
    if (luat_rtos_mutex_create(&created)) {
        __atomic_store_n(&init_state, SERVICE_STOPPED, __ATOMIC_RELEASE);
        return LUAT_INPUT_SERVICE_ENOMEM;
    }
    luat_input_init(&core);
    mutex = created;
    /* Publish only after both the core and mutex are usable. */
    __atomic_store_n(&init_state, SERVICE_READY, __ATOMIC_RELEASE);
    return LUAT_INPUT_OK;
}
int luat_input_service_is_ready(void)
{
    return __atomic_load_n(&init_state, __ATOMIC_ACQUIRE) == SERVICE_READY;
}
void luat_input_service_lock(void) { luat_rtos_mutex_lock(mutex, UINT32_MAX); }
void luat_input_service_unlock(void) { luat_rtos_mutex_unlock(mutex); }
luat_input_core_t *luat_input_service_core(void) { return &core; }

luat_input_service_info_t *luat_input_service_info(uint32_t id)
{
    luat_input_handle_t handle;
    const luat_input_device_desc_t *desc;
    if (luat_input_lookup(&core, id, &handle) || luat_input_get_desc(handle, &desc))
        return NULL;
    const luat_input_caps_t *c = &desc->caps;
    size_t words = luat_input_state_words(c);
    if (words == SIZE_MAX)
        return NULL;
    size_t bytes = sizeof(luat_input_service_info_t) + (c->key_words + words) * sizeof(uint32_t) + ((size_t)c->abs_count + c->mt_count) * sizeof(luat_input_axis_t);
    bytes = (bytes + 7U) & ~(size_t)7U;
    luat_input_service_info_t *info = luat_heap_calloc(1, bytes);
    if (!info)
        return NULL;
    info->bytes = (uint32_t)bytes;
    info->properties = desc->properties;
    info->rel_bits = c->rel_bits;
    info->msc_bits = c->msc_bits;
    info->bus = desc->bus;
    info->vendor = desc->vendor;
    info->product = desc->product;
    info->version = desc->version;
    info->key_words = c->key_words;
    info->abs_count = c->abs_count;
    info->mt_count = c->mt_count;
    info->mt_slots = c->mt_slots;
    if (desc->name)
        strncpy(info->name, desc->name, sizeof(info->name) - 1);
    uint8_t *out = (uint8_t *)info->data;
    if (c->key_words)
        memcpy(out, c->keys, c->key_words * sizeof(uint32_t));
    out += c->key_words * sizeof(uint32_t);
    if (c->abs_count)
        memcpy(out, c->abs, c->abs_count * sizeof(luat_input_axis_t));
    out += c->abs_count * sizeof(luat_input_axis_t);
    if (c->mt_count)
        memcpy(out, c->mt, c->mt_count * sizeof(luat_input_axis_t));
    out += c->mt_count * sizeof(luat_input_axis_t);
    if (luat_input_snapshot(handle, &info->snapshot, (uint32_t *)out, words))
    {
        luat_heap_free(info);
        return NULL;
    }
    return info;
}

static void fail(luat_input_subscription_t *s, int error, size_t required)
{
    s->fault = error;
    s->required_bytes = required > UINT32_MAX ? UINT32_MAX : (uint32_t)required;
    if (s->notify)
        s->notify(s->userdata);
}

static void receive(void *userdata, const luat_input_frame_t *frame,
                    const luat_input_event_t *events)
{
    luat_input_service_route_t *route = userdata;
    luat_input_subscription_t *s = route->owner;
    if (!s->active || s->fault)
        return;
    luat_input_frame_t outgoing = *frame;
    luat_input_service_info_t *info = NULL;
    if (!(frame->flags & LUAT_INPUT_FRAME_REMOVE) &&
        (frame->flags & (LUAT_INPUT_FRAME_ATTACH | LUAT_INPUT_FRAME_RESET)))
    {
        info = luat_input_service_info(frame->device_id);
        if (!info)
        {
            fail(s, LUAT_INPUT_SERVICE_ENOMEM, 0);
            return;
        }
        if (info->bytes / sizeof(*events) > UINT16_MAX)
        {
            fail(s, LUAT_INPUT_ENOSPC, sizeof(outgoing) + info->bytes);
            luat_heap_free(info);
            return;
        }
        outgoing.count = (uint16_t)(info->bytes / sizeof(*events));
        events = (const luat_input_event_t *)info;
    }
    size_t count = outgoing.count;
    if (!outgoing.flags && s->types != UINT32_MAX)
    {
        count = 0;
        for (unsigned i = 0; i < outgoing.count; i++)
            if (events[i].type < 32 && (s->types & (UINT32_C(1) << events[i].type)))
                count++;
        if (!count)
            return;
    }
    size_t required = sizeof(outgoing) + count * sizeof(*events);
    if (required > s->queue.capacity)
    {
        fail(s, LUAT_INPUT_ENOSPC, required);
    }
    else
    {
        int was_lost = s->queue.lost;
        int ret = luat_input_queue_push_types(&s->queue, &outgoing, events, s->types);
        if (!ret)
            __sync_add_and_fetch(&s->frames, 1);
        if (!was_lost && s->queue.lost)
            __sync_add_and_fetch(&s->overflows, 1);
    }
    luat_heap_free(info);
}

static int matches(luat_input_subscription_t *s, luat_input_handle_t h)
{
    if (s->device_id && s->device_id != h.id)
        return 0;
    const luat_input_device_desc_t *d;
    if (luat_input_get_desc(h, &d))
        return 0;
    uint32_t types = (1U << LUAT_INPUT_EV_SYN);
    if (d->caps.key_words)
        types |= 1U << LUAT_INPUT_EV_KEY;
    if (d->caps.rel_bits)
        types |= 1U << LUAT_INPUT_EV_REL;
    if (d->caps.abs_count || d->caps.mt_slots)
        types |= 1U << LUAT_INPUT_EV_ABS;
    if (d->caps.msc_bits)
        types |= 1U << LUAT_INPUT_EV_MSC;
    return !!(types & s->types);
}

static int bind_route(luat_input_subscription_t *s, unsigned i)
{
    if (!devices[i].id || !matches(s, devices[i]))
        return LUAT_INPUT_OK;
    s->routes[i].owner = s;
    int ret = luat_input_bind(devices[i], &s->routes[i].link, receive, &s->routes[i]);
    return ret ? ret : s->fault;
}

int luat_input_service_attach(luat_input_handle_t h)
{
    if (!h.device || h.device->core != &core || h.device->id != h.id)
        return LUAT_INPUT_ESTALE;
    unsigned slot = LUAT_INPUT_SERVICE_DEVICES;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
    {
        if (devices[i].id == h.id)
            return LUAT_INPUT_EBUSY;
        if (!devices[i].id && slot == LUAT_INPUT_SERVICE_DEVICES)
            slot = i;
    }
    if (slot == LUAT_INPUT_SERVICE_DEVICES)
        return LUAT_INPUT_ENOSPC;
    devices[slot] = h;
    for (luat_input_service_observer_t *o = observers; o; o = o->next)
        o->attach(o->userdata, h);
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_SUBSCRIPTIONS; i++)
    {
        luat_input_subscription_t *s = subscriptions[i];
        if (s)
        {
            int ret = bind_route(s, slot);
            if (ret && !s->fault)
                fail(s, ret, 0);
        }
    }
    return LUAT_INPUT_OK;
}

void luat_input_service_detach(luat_input_handle_t h)
{
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
    {
        if (devices[i].id != h.id)
            continue;
        for (luat_input_service_observer_t *o = observers; o; o = o->next)
            o->detach(o->userdata, h);
        for (unsigned j = 0; j < LUAT_INPUT_SERVICE_SUBSCRIPTIONS; j++)
        {
            luat_input_subscription_t *s = subscriptions[j];
            if (s && s->routes[i].link.device)
                luat_input_unbind(&s->routes[i].link);
        }
        memset(&devices[i], 0, sizeof(devices[i]));
        return;
    }
}

size_t luat_input_service_list(uint32_t *ids, size_t capacity)
{
    size_t count = 0;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
    {
        if (!devices[i].id)
            continue;
        if (count < capacity)
            ids[count] = devices[i].id;
        count++;
    }
    return count;
}

int luat_input_service_subscribe(luat_input_subscription_t *s, uint32_t id,
                                 uint32_t types, void *buffer, size_t bytes, void (*notify)(void *), void *userdata)
{
    if (!s || !types || !buffer || bytes < sizeof(luat_input_frame_t))
        return LUAT_INPUT_EINVAL;
    unsigned slot = 0;
    while (slot < LUAT_INPUT_SERVICE_SUBSCRIPTIONS && subscriptions[slot])
        slot++;
    if (slot == LUAT_INPUT_SERVICE_SUBSCRIPTIONS)
        return LUAT_INPUT_ENOSPC;
    if (id)
    {
        int found = 0;
        for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
            if (devices[i].id == id)
                found = 1;
        if (!found)
            return LUAT_INPUT_ESTALE;
    }
    memset(s, 0, sizeof(*s));
    luat_input_queue_ops_t ops = {.notify = notify, .userdata = userdata};
    int ret = luat_input_queue_init(&s->queue, buffer, bytes, &ops);
    if (ret)
        return ret;
    s->device_id = id;
    s->types = types;
    s->slot = slot;
    s->notify = notify;
    s->userdata = userdata;
    s->active = 1;
    subscriptions[slot] = s;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
    {
        ret = bind_route(s, i);
        if (ret)
        {
            luat_input_service_close(s);
            return ret;
        }
    }
    return LUAT_INPUT_OK;
}

void luat_input_service_close(luat_input_subscription_t *s)
{
    if (!s || !s->active)
        return;
    s->active = 0;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
        if (s->routes[i].link.device)
            luat_input_unbind(&s->routes[i].link);
    subscriptions[s->slot] = NULL;
    luat_input_queue_reset(&s->queue);
}

int luat_input_service_recover(luat_input_subscription_t *s,
                               luat_input_service_info_t **infos, size_t capacity, size_t *count)
{
    if (!s || !s->active || !infos || !count || capacity < LUAT_INPUT_SERVICE_DEVICES)
        return LUAT_INPUT_EINVAL;
    *count = 0;
    if (s->fault)
        return s->fault;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++)
    {
        if (!s->routes[i].link.device)
            continue;
        infos[*count] = luat_input_service_info(devices[i].id);
        if (!infos[*count])
        {
            for (size_t j = 0; j < *count; j++)
            {
                luat_heap_free(infos[j]);
                infos[j] = NULL;
            }
            *count = 0;
            return LUAT_INPUT_SERVICE_ENOMEM;
        }
        (*count)++;
    }
    /* No producer can run under the service lock: these snapshots and reset
     * form one boundary. Future queued frames are strictly after this baseline. */
    luat_input_queue_reset(&s->queue);
    return LUAT_INPUT_OK;
}
#endif
