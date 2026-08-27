/*
 * OpenVPN reliable transport window (send + recv) for LuatOS netdrv.
 *
 * Split from the original single-file OpenVPN client core; behavior unchanged.
 */

#include "ovpn/ovpn_client.h"
#include "ovpn/ovpn_rel.h"

#include <string.h>
#include "luat_malloc.h"

#define LUAT_LOG_TAG "openvpn"
#include "luat_log.h"

/* ========== Reliable send window ========== */

static int rel_send_find_free(ovpn_client_t *cli) {
    for (int i = 0; i < OVPN_REL_SEND_SIZE; i++) {
        if (!cli->rel_send[i].in_use) return i;
    }
    return -1;
}

static int rel_send_find_by_id(ovpn_client_t *cli, uint32_t id) {
    for (int i = 0; i < OVPN_REL_SEND_SIZE; i++) {
        if (cli->rel_send[i].in_use && cli->rel_send[i].id == id) return i;
    }
    return -1;
}

/* Store a message in the reliable send window for potential retransmission */
int rel_send_store(ovpn_client_t *cli, uint32_t id,
                   const uint8_t *data, int len, uint32_t now_ms)
{
    int slot = rel_send_find_free(cli);
    if (slot < 0) return -1;
    uint8_t *copy = (uint8_t *)luat_heap_malloc(len);
    if (!copy) return -1;
    memcpy(copy, data, len);
    cli->rel_send[slot].in_use = 1;
    cli->rel_send[slot].id = id;
    cli->rel_send[slot].len = (uint16_t)len;
    cli->rel_send[slot].data = copy;
    cli->rel_send[slot].retransmit_at = now_ms + OVPN_RETRANSMIT_BASE_MS;
    return 0;
}

/* Remove acknowledged messages from send window */
void rel_send_ack(ovpn_client_t *cli, uint32_t ack_id) {
    for (int i = 0; i < OVPN_REL_SEND_SIZE; i++) {
        if (cli->rel_send[i].in_use && cli->rel_send[i].id == ack_id) {
            luat_heap_free(cli->rel_send[i].data);
            cli->rel_send[i].in_use = 0;
            cli->rel_send[i].data = NULL;
            return;
        }
    }
}

/* Check and retransmit expired packets */
void rel_send_retransmit(ovpn_client_t *cli, uint32_t now_ms) {
    uint32_t backoff = OVPN_RETRANSMIT_BASE_MS;
    for (int i = 0; i < OVPN_REL_SEND_SIZE; i++) {
        if (!cli->rel_send[i].in_use) continue;
        if (now_ms >= cli->rel_send[i].retransmit_at) {
            if (cli->debug) {
                LLOGD("retransmit seq=%lu", (unsigned long)cli->rel_send[i].id);
            }
            ovpn_send_udp(cli, cli->rel_send[i].data, cli->rel_send[i].len);
            cli->rel_send[i].retransmit_at = now_ms + backoff;
            backoff = backoff < OVPN_RETRANSMIT_MAX_MS ? backoff * 2 : OVPN_RETRANSMIT_MAX_MS;
        }
    }
}

/* ========== Reliable recv window ========== */

static int rel_recv_find_by_id(ovpn_client_t *cli, uint32_t id) {
    for (int i = 0; i < OVPN_REL_RECV_SIZE; i++) {
        if (cli->rel_recv[i].in_use && cli->rel_recv[i].id == id) return i;
    }
    return -1;
}

/* Add a received message to the recv window (if within window) */
int rel_recv_add(ovpn_client_t *cli, uint32_t id,
                 const uint8_t *data, int len)
{
    /* Reject packets older than window */
    if (id + OVPN_REL_RECV_SIZE <= cli->rel_recv_next) return -1;
    /* Reject duplicates */
    if (rel_recv_find_by_id(cli, id) >= 0) return -1;
    /* Find free slot */
    int slot = -1;
    for (int i = 0; i < OVPN_REL_RECV_SIZE; i++) {
        if (!cli->rel_recv[i].in_use) { slot = i; break; }
    }
    if (slot < 0) return -1;
    uint8_t *copy = (uint8_t *)luat_heap_malloc(len);
    if (!copy) return -1;
    memcpy(copy, data, len);
    cli->rel_recv[slot].in_use = 1;
    cli->rel_recv[slot].id = id;
    cli->rel_recv[slot].data = copy;
    cli->rel_recv[slot].len = (uint16_t)len;
    return 0;
}

/* Get the next in-order message from recv window */
int rel_recv_next(ovpn_client_t *cli,
                  const uint8_t **data, int *len, uint32_t *id)
{
    for (int i = 0; i < OVPN_REL_RECV_SIZE; i++) {
        if (cli->rel_recv[i].in_use && cli->rel_recv[i].id == cli->rel_recv_next) {
            *data = cli->rel_recv[i].data;
            *len = cli->rel_recv[i].len;
            *id = cli->rel_recv[i].id;
            return 1;
        }
    }
    return 0;
}

/* Advance the recv window and free consumed slots */
void rel_recv_advance(ovpn_client_t *cli, uint32_t id) {
    for (int i = 0; i < OVPN_REL_RECV_SIZE; i++) {
        if (cli->rel_recv[i].in_use && cli->rel_recv[i].id == id) {
            luat_heap_free(cli->rel_recv[i].data);
            cli->rel_recv[i].in_use = 0;
            cli->rel_recv[i].data = NULL;
            break;
        }
    }
    if (id >= cli->rel_recv_next) {
        cli->rel_recv_next = id + 1;
    }
}
