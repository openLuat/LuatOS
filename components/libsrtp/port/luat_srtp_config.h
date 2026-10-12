/* Force-include this uniquely named header for libsrtp translation units. */
#ifndef LUAT_LIBSRTP_FORCE_CONFIG_H
#define LUAT_LIBSRTP_FORCE_CONFIG_H
/* Quoted include resolves against this file, never another component's config.h. */
#define HAVE_CONFIG_H 1
#include "config.h"

/* Upstream aes_icm_mbedtls.c defines the 192-bit table unconditionally,
 * while cipher_types.h declares it only with GCM. Supply the missing
 * forward declaration for our non-GCM build without enabling another suite. */
extern const struct srtp_cipher_type_t srtp_aes_icm_192;
#endif
