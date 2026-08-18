#pragma once

/*
 * Internal OpenVPN reliable-window prototypes (ovpn_rel.c).  Module-internal
 * only; the public OpenVPN client API lives in ovpn/ovpn_client.h.
 */

#include <stdint.h>
#include "ovpn/ovpn_client.h"

#ifdef __cplusplus
extern "C" {
#endif

int rel_send_store(ovpn_client_t *cli, uint32_t id,
                   const uint8_t *data, int len, uint32_t now_ms);
void rel_send_ack(ovpn_client_t *cli, uint32_t ack_id);
void rel_send_retransmit(ovpn_client_t *cli, uint32_t now_ms);

int rel_recv_add(ovpn_client_t *cli, uint32_t id,
                 const uint8_t *data, int len);
int rel_recv_next(ovpn_client_t *cli,
                  const uint8_t **data, int *len, uint32_t *id);
void rel_recv_advance(ovpn_client_t *cli, uint32_t id);

#ifdef __cplusplus
}
#endif
