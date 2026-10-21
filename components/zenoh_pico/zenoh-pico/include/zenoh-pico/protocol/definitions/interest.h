//
// Copyright (c) 2024 ZettaScale Technology
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

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_INTEREST_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_INTEREST_H

#include <stdint.h>

#include "zenoh-pico/protocol/core.h"

#ifdef __cplusplus
extern "C" {
#endif

#define _Z_INTEREST_FLAG_KEYEXPRS (1)
#define _Z_INTEREST_FLAG_SUBSCRIBERS (1 << 1)
#define _Z_INTEREST_FLAG_QUERYABLES (1 << 2)
#define _Z_INTEREST_FLAG_TOKENS (1 << 3)
#define _Z_INTEREST_FLAG_RESTRICTED (1 << 4)
#define _Z_INTEREST_FLAG_CURRENT (1 << 5)
#define _Z_INTEREST_FLAG_FUTURE (1 << 6)
#define _Z_INTEREST_FLAG_AGGREGATE (1 << 7)

#define _Z_INTEREST_NOT_FINAL_MASK (_Z_INTEREST_FLAG_CURRENT | _Z_INTEREST_FLAG_FUTURE)

typedef struct {
    _z_wireexpr_t _keyexpr;
    uint32_t _id;
    uint8_t flags;
    bool complete;
} _z_interest_t;

// Warning: None of the sub-types require a non-0 initialization. Add a init function if it changes.
static inline _z_interest_t _z_interest_null(void) { return (_z_interest_t){0}; }
void _z_interest_clear(_z_interest_t* decl);
_z_interest_t _z_make_interest(_Z_MOVE(_z_wireexpr_t) key, uint32_t id, uint8_t flags);
_z_interest_t _z_make_interest_final(uint32_t id);

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_INTEREST_H */
