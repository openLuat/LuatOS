#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_mcu.h"

static luat_rtos_mutex_t flags_lock;
static luat_rtos_mutex_t statistics_lock;
static struct {
    airlink_flags_t flags;
    uint32_t frame_id;
    uint64_t last_ms;
} peers[AIRLINK_LINK_COUNT + 1];
#define peer_flags (peers[luat_airlink_context_link() + 1].flags)
#define next_frame_id (peers[luat_airlink_context_link() + 1].frame_id)
#define last_flags_ms (peers[luat_airlink_context_link() + 1].last_ms)

void luat_airlink_flags_init(void) {
    if (!flags_lock) luat_rtos_mutex_create(&flags_lock);
    if (!statistics_lock) luat_rtos_mutex_create(&statistics_lock);
}

void luat_airlink_statistics_add(uint64_t* counter, uint64_t value) {
    if (statistics_lock) luat_rtos_mutex_lock(statistics_lock, LUAT_WAIT_FOREVER);
    *counter += value;
    if (statistics_lock) luat_rtos_mutex_unlock(statistics_lock);
}
void luat_airlink_statistics_copy(airlink_statistic_t* dst, const airlink_statistic_t* src) {
    if (statistics_lock) luat_rtos_mutex_lock(statistics_lock, LUAT_WAIT_FOREVER);
    *dst = *src;
    if (statistics_lock) luat_rtos_mutex_unlock(statistics_lock);
}

uint32_t luat_airlink_next_frame_id(void) {
    luat_airlink_flags_init();
    luat_rtos_mutex_lock(flags_lock, LUAT_WAIT_FOREVER);
    uint32_t id = next_frame_id++;
    luat_rtos_mutex_unlock(flags_lock);
    return id;
}

void luat_airlink_peer_flags_reset(void) {
    if (!flags_lock) return;
    luat_rtos_mutex_lock(flags_lock, LUAT_WAIT_FOREVER);
    memset(&peer_flags, 0, sizeof(peer_flags));
    last_flags_ms = 0;
    luat_rtos_mutex_unlock(flags_lock);
}

void luat_airlink_peer_flags_update(const airlink_flags_t* flags) {
    if (!flags_lock || !flags) return;
    luat_rtos_mutex_lock(flags_lock, LUAT_WAIT_FOREVER);
    peer_flags = *flags; // Zero is a negative capability declaration, as in V2054.
    last_flags_ms = luat_mcu_tick64_ms();
    luat_rtos_mutex_unlock(flags_lock);
}

void luat_airlink_peer_frame_update(const airlink_link_data_t* frame) {
    luat_airlink_peer_flags_update(&frame->flags);
}

static int supported_at(int index, int rpc) {
    if (!flags_lock) return 0;
    luat_rtos_mutex_lock(flags_lock, LUAT_WAIT_FOREVER);
    if (luat_mcu_tick64_ms() - peers[index].last_ms > 20000)
        memset(&peers[index].flags, 0, sizeof(peers[index].flags));
    int value = rpc ? peers[index].flags.rpc_supported : peers[index].flags.frag_supported;
    luat_rtos_mutex_unlock(flags_lock);
    return value;
}
int luat_airlink_peer_rpc_supported(void) { return supported_at(luat_airlink_context_link() + 1, 1); }
int luat_airlink_peer_frag_supported(void) { return supported_at(luat_airlink_context_link() + 1, 0); }
#ifdef LUAT_USE_AIRLINK_INSTANCE
int luat_airlink_flags_supported_link(int id, int rpc) {
    return id >= 0 && id < AIRLINK_LINK_COUNT ? supported_at(id + 1, rpc) : 0;
}
#endif
