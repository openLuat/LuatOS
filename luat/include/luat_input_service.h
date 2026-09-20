/** Platform-wide input directory. Task context only; never calls Lua.
 * Drivers hold service_lock around core register/feed/reset/unregister and
 * attach/detach. Lock order: transport lock -> service lock. Consumers never
 * acquire transport locks. All functions except init/is_ready/lock/unlock require the
 * service lock. No Lua allocation/callback is permitted while it is held.
 */
#ifndef LUAT_INPUT_SERVICE_H
#define LUAT_INPUT_SERVICE_H
#include "luat_input.h"

/* Included with LUAT_USE_INPUT; C consumers do not require the Lua API. */

#ifndef LUAT_INPUT_SERVICE_DEVICES
#define LUAT_INPUT_SERVICE_DEVICES 16U
#endif
#ifndef LUAT_INPUT_SERVICE_SUBSCRIPTIONS
#define LUAT_INPUT_SERVICE_SUBSCRIPTIONS 4U
#endif
#define LUAT_INPUT_SERVICE_ENOMEM (-8)
#define LUAT_INPUT_SERVICE_ENOTREADY (-9)

/* Owned flat snapshot, pointer-free and padded to an event-size boundary.
 * Data: capability key words, ABS axes, MT axes, then state words.
 * Also used as the payload of queued ATTACH/RESET frames (count is payload
 * length / 8 there, not the number of semantic input events).
 */
typedef struct {
    uint32_t bytes;
    luat_input_snapshot_t snapshot;
    uint32_t properties, rel_bits, msc_bits;
    uint16_t bus, vendor, product, version;
    uint16_t key_words, abs_count, mt_count, mt_slots;
    char name[64];
    uint32_t data[];
} luat_input_service_info_t;

typedef struct luat_input_subscription luat_input_subscription_t;
typedef struct {
    luat_input_link_t link;
    luat_input_subscription_t *owner;
} luat_input_service_route_t;

struct luat_input_subscription {
    luat_input_queue_t queue;
    luat_input_service_route_t routes[LUAT_INPUT_SERVICE_DEVICES];
    uint32_t device_id, types;
    uint32_t frames, overflows, required_bytes;
    int fault;
    unsigned slot;
    uint8_t active;
    void (*notify)(void *);
    void *userdata;
};

/** Application startup, after RTOS setup and before producers/consumers start.
 * Each BSP opts in and calls before luat_main; standalone C apps do likewise.
 * The common LuatOS startup does not initialize this service.
 * Already ready: OK without reset. Concurrent init: EBUSY without waiting.
 * Allocation failure leaves the service stopped and permits a later retry.
 */
int luat_input_service_init(void);
/** Safe without service lock; readiness is permanent once init succeeds.
 * All other service operations require successful initialization first.
 */
int luat_input_service_is_ready(void);
/** Optional configuration-time observer. All callbacks run under service lock.
 * Use attach/detach to bind/unbind direct input links owned by the consumer.
 * No observer traversal occurs on the per-frame path. Storage must outlive the
 * registration; zero-initialize before first use. Callbacks must not reenter
 * observer or device lifecycle APIs.
 */
typedef struct luat_input_service_observer {
    void (*attach)(void *userdata, luat_input_handle_t handle);
    void (*detach)(void *userdata, luat_input_handle_t handle);
    void *userdata;
    struct luat_input_service_observer *next;
    uint8_t active;
} luat_input_service_observer_t;
/** Service lock required. Adding visits existing devices; removing detaches all. */
int luat_input_service_observe(luat_input_service_observer_t *observer);
void luat_input_service_unobserve(luat_input_service_observer_t *observer);
void luat_input_service_lock(void);
void luat_input_service_unlock(void);
luat_input_core_t *luat_input_service_core(void);
int luat_input_service_attach(luat_input_handle_t handle);
void luat_input_service_detach(luat_input_handle_t handle);
size_t luat_input_service_list(uint32_t *ids, size_t capacity);
luat_input_service_info_t *luat_input_service_info(uint32_t id);
int luat_input_service_subscribe(luat_input_subscription_t *sub, uint32_t id,
    uint32_t types, void *buffer, size_t bytes, void (*notify)(void *), void *userdata);
void luat_input_service_close(luat_input_subscription_t *sub);
/* Recover atomically into caller's pointer array; free each owned info with
 * luat_heap_free. On success overflow invalidates the consumer's entire old
 * baseline, followed by ATTACH snapshots for the currently bound devices. */
int luat_input_service_recover(luat_input_subscription_t *sub,
    luat_input_service_info_t **infos, size_t capacity, size_t *count);
#endif
