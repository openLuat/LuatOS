/** @file luat_input.h
 * Small, allocation-free input core. See components/input/README.md for ownership
 * and synchronization contracts. Event numbers follow Linux input semantics;
 * this is not the Linux evdev binary ABI.
 */
#ifndef LUAT_INPUT_H
#define LUAT_INPUT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    LUAT_INPUT_OK = 0,
    LUAT_INPUT_EINVAL = -1,
    LUAT_INPUT_ENOSPC = -2,
    LUAT_INPUT_ESTALE = -3,
    LUAT_INPUT_EBUSY = -4,
    LUAT_INPUT_ENOTSUP = -5,
    LUAT_INPUT_EEMPTY = -6,
    LUAT_INPUT_ELOST = -7
};

enum {
    LUAT_INPUT_EV_SYN = 0x00,
    LUAT_INPUT_EV_KEY = 0x01,
    LUAT_INPUT_EV_REL = 0x02,
    LUAT_INPUT_EV_ABS = 0x03,
    LUAT_INPUT_EV_MSC = 0x04
};

enum {
    LUAT_INPUT_SYN_REPORT = 0,
    LUAT_INPUT_REL_X = 0x00,
    LUAT_INPUT_REL_Y = 0x01,
    LUAT_INPUT_REL_HWHEEL = 0x06,
    LUAT_INPUT_REL_WHEEL = 0x08,
    LUAT_INPUT_ABS_X = 0x00,
    LUAT_INPUT_ABS_Y = 0x01,
    LUAT_INPUT_ABS_PRESSURE = 0x18,
    LUAT_INPUT_ABS_MT_SLOT = 0x2f,
    LUAT_INPUT_ABS_MT_TOUCH_MAJOR = 0x30,
    LUAT_INPUT_ABS_MT_POSITION_X = 0x35,
    LUAT_INPUT_ABS_MT_POSITION_Y = 0x36,
    LUAT_INPUT_ABS_MT_TRACKING_ID = 0x39,
    LUAT_INPUT_ABS_MT_PRESSURE = 0x3a,
    LUAT_INPUT_BTN_LEFT = 0x110,
    LUAT_INPUT_BTN_RIGHT = 0x111,
    LUAT_INPUT_BTN_MIDDLE = 0x112,
    LUAT_INPUT_BTN_TOUCH = 0x14a
};

enum {
    LUAT_INPUT_RELEASE = 0,
    LUAT_INPUT_PRESS = 1,
    LUAT_INPUT_REPEAT = 2,
    LUAT_INPUT_FRAME_ATTACH = 1U << 0,
    LUAT_INPUT_FRAME_REMOVE = 1U << 1,
    LUAT_INPUT_FRAME_RESET = 1U << 2,
    LUAT_INPUT_PROP_POINTER = 1U << 0,
    LUAT_INPUT_PROP_DIRECT = 1U << 1
};

#define LUAT_INPUT_KEY_WORDS_MAX 24U /* Linux key/button codes 0..0x2ff. */
#ifndef LUAT_INPUT_MT_SLOTS_MAX
#define LUAT_INPUT_MT_SLOTS_MAX 16U
#endif

typedef struct {
    uint16_t type;
    uint16_t code;
    int32_t value;
} luat_input_event_t;

/** One immutable frame; timestamp_ms is a wrapping monotonic device/host clock. */
typedef struct {
    uint32_t device_id;
    uint32_t sequence;
    uint32_t timestamp_ms;
    uint16_t count;
    uint16_t flags;
} luat_input_frame_t;

/** Sorted by code, unique. MT tracking ID must allow -1 and start at -1. */
typedef struct {
    uint16_t code;
    uint16_t reserved;
    int32_t minimum;
    int32_t maximum;
    int32_t initial;
} luat_input_axis_t;

/** Immutable after registration; arrays can reside in read-only flash. */
typedef struct {
    const uint32_t *keys;
    const luat_input_axis_t *abs;
    const luat_input_axis_t *mt;
    uint32_t rel_bits;
    uint32_t msc_bits;
    uint16_t key_words;
    uint16_t abs_count;
    uint16_t mt_count;
    uint16_t mt_slots;
} luat_input_caps_t;

