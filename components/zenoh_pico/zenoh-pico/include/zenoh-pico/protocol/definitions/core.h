//
// Copyright (c) 2022 ZettaScale Technology
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0, or the Apache License, Version 2.0
// which is available at https://www.apache.org/licenses/LICENSE-2.0.
//
// SPDX-License-Identifier: EPL-2.0 OR Apache-2.0
//
// Contributors:
//   ZettaScale Zenoh Team, <zenoh@zettascale.tech>
//

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_CORE_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_CORE_H

#include "zenoh-pico/protocol/core.h"

#define _Z_DEFAULT_UNICAST_BATCH_SIZE 65535
#define _Z_DEFAULT_MULTICAST_BATCH_SIZE 8192
#define _Z_DEFAULT_RESOLUTION_SIZE 2

#define _Z_DECLARE_CLEAR(layer, name) void _z_##layer##_msg_clear_##name(_z_##name##_t *m, uint8_t header)
#define _Z_DECLARE_CLEAR_NOH(layer, name) void _z_##layer##_msg_clear_##name(_z_##name##_t *m)

// NOTE: 16 bits (2 bytes) may be prepended to the serialized message indicating the total length
//       in bytes of the message, resulting in the maximum length of a message being 65_535 bytes.
//       This is necessary in those stream-oriented transports (e.g., TCP) that do not preserve
//       the boundary of the serialized messages. The length is encoded as little-endian.
//       In any case, the length of a message must not exceed 65_535 bytes.
#define _Z_MSG_LEN_ENC_SIZE 2

/*=============================*/
/*       Message header        */
/*=============================*/
#define _Z_MID_MASK 0x1f
#define _Z_FLAGS_MASK 0xe0

/*=============================*/
/*       Message helpers       */
/*=============================*/
#define _Z_MID(h) (_Z_MID_MASK & (h))
#define _Z_FLAGS(h) (_Z_FLAGS_MASK & (h))
#define _Z_HAS_FLAG(h, f) (((h) & (f)) != 0)
#define _Z_SET_FLAG(h, f) (h |= f)
#define _Z_CLEAR_FLAG(h, f) (h &= (uint8_t)(~(f)))

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_CORE_H */
