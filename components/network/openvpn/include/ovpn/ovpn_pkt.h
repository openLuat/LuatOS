#pragma once

/*
 * Internal OpenVPN wire-format prototypes shared across the split client
 * sources (ovpn_pkt.c / ovpn_rel.c / ovpn_ctl.c / ovpn_tls.c /
 * ovpn_crypto.c / ovpn_client.c).  Module-internal only; the public
 * OpenVPN client API lives in ovpn/ovpn_client.h.
 */

#include <stdint.h>
#include "ovpn/ovpn_client.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Byte-level helpers (ovpn_pkt.c) */
uint8_t ovpn_op_extract(uint8_t byte);
uint8_t ovpn_key_id_extract(uint8_t byte);
void ovpn_copy_sid(uint8_t *dst, const uint8_t *src);

/* Header build/parse (ovpn_pkt.c) */
int ovpn_build_hdr(uint8_t *buf, int buflen,
                   uint8_t opcode, uint8_t key_id,
                   const uint8_t *src_sid,
                   const uint8_t *peer_sid,
                   const uint32_t *acks, int ack_count,
                   uint32_t packet_id, int include_pid);
int ovpn_parse_pkt(const uint8_t *data, int datalen,
                   uint8_t *opcode, uint8_t *key_id,
                   uint8_t *peer_sid,
                   uint32_t *acks, int *ack_count,
                   uint32_t *packet_id, int *has_packet_id,
                   const uint8_t **payload, int *payload_len);

#ifdef __cplusplus
}
#endif
