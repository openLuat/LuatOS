#include "luat_input.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <sched.h>
#endif

static const uint32_t keys[9] = {[0] = 1U << 30, [1] = 1U << 10, [8] = 7U << 16};
static const luat_input_axis_t abs_axes[] = {{0, 0, 0, 799, 0}, {1, 0, 0, 479, 0}};
static const luat_input_axis_t mt_axes[] = {
    {0x35, 0, 0, 799, 0}, {0x36, 0, 0, 479, 0}, {0x39, 0, -1, 65535, -1}
};
static const luat_input_device_desc_t desc = {
    .name = "test composite",
    .caps = {.keys = keys, .abs = abs_axes, .mt = mt_axes, .rel_bits = 0x103,
             .msc_bits = 1, .key_words = 9, .abs_count = 2, .mt_count = 3, .mt_slots = 2}
};

typedef struct {
    luat_input_handle_t handle;
    luat_input_link_t *link;
    unsigned calls;
    luat_input_frame_t last;
    luat_input_event_t events[16];
    const luat_input_event_t *borrowed;
    int check_reentry;
} observer_t;

static void observe(void *userdata, const luat_input_frame_t *frame, const luat_input_event_t *events)
{
    observer_t *o = userdata;
    o->calls++;
    o->last = *frame;
    o->borrowed = events;
    assert(frame->count <= 16);
    if (frame->count) memcpy(o->events, events, frame->count * sizeof(*events));
    if (o->check_reentry) {
        int32_t value;
        assert(luat_input_get_value(o->handle, LUAT_INPUT_EV_KEY, 30, 0, &value) == 0);
        assert(luat_input_submit(o->handle, 0, NULL, 0) == LUAT_INPUT_EBUSY);
        assert(luat_input_unregister(o->handle, 0) == LUAT_INPUT_EBUSY);
        assert(luat_input_unbind(o->link) == LUAT_INPUT_EBUSY);
    }
}