typedef struct {
    const char *name;
    luat_input_caps_t caps;
    uint32_t properties;
    uint16_t bus;
    uint16_t vendor;
    uint16_t product;
    uint16_t version;
} luat_input_device_desc_t;

typedef struct luat_input_device luat_input_device_t;
typedef struct luat_input_link luat_input_link_t;

/** Borrowed only during callback. Never retain frame/events or mutate the core.
 * A slow/cross-task consumer should bind luat_input_queue_receive instead.
 */
typedef void (*luat_input_receive_t)(void *userdata,
    const luat_input_frame_t *frame, const luat_input_event_t *events);

typedef struct {
    luat_input_device_t *devices;
    uint32_t next_id;
    uint8_t dispatching;
} luat_input_core_t;

/** An instance token. Device storage must still exist when checking a token. */
typedef struct {
    luat_input_device_t *device;
    uint32_t id;
} luat_input_handle_t;

/** Caller-owned, zero-initialize before first use. Fields are private to core. */
struct luat_input_link {
    luat_input_link_t *next;
    luat_input_device_t *device;
    luat_input_receive_t receive;
    void *userdata;
};

/** Caller-owned, zero-initialize before first registration. No embedded queue. */
struct luat_input_device {
    luat_input_device_t *next;
    luat_input_core_t *core;
    const luat_input_device_desc_t *desc;
    luat_input_link_t *links;
    uint32_t *state;
    uint32_t id;
    uint32_t sequence;
    uint32_t timestamp_ms;
    uint16_t mt_slot;
};

typedef struct {
    uint32_t device_id;
    uint32_t sequence;
    uint32_t timestamp_ms;
    uint16_t mt_slot;
    uint16_t reserved;
} luat_input_snapshot_t;

/** All core operations require caller serialization. Callbacks run inside that
 * serialization scope. Queries are allowed in callbacks; mutations return EBUSY.
 */
/** Initialize once before use; never reinitialize an active core. */
void luat_input_init(luat_input_core_t *core);
/** Required uint32_t words; SIZE_MAX means invalid capabilities. */
size_t luat_input_state_words(const luat_input_caps_t *caps);
/** Register caller-owned device/descriptor/state storage; no allocation. Instance
 * IDs are unique within one initialized core until exhaustion (no ID reuse).
 */
int luat_input_register(luat_input_core_t *core, luat_input_device_t *device,
    const luat_input_device_desc_t *desc, uint32_t *state, size_t words,
    luat_input_handle_t *handle);
/** Stop producers first. Cancels state, emits REMOVE|RESET, clears all bindings. */
int luat_input_unregister(luat_input_handle_t handle, uint32_t timestamp_ms);
/** Add a resolved direct route and notify this consumer with ATTACH. Identical
 * receive/userdata pairs on one device are rejected. Take a snapshot on ATTACH.
 */
int luat_input_bind(luat_input_handle_t handle, luat_input_link_t *link,
    luat_input_receive_t receive, void *userdata);
/** Remove one route, increment sequence and deliver REMOVE to that consumer. */
int luat_input_unbind(luat_input_link_t *link);
/** Validates the whole frame before changing state. No allocation/copy of events.
 * Success means committed to the device, not guaranteed delivery to every queue.
 * SYN_REPORT is optional; if provided it must be the final event with value 0.
 */
int luat_input_submit(luat_input_handle_t handle, uint32_t timestamp_ms,
    const luat_input_event_t *events, uint16_t count);
/** Cancel all device state and publish RESET (not a click or normal release). */
int luat_input_reset(luat_input_handle_t handle, uint32_t timestamp_ms);
/** Read KEY/ABS state. slot selects an MT contact, ignored for other codes. */
int luat_input_get_value(luat_input_handle_t handle, uint16_t type,
    uint16_t code, uint16_t slot, int32_t *value);
/** State layout: key_words bitmap, abs_count values, then mt_slots*mt_count values.
 * Signed axis values occupy uint32_t words as their bit representation.
 */
int luat_input_snapshot(luat_input_handle_t handle, luat_input_snapshot_t *snapshot,
    uint32_t *state, size_t words);
/** Enumerate one core's active instances, for configuration/loss recovery only. */
int luat_input_enumerate(luat_input_core_t *core, luat_input_handle_t *handles,
    size_t capacity, size_t *count);
