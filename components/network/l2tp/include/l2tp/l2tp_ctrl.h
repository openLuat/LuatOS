#pragma once

/*
 * Internal control/data-plane prototypes shared across the split L2TP client
 * sources (l2tp_client.c / l2tp_ctrl.c / l2tp_ppp.c).  Module-internal only;
 * the public L2TP client API lives in l2tp/l2tp_client.h.
 */

#include <stdint.h>
#include "lwip/pbuf.h"
#include "l2tp/l2tp_client.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Wire-format senders and the incoming-packet entry point (l2tp_ctrl.c) */
err_t l2tp_data_send(l2tp_client_t *cli, struct pbuf *p, u16_t skip,
                     u8_t add_proto, u16_t protocol);
void l2tp_input_packet(l2tp_client_t *cli, const u8_t *data, u16_t datalen,
                       ip_addr_t *addr, u16_t port);
err_t l2tp_send_sccrq(l2tp_client_t *cli);
err_t l2tp_send_scccn(l2tp_client_t *cli, u16_t ns);
err_t l2tp_send_icrq(l2tp_client_t *cli, u16_t ns);
err_t l2tp_send_iccn(l2tp_client_t *cli, u16_t ns);
err_t l2tp_send_stopccn(l2tp_client_t *cli, u16_t ns);

#ifdef __cplusplus
}
#endif
