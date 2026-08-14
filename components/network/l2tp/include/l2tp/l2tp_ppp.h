#pragma once

/*
 * Internal PPP-glue prototypes shared between the split L2TP client sources.
 * The link_callbacks table and the PPP link-status callback live in
 * l2tp_ppp.c and are consumed by the lifecycle code in l2tp_client.c.
 * Module-internal only; the public L2TP client API lives in l2tp/l2tp_client.h.
 */

#include <stddef.h>
#include <stdint.h>
#include "l2tp/l2tp_client.h"

/* Vendored lwIP PPP stack options/override must precede ppp_impl.h */
#include "netif/ppp/ppp_opts.h"
#include "luat_ppp_opts_override.h"
#include "netif/ppp/ppp_impl.h"

#ifdef __cplusplus
extern "C" {
#endif

extern const struct link_callbacks l2tp_callbacks;

void l2tp_ppp_status_cb(ppp_pcb *ppp, int err_code, void *ctx);

#ifdef __cplusplus
}
#endif
