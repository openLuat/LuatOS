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

#ifndef INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_SERIAL_H
#define INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_SERIAL_H

#include <stdint.h>

#include "zenoh-pico/link/endpoint.h"
#include "zenoh-pico/protocol/definitions/network.h"

#ifdef __cplusplus
extern "C" {
#endif

/// ZSerial Frame Format
///
/// Using COBS
///
/// +-+-+----+------------+--------+-+
/// |O|H|XXXX|ZZZZ....ZZZZ|CCCCCCCC|0|
/// +-+----+------------+--------+-+
/// |O| |Len |   Data     |  CRC32 |C|
/// +-+-+-2--+----N-------+---4----+-+
///
/// Header: 1byte
/// +---------------+
/// |7|6|5|4|3|2|1|0|
/// +---------------+
/// |x|x|x|x|x|R|A|I|
/// +---------------+
///
/// Flags:
/// I - Init
/// A - Ack
/// R - Reset
///
/// Max Frame Size: 1510
/// Max MTU: 1500
/// Max On-the-wire length: 1516 (MFS + Overhead Byte (OHB) + Kind Byte + End of packet (EOP))

#define _Z_FLAG_SERIAL_INIT 0x01
#define _Z_FLAG_SERIAL_ACK 0x02
#define _Z_FLAG_SERIAL_RESET 0x04

#ifdef __cplusplus
}
#endif

#endif /* INCLUDE_ZENOH_PICO_PROTOCOL_DEFINITIONS_SERIAL_H*/