static void test_core(void)
{
    luat_input_core_t core;
    luat_input_device_t device = {0};
    luat_input_link_t link = {0};
    luat_input_handle_t h;
    uint32_t state[17], before[17], snapshot[17];
    luat_input_init(&core);
    assert(luat_input_state_words(&desc.caps) == 17);
    assert(luat_input_register(&core, &device, &desc, state, 16, &h) == LUAT_INPUT_ENOSPC);
    assert(!core.devices && core.next_id == 1);
    assert(luat_input_register(&core, &device, &desc, state, 17, &h) == 0);
    observer_t o = {.handle = h, .link = &link, .check_reentry = 1};
    assert(luat_input_bind(h, &link, observe, &o) == 0);
    assert(o.calls == 1 && o.last.flags == LUAT_INPUT_FRAME_ATTACH);
    luat_input_link_t duplicate = {0};
    assert(luat_input_bind(h, &duplicate, observe, &o) == LUAT_INPUT_EBUSY && !duplicate.device);

    const luat_input_event_t input[] = {
        {1, 30, 1}, {1, 42, 1}, {2, 0, -123}, {2, 8, INT32_MIN},
        {3, 0x2f, 0}, {3, 0x39, 42}, {3, 0x35, 100},
        {3, 0x2f, 1}, {3, 0x39, 43}, {3, 0x35, 300}, {3, 0x36, 200}, {0, 0, 0}
    };
    assert(luat_input_submit(h, 99, input, 12) == 0);
    assert(o.calls == 2 && o.borrowed == input && o.last.sequence == 1 && o.last.timestamp_ms == 99);
    assert(!memcmp(input, o.events, sizeof(input)));
    int32_t value;
    assert(luat_input_get_value(h, 1, 30, 0, &value) == 0 && value == 1);
    assert(luat_input_get_value(h, 3, 0x35, 0, &value) == 0 && value == 100);
    assert(luat_input_get_value(h, 3, 0x35, 1, &value) == 0 && value == 300);
    assert(luat_input_get_value(h, 3, 0x39, 1, &value) == 0 && value == 43);
    assert(luat_input_get_value(h, 2, 0, 0, &value) == LUAT_INPUT_ENOTSUP);
    assert(luat_input_get_value(h, 3, 0x35, 2, &value) == LUAT_INPUT_EINVAL);

    /* Invalid tail must not apply a valid key release at the start of a frame. */
    memcpy(before, state, sizeof(state));
    const luat_input_event_t bad[] = {{1, 30, 0}, {3, 0x2f, 2}};
    assert(luat_input_submit(h, 100, bad, 2) == LUAT_INPUT_EINVAL);
    assert(!memcmp(before, state, sizeof(state)) && device.sequence == 1 && device.mt_slot == 1 && o.calls == 2);
    const luat_input_event_t invalid[] = {
        {1, 31, 1}, {1, 30, 3}, {3, 0, 800}, {3, 0x2f, -1},
        {2, 32, 0}, {2, 3, 0}, {99, 0, 0}, {0, 3, 0}, {4, 1, 0}
    };
    for (unsigned i = 0; i < sizeof(invalid)/sizeof(invalid[0]); i++) {
        assert(luat_input_submit(h, 100, invalid + i, 1) < 0);
        assert(!memcmp(before, state, sizeof(state)) && device.sequence == 1);
    }
    const luat_input_event_t syn_first[] = {{0, 0, 0}, {1, 30, 0}};
    assert(luat_input_submit(h, 100, syn_first, 2) == LUAT_INPUT_EINVAL);
    assert(luat_input_submit(h, 100, NULL, 1) == LUAT_INPUT_EINVAL);

    luat_input_snapshot_t snap;
    assert(luat_input_snapshot(h, &snap, snapshot, 16) == LUAT_INPUT_ENOSPC);
    assert(luat_input_snapshot(h, &snap, snapshot, 17) == 0);
    assert(snap.sequence == 1 && snap.mt_slot == 1 && !memcmp(snapshot, state, sizeof(state)));
    const luat_input_event_t repeat[] = {{1, 30, 2}, {3, 0x39, -1}};
    assert(luat_input_submit(h, 100, repeat, 2) == 0);
    assert(luat_input_get_value(h, 1, 30, 0, &value) == 0 && value == 1);
    assert(luat_input_get_value(h, 3, 0x39, 1, &value) == 0 && value == -1);
    assert(luat_input_reset(h, 101) == 0);
    assert(o.last.flags == LUAT_INPUT_FRAME_RESET);
    assert(luat_input_get_value(h, 1, 30, 0, &value) == 0 && value == 0);
    assert(luat_input_get_value(h, 3, 0x39, 0, &value) == 0 && value == -1);

    device.sequence = UINT32_MAX; /* Exercise documented sequence wrap. */
    assert(luat_input_submit(h, UINT32_MAX, NULL, 0) == 0 && o.last.sequence == 0);
    assert(luat_input_sequence_after(0, UINT32_MAX));
    assert(!luat_input_sequence_after(UINT32_MAX, 0));
    size_t count;
    luat_input_handle_t list[1];
    assert(luat_input_enumerate(&core, NULL, 0, &count) == LUAT_INPUT_ENOSPC && count == 1);
    assert(luat_input_enumerate(&core, list, 1, &count) == 0 && list[0].id == h.id);
    luat_input_handle_t found = {0};
    const luat_input_device_desc_t *found_desc = NULL;
    const luat_input_axis_t *axis = NULL;
    assert(!luat_input_lookup(&core, h.id, &found) && found.id == h.id);
    assert(!luat_input_get_desc(found, &found_desc) && found_desc == &desc);
    assert(!luat_input_get_capability(found, LUAT_INPUT_EV_KEY, 30, &axis) && !axis);
    assert(!luat_input_get_capability(found, LUAT_INPUT_EV_REL, LUAT_INPUT_REL_X, &axis) && !axis);
    assert(!luat_input_get_capability(found, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_X, &axis));
    assert(axis == &abs_axes[0] && axis->minimum == 0 && axis->maximum == 799);
    assert(!luat_input_get_capability(found, LUAT_INPUT_EV_ABS, LUAT_INPUT_ABS_MT_SLOT, &axis) && !axis);
    assert(luat_input_get_capability(found, LUAT_INPUT_EV_KEY, 31, NULL) == LUAT_INPUT_ENOTSUP);
    assert(luat_input_get_capability(found, 0xffff, 0, NULL) == LUAT_INPUT_ENOTSUP);
    assert(luat_input_lookup(&core, 0, &found) == LUAT_INPUT_EINVAL);
    assert(luat_input_lookup(&core, h.id + 1, &found) == LUAT_INPUT_ESTALE && !found.device);
    uint32_t prior_sequence = device.sequence;
    assert(luat_input_unbind(&link) == 0 && o.last.flags == LUAT_INPUT_FRAME_REMOVE);
    assert(luat_input_sequence_after(o.last.sequence, prior_sequence));
    assert(!link.device);
    assert(luat_input_bind(h, &link, observe, &o) == 0);
    assert(luat_input_unregister(h, 102) == 0);
    assert(o.last.flags == (LUAT_INPUT_FRAME_REMOVE | LUAT_INPUT_FRAME_RESET));
    assert(!link.device && !core.devices && !device.core);
    assert(luat_input_get_desc(h, &found_desc) == LUAT_INPUT_ESTALE);
    assert(luat_input_submit(h, 0, NULL, 0) == LUAT_INPUT_ESTALE);
    luat_input_handle_t fresh;
    assert(luat_input_register(&core, &device, &desc, state, 17, &fresh) == 0);
    assert(fresh.id != h.id && luat_input_reset(h, 0) == LUAT_INPUT_ESTALE);
    assert(luat_input_unregister(fresh, 0) == 0);
    core.next_id = UINT32_MAX;
    assert(luat_input_register(&core, &device, &desc, state, 17, &fresh) == 0 && fresh.id == UINT32_MAX);
    assert(luat_input_unregister(fresh, 0) == 0);
    assert(luat_input_register(&core, &device, &desc, state, 17, &fresh) == LUAT_INPUT_ENOSPC);
}

