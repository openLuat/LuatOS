/**
 * \file ipsec_ike.h
 *
 * \brief IKEv2 initiator (RFC 7296) core for LuatOS netdrv.
 *
 * Tunnel mode only: EAP-MSCHAPv2 authentication, server certificate chain
 * verification, NAT-T (UDP 500 -> 4500), DPD, CHILD_SA rekey without PFS
 * and full IKE SA rebuild on expiry.  The virtual netif routes all traffic
 * through the tunnel; the transport is a single network adapter UDP socket
 * that carries both IKE (4-byte zero marker on 4500) and ESP-in-UDP (4500).
 */
#ifndef IPSEC_IKE_H
#define IPSEC_IKE_H

#include <stddef.h>
#include <stdint.h>

#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "luat_network_adapter.h"

#include "mbedtls/x509_crt.h"

#include "ipsec/ipsec_crypto.h"
#include "ipsec/ipsec_esp.h"

#ifdef __cplusplus
extern "C" {
#endif

#define IPSEC_IKE_PORT           500
#define IPSEC_ESP_PORT           4500
#define IPSEC_DEFAULT_MTU        1400

#define IPSEC_IKE_BUF_LEN        3200
#define IPSEC_IKE_TX_LEN         2048
#define IPSEC_NONCE_LEN          32
#define IPSEC_DH_PUB_LEN         256
#define IPSEC_MAX_USERNAME_LEN   255
#define IPSEC_MAX_PASSWORD_LEN   256
#define IPSEC_MAX_CA_PEM_LEN     16384

/* IKEv2 exchange types */
#define IPSEC_EXCH_IKE_SA_INIT       34
#define IPSEC_EXCH_IKE_AUTH          35
#define IPSEC_EXCH_CREATE_CHILD_SA   36
#define IPSEC_EXCH_INFORMATIONAL     37

/* Payload types */
#define IPSEC_PAYLOAD_SA             33
#define IPSEC_PAYLOAD_KE             34
#define IPSEC_PAYLOAD_IDI            35
#define IPSEC_PAYLOAD_IDR            36
#define IPSEC_PAYLOAD_CERT           37
#define IPSEC_PAYLOAD_CERTREQ        38
#define IPSEC_PAYLOAD_AUTH           39
#define IPSEC_PAYLOAD_NONCE          40
#define IPSEC_PAYLOAD_NOTIFY         41
#define IPSEC_PAYLOAD_DELETE         42
#define IPSEC_PAYLOAD_VENDOR         43
#define IPSEC_PAYLOAD_TSI            44
#define IPSEC_PAYLOAD_TSR            45
#define IPSEC_PAYLOAD_SK             46
#define IPSEC_PAYLOAD_CP             47
#define IPSEC_PAYLOAD_EAP            48

/* IKE header flags */
#define IPSEC_FLAG_RESPONSE          0x20
#define IPSEC_FLAG_VERSION           0x10
#define IPSEC_FLAG_INITIATOR         0x08

/* Identification types */
#define IPSEC_ID_IPV4_ADDR           1
#define IPSEC_ID_FQDN                2
#define IPSEC_ID_RFC822_ADDR         3
#define IPSEC_ID_IPV6_ADDR           5
#define IPSEC_ID_KEY_ID              11

/* Notify types */
#define IPSEC_NOTIFY_INITIAL_CONTACT      16384
#define IPSEC_NOTIFY_NAT_DETECTION_SOURCE 16388
#define IPSEC_NOTIFY_NAT_DETECTION_DEST   16389
#define IPSEC_NOTIFY_COOKIE               16390
#define IPSEC_NOTIFY_USE_TRANSPORT_MODE   16391
#define IPSEC_NOTIFY_UPDATE_SA_ADDRESSES  16392
#define IPSEC_NOTIFY_NO_PROPOSAL_CHOSEN   14
#define IPSEC_NOTIFY_INVALID_KE           17
#define IPSEC_NOTIFY_AUTH_FAILED          24
#define IPSEC_NOTIFY_INTERNAL_ADDR_FAIL   36
#define IPSEC_NOTIFY_TS_UNACCEPTABLE      38
#define IPSEC_NOTIFY_TEMPORARY_FAILURE    43
#define IPSEC_NOTIFY_CHILD_SA_NOT_FOUND   44

/* Protocol IDs */
#define IPSEC_PROTO_IKE            1
#define IPSEC_PROTO_ESP            3

/* Transform types */
#define IPSEC_TRANSFORM_ENCR       1
#define IPSEC_TRANSFORM_PRF        2
#define IPSEC_TRANSFORM_INTEG      3
#define IPSEC_TRANSFORM_DH         4
#define IPSEC_TRANSFORM_ESN        5

/* Transform IDs */
#define IPSEC_ENCR_AES_CBC         12
#define IPSEC_ENCR_AES_GCM_16      20
#define IPSEC_PRF_HMAC_SHA1        2
#define IPSEC_PRF_HMAC_SHA2_256    5
#define IPSEC_INTEG_HMAC_SHA1_96   2
#define IPSEC_INTEG_HMAC_SHA2_256_128 12
#define IPSEC_ESN_NONE             0

/* Auth methods */
#define IPSEC_AUTH_RSA             1
#define IPSEC_AUTH_SHARED_SECRET   2
#define IPSEC_AUTH_ECDSA_256       9
#define IPSEC_AUTH_ECDSA_384       10
#define IPSEC_AUTH_ECDSA_521       11
#define IPSEC_AUTH_DIGITAL_SIG     14

/* Configuration payload */
#define IPSEC_CFG_REQUEST          1
#define IPSEC_CFG_REPLY            2
#define IPSEC_CFG_INTERNAL_IP4_ADDRESS 1
#define IPSEC_CFG_INTERNAL_IP4_NETMASK 2
#define IPSEC_CFG_INTERNAL_IP4_DNS 3

/* EAP */
#define IPSEC_EAP_CODE_REQUEST     1
#define IPSEC_EAP_CODE_RESPONSE    2
#define IPSEC_EAP_CODE_SUCCESS     3
#define IPSEC_EAP_CODE_FAILURE     4
#define IPSEC_EAP_TYPE_IDENTITY    1
#define IPSEC_EAP_TYPE_MSCHAPV2    26

/* Certificate encoding: X.509 certificate (DER) */
#define IPSEC_CERT_X509            4

/* Timers (ms) */
#define IPSEC_RETRANS_BASE_MS      4000
#define IPSEC_RETRANS_MAX          5
#define IPSEC_DPD_INTERVAL_MS      30000
#define IPSEC_DPD_MAX_PENDING      4
#define IPSEC_KEEPALIVE_MS         20000
#define IPSEC_TICK_MS              1000
#define IPSEC_ESP_LIFETIME_MS      3600000
#define IPSEC_IKE_LIFETIME_MS      86400000
#define IPSEC_DYING_SA_GRACE_MS    60000

/* States */
enum {
    IPSEC_STATE_IDLE = 0,
    IPSEC_STATE_SA_INIT_SENT,
    IPSEC_STATE_AUTH1_SENT,
    IPSEC_STATE_EAP_SENT,
    IPSEC_STATE_AUTH2_SENT,
    IPSEC_STATE_ESTABLISHED,
    IPSEC_STATE_REKEY_SENT,
};

typedef struct ipsec_client ipsec_client_t;

typedef struct ipsec_client_cfg {
    ip_addr_t  remote_ip;
    uint16_t   remote_port;       /* IKE port, default 500 */
    char      *username;
    size_t     username_len;
    char      *password;
    size_t     password_len;
    char      *ca_cert_pem;       /* PEM trust anchor; required unless insecure mode */
    size_t     ca_cert_pem_len;
    char      *san;               /* expected server SAN */
    uint8_t    insecure_cert_ok;   /* allow missing CA after SAN check */
    uint16_t   mtu;
    uint8_t    adapter_index;
    uint8_t    transport_index;
    uint8_t    retry_enable;
    uint8_t    ipsec_mobike_enable;
    uint32_t   retry_base_ms;
    uint32_t   retry_max_ms;
    /* status callback: err_code == 0 -> tunnel ready, else link down */
    void (*status_cb)(ipsec_client_t *cli, int err_code, void *user_data);
    void *user_data;
} ipsec_client_cfg_t;

/* Received datagram (adapter thread -> tcpip thread) */
typedef struct ipsec_rx_msg {
    ipsec_client_t *cli;
    luat_ip_addr_t src_addr;
    uint16_t src_port;
    uint16_t len;
    uint8_t data[4];
} ipsec_rx_msg_t;

struct ipsec_client {
    /* config (strings owned by glue, copied at init) */
    ip_addr_t  remote_ip;
    uint16_t   remote_port;
    uint16_t   ike_port;          /* current IKE port (500 / 4500) */
    uint16_t   mtu;
    uint8_t    adapter_index;
    uint8_t    transport_index;
    uint8_t    retry_enable;
    uint32_t   retry_base_ms;
    uint32_t   retry_max_ms;
    char      *username;
    size_t     username_len;
    char      *password;
    size_t     password_len;
    char      *ca_cert_pem;
    size_t     ca_cert_pem_len;
    char      *san;
    uint8_t    insecure_cert_ok;

    /* transport */
    network_ctrl_t *netc;
    volatile uint8_t transport_err;
    uint8_t started;
    uint8_t debug;
    uint8_t user_close;
    uint8_t tearing_down;
    uint8_t netif_added;

    /* IKE state */
    uint8_t  phase;
    uint32_t msgid;               /* next request message id (RFC 7296: 32-bit, monotonic) */
    uint32_t pending_msgid;
    uint8_t  last_exchange;       /* exchange type of the pending request */
    uint8_t  nat_detected;
    uint8_t  cookie_len;
    uint8_t  cookie[64];
    uint8_t  spii[8];
    uint8_t  spir[8];
    uint8_t  ni[IPSEC_NONCE_LEN];
    uint16_t ni_len;
    uint8_t  nr[IPSEC_NONCE_LEN];
    uint16_t nr_len;
    uint8_t  kei[IPSEC_DH_PUB_LEN];
    uint16_t kei_len;
    uint8_t  ker[IPSEC_DH_PUB_LEN];
    uint16_t ker_len;
    uint8_t  g_ir[IPSEC_DH_PUB_LEN];
    uint16_t g_ir_len;
    uint16_t ike_dh_group;        /* negotiated IKE DH group (default 14) */
    ipsec_dh_ctx_t ike_dh;        /* IKE_SA_INIT DH context */
    ipsec_dh_ctx_t child_dh;      /* CREATE_CHILD_SA (PFS) DH context */

    /* negotiated IKE algorithms + keys */
    uint8_t  ike_prf;
    uint8_t  ike_enc;
    uint8_t  ike_integ;
    uint8_t  sk_d[32], sk_ai[32], sk_ar[32], sk_ei[32], sk_er[32];
    uint8_t  sk_pi[32], sk_pr[32];
    uint8_t  keys_valid;

    /* saved messages for AUTH computation */
    uint8_t  sa_init_tx[IPSEC_IKE_TX_LEN];
    uint16_t sa_init_tx_len;
    uint8_t  sa_init_rx[IPSEC_IKE_BUF_LEN];
    uint16_t sa_init_rx_len;
    uint8_t  idr_rest[64];        /* IDr payload body (type+reserved+data) */
    uint16_t idr_rest_len;
    uint8_t  idi_rest[64];        /* IDi payload body we sent */
    uint16_t idi_rest_len;

    /* server certificate */
    mbedtls_x509_crt server_cert;
    uint8_t  server_cert_valid;
    uint8_t  auth_received;       /* server AUTH (msg 4) verified */

    /* EAP-MSCHAPv2 */
    uint8_t  eap_id;
    uint8_t  mschap_peer_challenge[16];
    uint8_t  mschap_nt_response[24];
    uint8_t  msk[64];
    uint8_t  msk_valid;
    char     mschap_auth_response[41];
    uint8_t  mschap_ready;
    uint8_t  eap_identity_sent;

    /* retransmission */
    uint8_t  retrans_count;
    uint8_t  last_tx[IPSEC_IKE_TX_LEN];
    uint16_t last_tx_len;

    /* ESP SAs (two slots: current + dying) */
    ipsec_esp_sa_t esp_in[2];
    ipsec_esp_sa_t esp_out[2];
    uint8_t  esp_slot;
    uint32_t esp_spi_out;
    uint8_t  esp_enc;             /* IPSEC_ENC_AES* */
    uint8_t  esp_integ;
    uint8_t  esp_rekey_inflight;
    uint8_t  rekey_no_ke;         /* rekey retry without KE (PFS fallback) */

    /* MOBIKE (opt-in, default off) */
    uint8_t  mobike_enable;
    ip4_addr_t local_ip_cache;
    uint8_t  mobike_inflight;
    uint8_t  mobike_cache_valid;

    /* virtual iface config from CP */
    ip4_addr_t v4;
    ip4_addr_t v4mask;
    ip_addr_t dns1, dns2;
    uint8_t  cfg_ready;
    uint8_t  online;
    struct netif netif;

    /* liveness / timers */
    uint8_t  dpd_pending;
    uint32_t dpd_sent_ms;
    uint32_t last_rx_ms;
    uint32_t online_ms;
    uint32_t esp_created_ms;
    uint8_t  retry_timer_active;
    uint32_t retry_attempt;
    uint32_t esp_sa_created_ms[2];

    void (*status_cb)(ipsec_client_t *cli, int err_code, void *user_data);
    void *user_data;
};

/* API */
int  ipsec_client_init(ipsec_client_t *cli, const ipsec_client_cfg_t *cfg);
int  ipsec_client_start(ipsec_client_t *cli);
void ipsec_client_stop(ipsec_client_t *cli);
void ipsec_client_deinit(ipsec_client_t *cli);
void ipsec_client_set_debug(ipsec_client_t *cli, int enable);
int  ipsec_client_is_ready(ipsec_client_t *cli);

/* Test hook: flip the cached local address and trigger the MOBIKE update
 * flow (utest builds only; no-op when MOBIKE is disabled). */
int ipsec_client_test_simulate_addr_change(ipsec_client_t *cli);

#ifdef __cplusplus
}
#endif

#endif /* IPSEC_IKE_H */
