/*
 * OpenVPN2 wire-format helpers for LuatOS netdrv: opcode/key-id composition,
 * session-id copy, and the packet header build/parse routines.
 *
 * Split from the original single-file OpenVPN client core; behavior unchanged.
 */

#include "ovpn/ovpn_client.h"
#include "ovpn/ovpn_pkt.h"

#include <string.h>

/* ========== Low-level protocol helpers ========== */

/* Compose opcode byte: (opcode << 3) | key_id */
static inline uint8_t ovpn_op_compose(uint8_t opcode, uint8_t key_id) {
    return (opcode << OVPN_OPCODE_SHIFT) | (key_id & OVPN_KEY_ID_MASK);
}

/* Extract opcode from first byte */
uint8_t ovpn_op_extract(uint8_t byte) {
    return byte >> OVPN_OPCODE_SHIFT;
}

/* Extract key_id from first byte */
uint8_t ovpn_key_id_extract(uint8_t byte) {
    return byte & OVPN_KEY_ID_MASK;
}

/* Write uint32 in network byte order */
static inline void ovpn_write_u32(uint8_t *dst, uint32_t val) {
    dst[0] = (uint8_t)(val >> 24);
    dst[1] = (uint8_t)(val >> 16);
    dst[2] = (uint8_t)(val >> 8);
    dst[3] = (uint8_t)(val);
}

/* Read uint32 in network byte order */
static inline uint32_t ovpn_read_u32(const uint8_t *src) {
    return ((uint32_t)src[0] << 24) | ((uint32_t)src[1] << 16) |
           ((uint32_t)src[2] << 8)  | (uint32_t)src[3];
}

/* Copy 8-byte session ID */
void ovpn_copy_sid(uint8_t *dst, const uint8_t *src) {
    memcpy(dst, src, OVPN_SID_SIZE);
}

/* Build a complete OpenVPN packet header in buf, return total header size.
 * OpenVPN2 wire format (no tls-auth):
 *   [op(1)] [sid(8)] [ack_cnt(1)] [ack_ids(N*4)] [remote_sid(8) if ack_cnt>0] [pid(4)]
 * Verified against packet hex: count → ack_ids → remote_sid order */
int ovpn_build_hdr(uint8_t *buf, int buflen,
                   uint8_t opcode, uint8_t key_id,
                   const uint8_t *src_sid,
                   const uint8_t *peer_sid,
                   const uint32_t *acks, int ack_count,
                   uint32_t packet_id, int include_pid)
{
    int pos = 0;
    if (pos >= buflen) return -1;

    buf[pos++] = ovpn_op_compose(opcode, key_id);
    if (pos + OVPN_SID_SIZE > buflen) return -1;
    memcpy(buf + pos, src_sid, OVPN_SID_SIZE);
    pos += OVPN_SID_SIZE;

    /* ACK list: count(1) + ack_ids(count*4) + [remote_sid(8) if count>0] */
    if (pos + 1 > buflen) return -1;
    buf[pos++] = (uint8_t)ack_count;
    for (int i = 0; i < ack_count; i++) {
        if (pos + 4 > buflen) return -1;
        ovpn_write_u32(buf + pos, acks[i]);
        pos += 4;
    }
    if (ack_count > 0) {
        if (pos + OVPN_SID_SIZE > buflen) return -1;
        memcpy(buf + pos, peer_sid, OVPN_SID_SIZE);
        pos += OVPN_SID_SIZE;
    }

    /* Packet ID after ack_list */
    if (include_pid) {
        if (pos + 4 > buflen) return -1;
        ovpn_write_u32(buf + pos, packet_id);
        pos += 4;
    }

    return pos;
}

/* Parse an incoming OpenVPN packet.
 * Returns 0 on success, -1 on error.
 * Out parameters are set only for valid packets. */
int ovpn_parse_pkt(const uint8_t *data, int datalen,
                   uint8_t *opcode, uint8_t *key_id,
                   uint8_t *peer_sid,
                   uint32_t *acks, int *ack_count,
                   uint32_t *packet_id, int *has_packet_id,
                   const uint8_t **payload, int *payload_len)
{
    int pos = 0;
    if (datalen < 1) return -1;
    uint8_t ob = data[pos++];
    *opcode = ovpn_op_extract(ob);
    *key_id = ovpn_key_id_extract(ob);

    *ack_count = 0;
    *has_packet_id = 0;

    /* OpenVPN2 wire format (no tls-auth) ref: reliable.c reliable_ack_parse:
     *   [opcode(1)] [peer_sid(8)] [ack_list] [packet_id(4)] [payload]
     * where ack_list = ack_count(1) + ack_ids(count*4) + [remote_sid(8) if count>0] */

    /* Read peer session ID */
    if (pos + OVPN_SID_SIZE > datalen) return -1;
    if (peer_sid) memcpy(peer_sid, data + pos, OVPN_SID_SIZE);
    pos += OVPN_SID_SIZE;

    /* Read ACK list: count(1) + ack_ids(count*4) + [remote_sid(8) if count>0]
     * Wire order verified against packet hex: ack_ids BEFORE remote_sid */
    if (pos < datalen) {
        int ac = data[pos++];
        if (ac < 0 || ac > OVPN_MAX_ACKS_ACK) return -1;
        *ack_count = ac;
        for (int i = 0; i < ac; i++) {
            if (pos + 4 > datalen) return -1;
            if (acks) acks[i] = ovpn_read_u32(data + pos);
            pos += 4;
        }
        /* Skip remote_sid (8 bytes) when count > 0; it echoes our session_id back */
        if (ac > 0) {
            if (pos + OVPN_SID_SIZE > datalen) return -1;
            pos += OVPN_SID_SIZE;
        }
    }

    /* Read packet_id (present for all non-ACK_V1 control packets) */
    if (*opcode != OVPN_OP_ACK_V1 && pos + 4 <= datalen) {
        if (packet_id) *packet_id = ovpn_read_u32(data + pos);
        pos += 4;
        *has_packet_id = 1;
    }

    *payload = data + pos;
    *payload_len = datalen - pos;
    return 0;
}