static void test_caps(void)
{
    luat_input_caps_t c = desc.caps;
    c.keys = NULL;
    assert(luat_input_state_words(&c) == SIZE_MAX);
    c = desc.caps; c.mt_slots = 0;
    assert(luat_input_state_words(&c) == SIZE_MAX);
    c = desc.caps; c.mt_count = 2;
    assert(luat_input_state_words(&c) == SIZE_MAX);
    luat_input_axis_t axes[2] = {{1, 0, 0, 10, 0}, {0, 0, 0, 10, 0}};
    c = desc.caps; c.abs = axes;
    assert(luat_input_state_words(&c) == SIZE_MAX);
    axes[1].code = 1;
    assert(luat_input_state_words(&c) == SIZE_MAX);
    axes[1].code = 2; axes[1].initial = 11;
    assert(luat_input_state_words(&c) == SIZE_MAX);
    c = (luat_input_caps_t){.rel_bits = 3};
    assert(luat_input_state_words(&c) == 0);
    luat_input_core_t core;
    luat_input_device_t device = {0};
    luat_input_handle_t h;
    luat_input_device_desc_t d = {.caps = c};
    luat_input_init(&core);
    assert(luat_input_register(&core, &device, &d, NULL, 0, &h) == 0);
    assert(luat_input_reset(h, 0) == 0);
    assert(luat_input_unregister(h, 0) == 0);
}

static void test_bind_id(void)
{
    luat_input_core_t core;
    luat_input_device_t device = {0};
    luat_input_link_t link = {0}, missing = {0};
    luat_input_handle_t h = {0}, bound = {0};
    uint32_t state[17];
    observer_t o = {0};
    luat_input_init(&core);
    assert(!luat_input_register(&core, &device, &desc, state, 17, &h));
    assert(!luat_input_bind_id(&core, h.id, &link, observe, &o, &bound));
    assert(bound.id == h.id && o.calls == 1 && o.last.flags == LUAT_INPUT_FRAME_ATTACH);
    assert(luat_input_bind_id(&core, h.id + 1, &missing, observe, &o, NULL) == LUAT_INPUT_ESTALE);
    assert(!missing.device);
    assert(!luat_input_unregister(h, 0));
}

typedef struct { int depth; int wakes; } lock_check_t;
static uintptr_t check_lock(void *p) { lock_check_t *c = p; assert(c->depth++ == 0); return 123; }
static void check_unlock(void *p, uintptr_t t) { lock_check_t *c = p; assert(t == 123 && --c->depth == 0); }
static void check_notify(void *p) { lock_check_t *c = p; assert(!c->depth); c->wakes++; }

