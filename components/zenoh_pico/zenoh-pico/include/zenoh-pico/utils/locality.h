//
// Copyright (c) 2025 ZettaScale Technology
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

#ifndef ZENOH_PICO_UTILS_LOCALITY_H
#define ZENOH_PICO_UTILS_LOCALITY_H

#include "zenoh-pico/api/constants.h"

static inline bool _z_locality_allows_local(z_locality_t locality) {
    switch (locality) {
        case Z_LOCALITY_REMOTE:
            return false;
        case Z_LOCALITY_ANY:
        case Z_LOCALITY_SESSION_LOCAL:
        default:
            return true;
    }
}

static inline bool _z_locality_allows_remote(z_locality_t locality) {
    switch (locality) {
        case Z_LOCALITY_SESSION_LOCAL:
            return false;
        case Z_LOCALITY_ANY:
        case Z_LOCALITY_REMOTE:
        default:
            return true;
    }
}

#endif  // ZENOH_PICO_UTILS_LOCALITY_H
