/* AI-MANAGED: true */
/* SPDX-License-Identifier: MIT */
#include <stdio.h>
#include <string.h>
#include "zenoh-pico/session/reply.h"
#include "zenoh-pico/session/query.h"
#include "zenoh-pico/session/utils.h"

static void count_drop(void *counter) { ++*(unsigned *)counter; }

int main(void) {
    _z_session_t session = {0};
    _z_n_msg_response_final_t final = {0};
    unsigned drops = 0;
    _z_pending_query_t *pending = _z_unsafe_register_pending_query(&session);
    if (pending == NULL) return 2;
    final._request_id = pending->_id;
    memset(pending, 0, sizeof(*pending));
    pending->_id = final._request_id;
    pending->_dropper = count_drop;
    pending->_arg = &drops;
    pending->_remaining_finals = 2;
    if (_z_trigger_reply_final(&session, &final) || drops != 0 || pending->_remaining_finals != 1) return 3;
    if (_z_trigger_reply_final(&session, &final) || drops != 1 || session._pending_queries != NULL) return 4;
    if (_z_trigger_reply_final(&session, &final) || drops != 1) return 5;
    _z_atomic_bool_store(&session._is_closed, true, _z_memory_order_release);
    int closed = _z_trigger_reply_final(&session, &final);
    printf("two_finals=ok duplicate=ok drops=%u closed_rc=%d expected=%d\n", drops, closed, _Z_ERR_SESSION_CLOSED);
    return closed == _Z_ERR_SESSION_CLOSED ? 0 : 6;
}
