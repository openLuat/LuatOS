#pragma once

#include <stddef.h>
#include <stdint.h>
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "luat_network_adapter.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/pk.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/gcm.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ========== OpenVPN protocol constants ========== */

/* Opcodes (upper 5 bits of first byte) */
#define OVPN_OP_CONTROL_HARD_RESET_CLIENT_V2  7
#define OVPN_OP_CONTROL_HARD_RESET_SERVER_V2  8
#define OVPN_OP_CONTROL_V1                    4
#define OVPN_OP_ACK_V1                        5
#define OVPN_OP_DATA_V1                       6
#define OVPN_OP_DATA_V2                       9
#define OVPN_OP_SOFT_RESET_V1                 3

/* Key ID mask and opcode shift */
#define OVPN_KEY_ID_MASK   0x07
#define OVPN_OPCODE_SHIFT  3

/* Session ID size (64-bit) */
#define OVPN_SID_SIZE      8

/* Reliable layer */
#define OVPN_REL_SEND_SIZE  4   /* send window slots */
#define OVPN_REL_RECV_SIZE  4   /* receive window slots */
#define OVPN_MAX_ACKS       4   /* max ACKs per CONTROL_V1 */
#define OVPN_MAX_ACKS_ACK   8   /* max ACKs per standalone ACK_V1 */

/* Data channel (AES-256-GCM) */
#define OVPN_NONCE_TAIL_LEN     8   /* implicit nonce tail */
#define OVPN_AUTH_TAG_LEN       16  /* GCM auth tag */
#define OVPN_AEAD_IV_LEN        12  /* AES-GCM IV length */
#define OVPN_EKM_LEN            256 /* key2 export length */
#define OVPN_KEY_CIPHER_LEN     64  /* struct key cipher length */
#define OVPN_KEY_HMAC_LEN       64  /* struct key hmac length */

/* Key method 2 constants */
#define OVPN_KEY_METHOD_2       2
#define OVPN_PRE_MASTER_LEN     48
#define OVPN_RANDOM_LEN         32
#define OVPN_TLS_OPTIONS_LEN    256
#define OVPN_PEER_INFO_MAX_LEN  256

/* Tunnel default MTU */
#define OVPN_TUN_MTU_DEFAULT  1500

/* Protocol timers (ms) */
#define OVPN_HANDSHAKE_TIMEOUT_MS  30000
#define OVPN_PING_INTERVAL_MS      10000
#define OVPN_DEAD_INTERVAL_MS      30000
#define OVPN_RETRANSMIT_BASE_MS    1000
#define OVPN_RETRANSMIT_MAX_MS     8000
#define OVPN_TICK_INTERVAL_MS       250  /* periodic tick for retransmit checks */

/* Event types for OpenVPN client state */
typedef enum {
    OVPN_EVENT_CONNECTED = 0,      /* Connection established */
    OVPN_EVENT_TLS_HANDSHAKE_OK,   /* TLS handshake succeeded */
    OVPN_EVENT_TLS_HANDSHAKE_FAIL, /* TLS handshake failed */
    OVPN_EVENT_KEEPALIVE_TIMEOUT,  /* Keepalive timeout (30s no response) */
    OVPN_EVENT_AUTH_FAILED,        /* Authentication failed */
    OVPN_EVENT_DISCONNECTED,       /* Connection closed */
    OVPN_EVENT_DATA_RX,            /* Data packet received */
    OVPN_EVENT_DATA_TX,            /* Data packet sent */
} ovpn_event_t;

/* Event callback function type */
typedef void (*ovpn_event_cb_t)(ovpn_event_t event, void *user_data);

/* Key source material for key_method_2 exchange.
 * Reference: openvpn/src/openvpn/ssl_common.h struct key_source2
 * Client has pre_master + random1 + random2. Server has random1 + random2 only. */
