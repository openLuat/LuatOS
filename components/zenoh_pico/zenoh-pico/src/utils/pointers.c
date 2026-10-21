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

#include "zenoh-pico/utils/pointers.h"

const uint8_t *_z_cptr_u8_offset(const uint8_t *ptr, const ptrdiff_t off) { return ptr + off; }
const char *_z_cptr_char_offset(const char *ptr, const ptrdiff_t off) { return ptr + off; }
