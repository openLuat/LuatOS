//
// Copyright (c) 2022 ZettaScale Technology
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0, or the Apache License, Version 2.0
// which is available at https://www.apache.org/licenses/LICENSE-2.0.
//
// SPDX-License-Identifier: EPL-2.0 OR Apache-2.0
//
// Contributors:
//   ZettaScale Zenoh Team, <zenoh@zettascale.tech>
//

#ifndef INCLUDE_ZENOH_PICO_CONFIG_H
#define INCLUDE_ZENOH_PICO_CONFIG_H

#ifdef ZENOH_GENERIC
#include <zenoh_generic_config.h>
#else

/*--- CMake generated config; pass values to CMake to change the following tokens ---*/
#define Z_FRAG_MAX_SIZE 8192
#define Z_BATCH_UNICAST_SIZE 2048
#define Z_BATCH_MULTICAST_SIZE 2048
#define Z_CONFIG_SOCKET_TIMEOUT 100
#define Z_TRANSPORT_LEASE 10000
#define Z_TRANSPORT_LEASE_EXPIRE_FACTOR 3
/* 1.9.0 executor.c默认64，必须与runtime.h保持相同布局。 */
#define Z_RUNTIME_MAX_TASKS 64
#define Z_TRANSPORT_ACCEPT_TIMEOUT 1000
#define Z_TRANSPORT_CONNECT_TIMEOUT 3000

/* Stable API only. */
#define Z_FEATURE_CONNECTIVITY 0
#define Z_FEATURE_MULTI_THREAD 0
#define Z_FEATURE_PUBLICATION 1
#define Z_FEATURE_ADVANCED_PUBLICATION 0
#define Z_FEATURE_SUBSCRIPTION 1
#define Z_FEATURE_ADVANCED_SUBSCRIPTION 0
#define Z_FEATURE_QUERY 1
#define Z_FEATURE_QUERYABLE 1
#define Z_FEATURE_LIVELINESS 0
#define Z_FEATURE_RAWETH_TRANSPORT 0
#define Z_FEATURE_INTEREST 0
#define Z_FEATURE_LINK_TCP 1
#define Z_FEATURE_LINK_BLUETOOTH 0
#define Z_FEATURE_LINK_WS 0
#define Z_FEATURE_LINK_SERIAL 0
#define Z_FEATURE_LINK_SERIAL_USB 0
#define Z_FEATURE_LINK_TLS 0
#define Z_FEATURE_SCOUTING 0
#define Z_FEATURE_LINK_UDP_MULTICAST 0
#define Z_FEATURE_LINK_UDP_UNICAST 0
#define Z_FEATURE_MULTICAST_TRANSPORT 0
#define Z_FEATURE_UNICAST_TRANSPORT 1
#define Z_FEATURE_FRAGMENTATION 1
#define Z_FEATURE_ENCODING_VALUES 0
#define Z_FEATURE_TCP_NODELAY 1
#define Z_FEATURE_LOCAL_SUBSCRIBER 0
#define Z_FEATURE_LOCAL_QUERYABLE 0
#define Z_FEATURE_SESSION_CHECK 1
#define Z_FEATURE_BATCHING 1
#define Z_FEATURE_BATCH_TX_MUTEX 0
#define Z_FEATURE_BATCH_PEER_MUTEX 0
#define Z_FEATURE_MATCHING 0
#define Z_FEATURE_RX_CACHE 0
#define Z_FEATURE_UNICAST_PEER 0
#define Z_FEATURE_AUTO_RECONNECT 0
#define Z_FEATURE_MULTICAST_DECLARATIONS 0
#define Z_FEATURE_ADMIN_SPACE 0

// End of CMake generation

#endif /* ZENOH_GENERIC */

/*------------------ Runtime configuration properties ------------------*/
/**
 * The library mode.
 * Accepted values : `"client"`, `"peer"`.
 * Default value : `"client"`.
 */
#define Z_CONFIG_MODE_KEY 0x40
#define Z_CONFIG_MODE_CLIENT "client"
#define Z_CONFIG_MODE_PEER "peer"
#define Z_CONFIG_MODE_DEFAULT Z_CONFIG_MODE_CLIENT

/**
 * The locator of a peer to connect to.
 * Accepted values : `<locator>` (ex: `"tcp/10.10.10.10:7447"`).
 * Default value : None.
 * Multiple values are accepted in peer to peer unicast mode.
 */
#define Z_CONFIG_CONNECT_KEY 0x41

/**
 * A locator to listen on.
 * Accepted values : `<locator>` (ex: `"tcp/10.10.10.10:7447"`).
 * Default value : None.
 * Multiple values are not accepted in zenoh-pico.
 */
#define Z_CONFIG_LISTEN_KEY 0x42

