#pragma once

#include <stddef.h>
#include <stdint.h>
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/pk.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Event types for OpenVPN client state */
typedef enum {
    OVPN_EVENT_CONNECTED = 0,      /* Connection established */
    OVPN_EVENT_TLS_HANDSHAKE_OK,   /* TLS/DTLS handshake succeeded */
    OVPN_EVENT_TLS_HANDSHAKE_FAIL, /* TLS/DTLS handshake failed */
    OVPN_EVENT_KEEPALIVE_TIMEOUT,  /* Keepalive timeout (30s no response) */
    OVPN_EVENT_AUTH_FAILED,        /* HMAC authentication failed */
    OVPN_EVENT_DISCONNECTED,       /* Connection closed */
    OVPN_EVENT_DATA_RX,            /* Data packet received (optional, for activity indication) */
    OVPN_EVENT_DATA_TX,            /* Data packet sent (optional, for activity indication) */
} ovpn_event_t;

/* Event callback function type */
typedef void (*ovpn_event_cb_t)(ovpn_event_t event, void *user_data);

typedef struct {
    ip_addr_t   remote_ip;        // required for now (UDP only)
    uint16_t    remote_port;      // server port
    uint8_t     adapter_index;    // defaults to NW_ADAPTER_INDEX_LWIP_USER0
    uint16_t    tun_mtu;          // defaults to 1500
    const char *ca_cert_pem;      // CA certificate (PEM)
    size_t      ca_cert_len;
    const char *client_cert_pem;  // client certificate (PEM)
    size_t      client_cert_len;
    const char *client_key_pem;   // client private key (PEM)
    size_t      client_key_len;
    uint8_t     retry_enable;     // enable retry
    uint32_t    retry_base_ms;    // base delay
    uint32_t    retry_max_ms;     // max delay
    ovpn_event_cb_t event_cb;     // Event callback function (optional)
    void       *user_data;        // User-defined data passed to callback
} ovpn_client_cfg_t;

typedef struct {
    uint64_t tx_pkts;
    uint64_t tx_bytes;
    uint64_t rx_pkts;
    uint64_t rx_bytes;
    uint64_t drop_auth;
    uint64_t drop_replay;
    uint64_t drop_malformed;
    uint64_t ping_sent;
    uint64_t ping_recv;
} ovpn_client_stats_t;

typedef struct ovpn_client {
    struct netif netif;
    struct udp_pcb *udp;
    ip_addr_t remote_ip;
    uint16_t remote_port;
    uint16_t mtu;
    uint8_t adapter_index;
    uint8_t started;
    uint32_t tx_seq;
    uint32_t rx_max_seq;
    uint32_t rx_window;
    uint8_t rx_initialized;
    uint32_t last_activity_ms;
    uint32_t last_ping_ms;
    uint32_t handshake_start_ms;
    uint8_t handshake_failed;
    uint8_t retry_enabled;
    uint8_t retry_timer_active;
    uint32_t retry_attempt;
    uint32_t retry_base_ms;
    uint32_t retry_max_ms;
    ovpn_client_stats_t stats;
    uint8_t debug;
    uint8_t use_tls;
    uint8_t tls_ready;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_x509_crt ca;
    mbedtls_x509_crt client_cert;
    mbedtls_pk_context client_key;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_entropy_context entropy;
    struct {
        struct pbuf *pkt;    /* pending UDP packet for DTLS read */
        uint16_t offset;
    } rx_pending;
    struct {
        uint32_t int_ms;
        uint32_t fin_ms;
    } dtls_timer;
    uint8_t *tls_buf;        /* Pre-allocated TLS temporary buffer (1600 bytes) */
    ovpn_event_cb_t event_cb; /* Event callback function */
    void *user_data;         /* User-defined data */
    /* Certificate data copies (copied from Lua stack to prevent garbage collection) */
    uint8_t *ca_cert_buf;    /* CA certificate copy */
    size_t ca_cert_len;
    uint8_t *client_cert_buf; /* Client certificate copy */
    size_t client_cert_len;
    uint8_t *client_key_buf; /* Client private key copy */
    size_t client_key_len;
} ovpn_client_t;

int ovpn_client_init(ovpn_client_t *cli, const ovpn_client_cfg_t *cfg);
int ovpn_client_start(ovpn_client_t *cli);
void ovpn_client_stop(ovpn_client_t *cli);
void ovpn_client_get_stats(ovpn_client_t *cli, ovpn_client_stats_t *out);
void ovpn_client_set_debug(ovpn_client_t *cli, int enable);

#ifdef __cplusplus
}
#endif
