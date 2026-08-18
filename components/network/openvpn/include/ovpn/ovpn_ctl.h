#pragma once

/*
 * Internal OpenVPN control-channel prototypes (ovpn_ctl.c).  Module-internal
 * only; the public OpenVPN client API lives in ovpn/ovpn_client.h.
 */

#include <stdint.h>
#include "ovpn/ovpn_client.h"

#ifdef __cplusplus
extern "C" {
#endif

int ovpn_send_ctrl(ovpn_client_t *cli, uint8_t opcode,
                   const uint8_t *payload, int payload_len);
int ovpn_send_ack(ovpn_client_t *cli);
void ovpn_queue_ack(ovpn_client_t *cli, uint32_t seq);

int ovpn_build_km2_msg(ovpn_client_t *cli, uint8_t *buf, int buflen);
int ovpn_parse_km2_reply(ovpn_client_t *cli, const uint8_t *data, int len);
void ovpn_process_tls_app_data(ovpn_client_t *cli);
void ovpn_process_push_reply(ovpn_client_t *cli, const char *reply, int len);

#ifdef __cplusplus
}
#endif
