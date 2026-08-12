#pragma once

/*
 * Internal OpenVPN TLS-channel prototypes (ovpn_tls.c).  Module-internal
 * only; the public OpenVPN client API lives in ovpn/ovpn_client.h.
 */

#include <stdint.h>
#include "ovpn/ovpn_client.h"

#ifdef __cplusplus
extern "C" {
#endif

int ovpn_tls_init(ovpn_client_t *cli, const ovpn_client_cfg_t *cfg);
void ovpn_tls_free(ovpn_client_t *cli);
void ovpn_feed_tls(ovpn_client_t *cli, const uint8_t *data, int len);

#ifdef __cplusplus
}
#endif
