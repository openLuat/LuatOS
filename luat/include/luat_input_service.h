/** Platform-wide input directory. Task context only; never calls Lua.
 * Drivers hold service_lock around core register/feed/reset/unregister and
 * attach/detach. Lock order: transport lock -> service lock. Consumers never
 * acquire transport locks. All functions except init/lock/unlock require the
 * service lock. No Lua allocation/callback is permitted while it is held.
 */
#ifndef LUAT_INPUT_SERVICE_H
#define LUAT_INPUT_SERVICE_H
#include "luat_input.h"

/* C producers/consumers can use the directory without enabling the Lua API. */
#if (defined(LUAT_USE_INPUT_LUA) || defined(LUAT_USE_INPUT_TOUCH)) && !defined(LUAT_USE_INPUT_SERVICE)
#define LUAT_USE_INPUT_SERVICE
#endif

#ifndef LUAT_INPUT_SERVICE_DEVICES
#define LUAT_INPUT_SERVICE_DEVICES 16U
#endif
#ifndef LUAT_INPUT_SERVICE_SUBSCRIPTIONS
#define LUAT_INPUT_SERVICE_SUBSCRIPTIONS 4U
#endif
#define LUAT_INPUT_SERVICE_ENOMEM (-8)

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

int luat_input_service_init(void);
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
