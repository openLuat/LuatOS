#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_mcu.h"

static luat_rtos_mutex_t flags_lock;
static airlink_flags_t peer_flags;
static uint32_t next_frame_id;
static uint64_t last_flags_ms;

void luat_airlink_flags_init(void) {
    if (!flags_lock) luat_rtos_mutex_create(&flags_lock);
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

static int supported(int rpc) {
    if (!flags_lock) return 0;
    luat_rtos_mutex_lock(flags_lock, LUAT_WAIT_FOREVER);
    if (luat_mcu_tick64_ms() - last_flags_ms > 20000) memset(&peer_flags, 0, sizeof(peer_flags));
    int value = rpc ? peer_flags.rpc_supported : peer_flags.frag_supported;
    luat_rtos_mutex_unlock(flags_lock);
    return value;
}
int luat_airlink_peer_rpc_supported(void) { return supported(1); }
int luat_airlink_peer_frag_supported(void) { return supported(0); }