/**
 * The user name to use for authentication.
 * Accepted values : `<string>`.
 * Default value : None.
 */
#define Z_CONFIG_USER_KEY 0x43

/**
 * The password to use for authentication.
 * Accepted values : `<string>`.
 * Default value : None.
 */
#define Z_CONFIG_PASSWORD_KEY 0x44

/**
 * Activates/Deactivates multicast scouting.
 * Accepted values : `false`, `true`.
 * Default value : `true`.
 */
#define Z_CONFIG_MULTICAST_SCOUTING_KEY 0x45
#define Z_CONFIG_MULTICAST_SCOUTING_DEFAULT "true"

/**
 * The multicast address and ports to use for multicast scouting.
 * Accepted values : `<ip address>:<port>`.
 * Default value : `"224.0.0.224:7446"`.
 */
#define Z_CONFIG_MULTICAST_LOCATOR_KEY 0x46
#define Z_CONFIG_MULTICAST_LOCATOR_DEFAULT "udp/224.0.0.224:7446"

/**
 * In client mode, the period dedicated to scouting a router before failing.
 * Accepted values : `<int in milliseconds>`.
 * Default value : `"1000"`.
 */
#define Z_CONFIG_SCOUTING_TIMEOUT_KEY 0x47
#define Z_CONFIG_SCOUTING_TIMEOUT_DEFAULT "1000"

/**
 * The entities to find in the multicast scouting, defined as a bitwise value.
 * Accepted values : [0-7]. Bitwise value are defined in :c:enum:`z_whatami_t`.
 * Default value : `3`.
 */
#define Z_CONFIG_SCOUTING_WHAT_KEY 0x48
#define Z_CONFIG_SCOUTING_WHAT_DEFAULT "3"

/**
 * A configurable and static Zenoh ID to be used on Zenoh Sessions.
 * Accepted values : `<UUDI 128-bit>`.
 */
#define Z_CONFIG_SESSION_ZID_KEY 0x49

/**
 * Indicates if data messages should be timestamped.
 * Accepted values : `false`, `true`.
 * Default value : `false`.
 */
#define Z_CONFIG_ADD_TIMESTAMP_KEY 0x4A
#define Z_CONFIG_ADD_TIMESTAMP_DEFAULT "false"

/*------------------ TLS configuration properties ------------------*/
#define Z_CONFIG_TLS_ROOT_CA_CERTIFICATE_KEY 0x4B
#define Z_CONFIG_TLS_ROOT_CA_CERTIFICATE_BASE64_KEY 0x4C
#define Z_CONFIG_TLS_LISTEN_PRIVATE_KEY_KEY 0x4D
#define Z_CONFIG_TLS_LISTEN_PRIVATE_KEY_BASE64_KEY 0x4E
#define Z_CONFIG_TLS_LISTEN_CERTIFICATE_KEY 0x4F
#define Z_CONFIG_TLS_LISTEN_CERTIFICATE_BASE64_KEY 0x50
#define Z_CONFIG_TLS_ENABLE_MTLS_KEY 0x51
#define Z_CONFIG_TLS_CONNECT_PRIVATE_KEY_KEY 0x52
#define Z_CONFIG_TLS_CONNECT_PRIVATE_KEY_BASE64_KEY 0x53
#define Z_CONFIG_TLS_CONNECT_CERTIFICATE_KEY 0x54
#define Z_CONFIG_TLS_CONNECT_CERTIFICATE_BASE64_KEY 0x55
#define Z_CONFIG_TLS_VERIFY_NAME_ON_CONNECT_KEY 0x56

/*------------------ Compile-time configuration properties ------------------*/
/**
 * Default length for Zenoh ID. Maximum size is 16 bytes.
 * This configuration will only be applied to Zenoh IDs generated by Zenoh-Pico.
 */
#define Z_ZID_LENGTH 16

/**
 * Protocol version identifier.
 * Do not change this value.
 */
#define Z_PROTO_VERSION 0x09

/**
 * Default multicast session join interval in milliseconds.
 */
#define Z_JOIN_INTERVAL 2500

#define Z_SN_RESOLUTION 0x02
#define Z_REQ_RESOLUTION 0x02

/**
 * Default size for the rx cache size (if activated).
 */
#define Z_RX_CACHE_SIZE 10

/**
 * Default get timeout in milliseconds.
 */
#define Z_GET_TIMEOUT_DEFAULT 10000

/**
 * Maximum number of connections for unicast listen sockets.
 */
#define Z_LISTEN_MAX_CONNECTION_NB 10

/**
 * Default "nop" instruction
 */
#define ZP_ASM_NOP __asm__("nop")

#endif /* INCLUDE_ZENOH_PICO_CONFIG_H */
