#pragma once

/*
 * Internal OpenVPN data-channel crypto prototypes (ovpn_crypto.c).
 * Module-internal only; the public OpenVPN client API lives in
 * ovpn/ovpn_client.h.
 */

#include <stdint.h>
#include "ovpn/ovpn_client.h"

#ifdef __cplusplus
extern "C" {
#endif

void ovpn_export_keys(ovpn_client_t *cli);

#ifdef __cplusplus
}
#endif
