/* AI-MANAGED: true */
/* SPDX-License-Identifier: EPL-2.0 OR Apache-2.0 */
#ifndef ZENOH_PICO_UNICAST_OBSERVE_H
#define ZENOH_PICO_UNICAST_OBSERVE_H
#include <stdint.h>
#include "zenoh-pico/config.h"

#ifdef ZP_UNICAST_OBSERVER
void ZP_UNICAST_OBSERVER(const char *event, uint64_t peer_lease, uint64_t effective_lease);
void ZP_TRANSPORT_FAULT_OBSERVER(const char *stage, int result, int remote_reason);
#define _Z_ACCEPTED_RX(event) ZP_UNICAST_OBSERVER(event, 0, 0)
#define _Z_ACCEPTED_OPEN(peer, effective) ZP_UNICAST_OBSERVER("open_ack", peer, effective)
#define _Z_TRANSPORT_FAULT(stage, result, remote) ZP_TRANSPORT_FAULT_OBSERVER(stage, result, remote)
#else
#define _Z_ACCEPTED_RX(event) ((void)0)
#define _Z_ACCEPTED_OPEN(peer, effective) ((void)0)
#define _Z_TRANSPORT_FAULT(stage, result, remote) ((void)0)
#endif
#endif
