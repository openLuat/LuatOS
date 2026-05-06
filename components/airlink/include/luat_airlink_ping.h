#ifndef LUAT_AIRLINK_PING_H
#define LUAT_AIRLINK_PING_H

#include "luat_airlink.h"
#include <stdint.h>

// Maximum echo payload size (bytes)
#define AIRLINK_PING_ECHO_MAX 256

/*
 * Synchronous ping helper. pkgid is pre-allocated by the caller and passed in
 * so the Lua binding can return it immediately before spawning the worker.
 *
 * Wire format: [pkgid:8][send_tick_ms:8][payload_len:2][payload:N]
 *
 * Returns:
 *   0   success
 *  -1   timeout
 *  -2   resource error (malloc/semaphore/slot full)
 *  -3   send failed
 *  -4   malformed pong response
 */
int luat_airlink_ping_raw(uint8_t mode, uint64_t pkgid,
                          const uint8_t* payload, uint16_t payload_len,
                          uint32_t timeout_ms,
                          uint64_t* rtt_ms_out,
                          uint8_t* echo_buf, uint16_t echo_buf_size,
                          uint16_t* echo_len_out);

#endif /* LUAT_AIRLINK_PING_H */