static void test_queue(void)
{
    uint8_t storage[91]; /* Force headers and payloads to wrap at unaligned boundaries. */
    luat_input_queue_t q;
    lock_check_t check = {0};
    luat_input_queue_ops_t ops = {check_lock, check_unlock, check_notify, &check};
    assert(luat_input_queue_init(&q, storage, sizeof(storage), &ops) == 0);
    luat_input_event_t source[2] = {{2, 0, 123}, {2, 1, -456}}, out[2];
    luat_input_frame_t f = {1, 0, 0, 2, 0}, got;
    for (unsigned i = 0; i < 1000; i++) {
        f.sequence = i;
        assert(luat_input_queue_push(&q, &f, source) == 0);
        source[0].value = 999;
        assert(luat_input_queue_read(&q, &got, out, 1) == LUAT_INPUT_ENOSPC && got.count == 2);
        assert(luat_input_queue_read(&q, &got, out, 2) == 0 && got.sequence == i);
        assert(out[0].value == 123 && out[1].value == -456);
        source[0].value = 123;
    }
    assert(luat_input_queue_read(&q, &got, out, 2) == LUAT_INPUT_EEMPTY);
    assert(luat_input_queue_push(&q, &f, source) == 0);
    assert(luat_input_queue_push(&q, &f, source) == 0);
    int wakes = check.wakes;
    assert(luat_input_queue_push(&q, &f, source) == LUAT_INPUT_ELOST);
    assert(check.wakes == wakes + 1);
    assert(luat_input_queue_read(&q, &got, out, 2) == LUAT_INPUT_ELOST);
    assert(luat_input_queue_push(&q, &f, source) == LUAT_INPUT_ELOST && check.wakes == wakes + 1);
    assert(luat_input_queue_reset(&q) == 0);
    assert(luat_input_queue_push(&q, &f, source) == 0);
    assert(luat_input_queue_read(&q, &got, out, 2) == 0);
    /* A new overflow after reset/during snapshot recovery must stay visible. */
    assert(luat_input_queue_push(&q, &f, source) == 0);
    assert(luat_input_queue_push(&q, &f, source) == 0);
    assert(luat_input_queue_push(&q, &f, source) == LUAT_INPUT_ELOST);
    assert(luat_input_queue_reset(&q) == 0);
    assert(luat_input_queue_push(&q, &f, source) == 0);
    assert(luat_input_queue_push(&q, &f, source) == 0);
    assert(luat_input_queue_push(&q, &f, source) == LUAT_INPUT_ELOST);
    assert(luat_input_queue_read(&q, &got, out, 2) == LUAT_INPUT_ELOST);
    assert(luat_input_queue_reset(&q) == 0);

    /* Overflow is consumer-local: core and direct sink still commit the frame. */
    luat_input_core_t core;
    luat_input_device_t device = {0};
    luat_input_link_t direct = {0}, queued = {0};
    luat_input_handle_t h;
    uint32_t state[17];
    luat_input_init(&core);
    assert(luat_input_register(&core, &device, &desc, state, 17, &h) == 0);
    observer_t o = {0};
    assert(luat_input_bind(h, &direct, observe, &o) == 0);
    assert(luat_input_queue_init(&q, storage, 16, &ops) == 0);
    assert(luat_input_bind(h, &queued, luat_input_queue_receive, &q) == 0);
    const luat_input_event_t press = {1, 30, 1};
    assert(luat_input_submit(h, 5, &press, 1) == 0 && o.last.sequence == 1);
    assert(luat_input_queue_read(&q, &got, out, 2) == LUAT_INPUT_ELOST);
    luat_input_handle_t bound[1];
    size_t count;
    assert(luat_input_enumerate_bound(&core, luat_input_queue_receive, &q, bound, 1, &count) == 0 && count == 1);
    /* A lost unbind cannot be recovered from the global device registry alone. */
    assert(luat_input_unbind(&queued) == 0);
    assert(luat_input_enumerate(&core, bound, 1, &count) == 0 && count == 1);
    assert(luat_input_enumerate_bound(&core, luat_input_queue_receive, &q, bound, 1, &count) == 0 && count == 0);
    assert(luat_input_bind(h, &queued, luat_input_queue_receive, &q) == 0);
    assert(luat_input_unregister(h, 6) == 0); /* REMOVE cannot fit, registry must reconcile. */
    assert(!core.devices && o.last.flags == (LUAT_INPUT_FRAME_REMOVE | LUAT_INPUT_FRAME_RESET));
    assert(luat_input_queue_reset(&q) == 0);
    assert(luat_input_queue_read(&q, &got, out, 2) == LUAT_INPUT_EEMPTY);
}