/** Resolve one active instance ID. Configuration path only. */
int luat_input_lookup(luat_input_core_t *core, uint32_t device_id,
    luat_input_handle_t *handle);
/** Return the immutable descriptor borrowed for this device's registered life. */
int luat_input_get_desc(luat_input_handle_t handle,
    const luat_input_device_desc_t **desc);
/** Query one event code. ABS returns its immutable axis metadata when axis is not
 * NULL; other supported types set axis to NULL. Returns ENOTSUP when absent.
 */
int luat_input_get_capability(luat_input_handle_t handle, uint16_t type,
    uint16_t code, const luat_input_axis_t **axis);
/** Resolve and bind by instance ID. Returns the resolved handle when requested.
 * This remains a configuration operation; events still dispatch through link.
 */
int luat_input_bind_id(luat_input_core_t *core, uint32_t device_id,
    luat_input_link_t *link, luat_input_receive_t receive, void *userdata,
    luat_input_handle_t *handle);
/** Resolve current bindings for a consumer, including loss recovery after unbind.
 * Queued consumers match receive=luat_input_queue_receive, userdata=queue.
 * Configuration path only; a queue with core bindings belongs to one core.
 */
int luat_input_enumerate_bound(luat_input_core_t *core,
    luat_input_receive_t receive, void *userdata, luat_input_handle_t *handles,
    size_t capacity, size_t *count);
/** Sequence order, including wrap; comparisons must be less than 2^31 apart. */
static inline int luat_input_sequence_after(uint32_t a, uint32_t b)
{
    return a != b && (uint32_t)(a - b) < UINT32_C(0x80000000);
}

/** Optional luat_input_log.c sink using LuatOS DEBUG logging (tag: input).
 * Bind as a regular consumer; userdata is ignored. Run in task context.
 * The core itself does not require this module or a logging backend.
 */
void luat_input_log_receive(void *userdata, const luat_input_frame_t *frame,
    const luat_input_event_t *events);

/* Optional queue module (LUAT_USE_INPUT_QUEUE). Lock hooks must be supplied as a
 * pair for cross-context access. Null hooks explicitly mean externally serialized.
 * ISR producers require ISR-safe hooks/notify; no implicit ISR safety is promised.
 */
typedef uintptr_t (*luat_input_lock_t)(void *userdata);
typedef void (*luat_input_unlock_t)(void *userdata, uintptr_t token);
typedef struct {
    luat_input_lock_t lock;
    luat_input_unlock_t unlock;
    void (*notify)(void *userdata);
    void *userdata;
} luat_input_queue_ops_t;

typedef struct {
    uint8_t *buffer;
    size_t capacity;
    size_t head;
    size_t tail;
    luat_input_queue_ops_t ops;
    uint8_t lost;
    uint8_t full;
} luat_input_queue_t;

/** Queue, buffer and ops userdata must outlive bindings and pending notifications. */
int luat_input_queue_init(luat_input_queue_t *queue, void *buffer, size_t bytes,
    const luat_input_queue_ops_t *ops);
/** Copy a whole frame; overflow flushes this queue and latches ELOST. notify runs
 * after unlock on empty->nonempty or clean->lost. It must be a nonblocking signal.
 */
int luat_input_queue_push(luat_input_queue_t *queue,
    const luat_input_frame_t *frame, const luat_input_event_t *events);
/** Bindable sink wrapper. Consumers observe errors through sticky queue ELOST. */
void luat_input_queue_receive(void *queue,
    const luat_input_frame_t *frame, const luat_input_event_t *events);
/** Single consumer. ENOSPC returns required frame.count without consuming it.
 * ELOST is sticky and covers ALL devices bound to this queue. No partial frames.
 */
int luat_input_queue_read(luat_input_queue_t *queue,
    luat_input_frame_t *frame, luat_input_event_t *events, size_t capacity);
/** Flush and clear loss BEFORE taking fresh device snapshots. Then ignore queued
 * frames at/before each snapshot sequence; repeat recovery if ELOST reoccurs.
 * Reconcile removed/unbound devices using enumerate_bound, not the global device
 * list. Hold the core serialization scope while resetting/enumerating/snapshotting.
 * Relative movement cannot be recovered. Never retain the queue lock to call core.
 */
int luat_input_queue_reset(luat_input_queue_t *queue);

#ifdef __cplusplus
}
#endif
#endif
