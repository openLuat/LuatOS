//
// Copyright (c) 2026 ZettaScale Technology
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

#ifndef INCLUDE_ZENOH_PICO_SESSION_WEAK_SESSION_H
#define INCLUDE_ZENOH_PICO_SESSION_WEAK_SESSION_H

#include "zenoh-pico/collections/refcount.h"

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration to avoid cyclical include
typedef struct _z_session_t _z_session_t;
extern void _z_session_clear(_z_session_t *zn);
_Z_REFCOUNT_DEFINE_NO_FROM_VAL(_z_session, _z_session)

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_SESSION_WEAK_SESSION_H */