/* Two producers and one consumer; only the optional queue is shared. */
#define THREAD_FRAMES 10000U
static uint8_t threaded_storage[32U * THREAD_FRAMES * 2U];
static luat_input_queue_t threaded_queue;
#ifdef _WIN32
static CRITICAL_SECTION mutex;
static uintptr_t thread_lock(void *p) { (void)p; EnterCriticalSection(&mutex); return 0; }
static void thread_unlock(void *p, uintptr_t t) { (void)p; (void)t; LeaveCriticalSection(&mutex); }
static DWORD WINAPI producer(void *p)
#else
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static uintptr_t thread_lock(void *p) { (void)p; pthread_mutex_lock(&mutex); return 0; }
static void thread_unlock(void *p, uintptr_t t) { (void)p; (void)t; pthread_mutex_unlock(&mutex); }
static void *producer(void *p)
#endif
{
    uint32_t id = (uint32_t)(uintptr_t)p;
    luat_input_frame_t f = {id, 0, 0, 2, 0};
    luat_input_event_t e[2] = {{2, 0, 0}, {2, 1, 0}};
    for (uint32_t i = 1; i <= THREAD_FRAMES; i++) {
        f.sequence = i; e[0].value = (int32_t)i; e[1].value = -(int32_t)i;
        assert(luat_input_queue_push(&threaded_queue, &f, e) == 0);
    }
    return 0;
}

static void test_threads(void)
{
    luat_input_queue_ops_t ops = {thread_lock, thread_unlock, NULL, NULL};
    assert(luat_input_queue_init(&threaded_queue, threaded_storage, sizeof(threaded_storage), &ops) == 0);
#ifdef _WIN32
    InitializeCriticalSection(&mutex);
    HANDLE threads[2] = {CreateThread(NULL, 0, producer, (void *)(uintptr_t)1, 0, NULL),
                         CreateThread(NULL, 0, producer, (void *)(uintptr_t)2, 0, NULL)};
    assert(threads[0] && threads[1]);
#else
    pthread_t threads[2];
    assert(!pthread_create(&threads[0], NULL, producer, (void *)(uintptr_t)1));
    assert(!pthread_create(&threads[1], NULL, producer, (void *)(uintptr_t)2));
#endif
    uint32_t last[2] = {0};
    unsigned n = 0;
    while (n < THREAD_FRAMES * 2U) {
        luat_input_frame_t f;
        luat_input_event_t e[2];
        int ret = luat_input_queue_read(&threaded_queue, &f, e, 2);
        if (ret == LUAT_INPUT_EEMPTY) {
#ifdef _WIN32
            Sleep(0);
#else
            sched_yield();
#endif
            continue;
        }
        assert(ret == 0 && f.device_id >= 1 && f.device_id <= 2);
        assert(f.sequence == ++last[f.device_id - 1]);
        assert(e[0].value == (int32_t)f.sequence && e[1].value == -(int32_t)f.sequence);
        n++;
    }
#ifdef _WIN32
    assert(WaitForMultipleObjects(2, threads, TRUE, 10000) == WAIT_OBJECT_0);
    CloseHandle(threads[0]); CloseHandle(threads[1]); DeleteCriticalSection(&mutex);
#else
    pthread_join(threads[0], NULL); pthread_join(threads[1], NULL);
#endif
}

static unsigned benchmark_frames;
static void benchmark_sink(void *p, const luat_input_frame_t *f, const luat_input_event_t *e)
{
    (void)p; (void)e;
    if (!f->flags) benchmark_frames++;
}

static void benchmark(void)
{
    luat_input_core_t core;
    luat_input_device_t dev = {0};
    luat_input_link_t link = {0};
    luat_input_handle_t h;
    luat_input_device_desc_t d = {.name = "mouse", .caps = {.keys = keys, .key_words = 9, .rel_bits = 0x103}};
    uint32_t state[9];
    luat_input_init(&core);
    assert(luat_input_register(&core, &dev, &d, state, 9, &h) == 0);
    assert(luat_input_bind(h, &link, benchmark_sink, NULL) == 0);
    const luat_input_event_t e[] = {{1, 0x110, 1}, {2, 0, 5}, {2, 1, -3}, {2, 8, 1}};
    clock_t start = clock();
    for (unsigned i = 0; i < 1000000; i++) assert(luat_input_submit(h, i, e, 4) == 0);
    double seconds = (double)(clock() - start) / CLOCKS_PER_SEC;
    assert(benchmark_frames == 1000000);
    printf("Host benchmark: 1000000 four-event frames -> direct sink, %.3f s (host only)\n", seconds);
    printf("ABI: event=%zu frame=%zu; native core=%zu device=%zu link=%zu queue=%zu\n",
        sizeof(luat_input_event_t), sizeof(luat_input_frame_t), sizeof(core), sizeof(dev), sizeof(link), sizeof(luat_input_queue_t));
}

int main(void)
{
    test_caps(); test_core(); test_bind_id(); test_queue(); test_threads(); benchmark();
    puts("PASS: frame atomicity, capabilities, key/MT state, snapshot, reentry, hotplug/stale IDs, wrap, queue loss/wrap, 20000 concurrent frames");
    return 0;
}