typedef struct {
    uint8_t pre_master[OVPN_PRE_MASTER_LEN];    /* client only, 48 bytes */
    uint8_t client_random1[OVPN_RANDOM_LEN];    /* client's random1 */
    uint8_t client_random2[OVPN_RANDOM_LEN];    /* client's random2 */
    uint8_t server_random1[OVPN_RANDOM_LEN];    /* server's random1 */
    uint8_t server_random2[OVPN_RANDOM_LEN];    /* server's random2 */
} ovpn_key_source2_t;

/* Key method 2 exchange state (TLS app-data phase) */
typedef enum {
    OVPN_KM2_NONE = 0,       /* not started */
    OVPN_KM2_WAIT_SEND,      /* need to send key_method_2 to server */
    OVPN_KM2_SENDING,        /* sending KM2 (deferred to timer tick) */
    OVPN_KM2_WAIT_REPLY,     /* sent, awaiting server response */
    OVPN_KM2_DONE,           /* exchange complete, keys can be derived */
} ovpn_km2_state_t;

/* Client configuration */
typedef struct {
    ip_addr_t   remote_ip;
    uint16_t    remote_port;
    uint8_t     adapter_index;
    uint16_t    tun_mtu;
    const char *ca_cert_pem;
    size_t      ca_cert_len;
    const char *client_cert_pem;
    size_t      client_cert_len;
    const char *client_key_pem;
    size_t      client_key_len;
    const char *username;        /* optional, for auth-user-pass */
    size_t      username_len;    /* 0 if no username */
    const char *password;        /* optional, for auth-user-pass */
    size_t      password_len;    /* 0 if no password */
    uint8_t     retry_enable;
    uint32_t    retry_base_ms;
    uint32_t    retry_max_ms;
    uint8_t     transport_index; /* 底层传输网卡编号，用于 network_alloc_ctrl */
    ovpn_event_cb_t event_cb;
    void       *user_data;
} ovpn_client_cfg_t;

/* Statistics */
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

/* Reliable send slot */
typedef struct {
    uint8_t  in_use;
    uint32_t id;
    uint32_t retransmit_at;
    uint8_t *data;
    uint16_t len;
} ovpn_rel_slot_t;

/* Reliable recv slot */
typedef struct {
    uint8_t  in_use;
    uint32_t id;
    uint8_t *data;
    uint16_t len;
} ovpn_rel_recv_slot_t;

/* Client state */
typedef enum {
    OVPN_STATE_IDLE,
    OVPN_STATE_RESET_SENT,       /* sent P_CONTROL_HARD_RESET_CLIENT_V2 */
    OVPN_STATE_RESET_ACKED,      /* received server reset, sent ACK */
    OVPN_STATE_HANDSHAKE,        /* TLS handshake in progress */
    OVPN_STATE_ACTIVE,           /* connected (keys derived, PUSH received) */
    OVPN_STATE_ERROR,
} ovpn_state_t;

/* PUSH reply info (minimal) */
typedef struct {
    uint8_t  received;
    uint8_t  tun_ip[4];
    uint8_t  tun_mask[4];
    uint8_t  tun_gw[4];
    uint8_t  use_comp_stub;  /* server expects NO_COMPRESS byte (0xFA) before each packet */
} ovpn_push_reply_t;

typedef struct ovpn_client {
    /* Network interface & transport */
    struct netif netif;
    network_ctrl_t *netc;          /* luat_network_adapter transport control */
    ip_addr_t remote_ip;
    uint16_t remote_port;
    uint16_t mtu;
    uint8_t adapter_index;         /* 虚拟网卡编号（用于 net_lwip2 注册） */
    uint8_t transport_index;       /* 底层传输网卡编号（用于 network_alloc_ctrl） */
    uint8_t started;
    uint8_t debug;

    /* Session IDs (64-bit each) */
    uint8_t session_id[OVPN_SID_SIZE];
    uint8_t peer_session_id[OVPN_SID_SIZE];
    uint8_t peer_session_id_valid;

    /* State machine */
    ovpn_state_t state;

    /* Reliable send window */
    uint32_t rel_next_seq;
    ovpn_rel_slot_t rel_send[OVPN_REL_SEND_SIZE];

    /* Reliable recv window */
    uint32_t rel_recv_next;
    ovpn_rel_recv_slot_t rel_recv[OVPN_REL_RECV_SIZE];
    uint32_t pending_acks[OVPN_MAX_ACKS];
    uint8_t  pending_ack_count;

    /* Timer management */
    uint32_t last_activity_ms;
    uint32_t handshake_start_ms;
    uint8_t  handshake_failed;
    uint8_t  tls_handshake_done; /* TLS handshake completed */
    uint8_t  retry_enabled;
    uint8_t  retry_timer_active;
    uint32_t retry_attempt;
    uint32_t retry_base_ms;
    uint32_t retry_max_ms;
    uint8_t  transport_err;      /* non-zero: transport socket error, handled in timer tick */
    uint32_t push_sent_ms;       /* when PUSH_REQUEST was last sent */

    /* Key method 2 exchange */
    ovpn_key_source2_t key_src;  /* random material for KM2 */
    ovpn_km2_state_t   km2_state;

    /* TLS context (control channel) */
    uint8_t  use_tls;
    uint8_t  tls_ready;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_x509_crt ca;
    mbedtls_x509_crt client_cert;
    mbedtls_pk_context client_key;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_entropy_context entropy;

    /* TLS receive buffer - accumulates control channel data across packets */
    uint8_t tls_buf[4096];
    uint16_t tls_buf_len;
    uint16_t tls_buf_offset;
    /* Data channel crypto (AES-256-GCM) */
    mbedtls_gcm_context gcm_enc;
    mbedtls_gcm_context gcm_dec;
    uint8_t enc_implicit_iv[OVPN_AEAD_IV_LEN];  /* for encrypt: [0..3]=0, [4..11]=hmac[0..7] */
    uint8_t dec_implicit_iv[OVPN_AEAD_IV_LEN];  /* for decrypt */
    uint32_t data_tx_seq;
    uint32_t data_rx_seq;
    uint8_t  data_key_ready;
    uint8_t  peer_id;
    uint8_t  key_id;            /* current data channel key id */

    /* PUSH_REPLY info */
    ovpn_push_reply_t push_reply;

    /* Stats */
    ovpn_client_stats_t stats;

    /* Callbacks */
    ovpn_event_cb_t event_cb;
    void *user_data;

    /* Certificate & auth copies (heap, freed on stop) */
    uint8_t *ca_cert_buf;
    size_t ca_cert_len;
    uint8_t *client_cert_buf;
    size_t client_cert_len;
    uint8_t *client_key_buf;
    size_t client_key_len;
    uint8_t *username_buf;
    size_t username_len;
    uint8_t *password_buf;
    size_t password_len;
} ovpn_client_t;

/* API functions */
int ovpn_client_init(ovpn_client_t *cli, const ovpn_client_cfg_t *cfg);
int ovpn_client_start(ovpn_client_t *cli);
void ovpn_client_stop(ovpn_client_t *cli);
void ovpn_client_get_stats(ovpn_client_t *cli, ovpn_client_stats_t *out);
void ovpn_client_set_debug(ovpn_client_t *cli, int enable);
void ovpn_client_timer_tick(ovpn_client_t *cli);   /* periodic timer callback */
void ovpn_client_poll(ovpn_client_t *cli);          /* poll for outgoing data */
int  ovpn_client_is_ready(ovpn_client_t *cli);      /* TLS + push done */

/* UDP receive callback (called from network adapter context) */
void ovpn_client_udp_recv(ovpn_client_t *cli, const uint8_t *data, uint16_t len, ip_addr_t *addr, uint16_t port);

/* ========== Internal cross-file API (module-internal, not for Lua) ========== */

/* Raw UDP transport (ovpn_client.c); shared with the reliable and control
 * layers (ovpn_rel.c / ovpn_ctl.c). */
int ovpn_send_udp(ovpn_client_t *cli, const uint8_t *data, int len);

#ifdef __cplusplus
}
#endif
