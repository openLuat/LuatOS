#include "luat_netdrv_openvpn_client.h"

#include <string.h>
#include "lwip/def.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"
#include "lwip/ip4.h"
#include "lwip/tcpip.h"
#include "lwip/timeouts.h"
#include "lwip/sys.h"
#include "net_lwip2.h"
#include "luat_malloc.h"
#include "luat_crypto.h"
#include "mbedtls/md.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/pk.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"

#define LUAT_LOG_TAG "openvpn"
#include "luat_log.h"
#include "luat_network_adapter.h"

/* lwIP version compatibility handling */
#include "lwip/opt.h"

/* lwIP 2.0 compatibility: IP4_ADDR_ANY4 */
#ifndef IP4_ADDR_ANY4
#define IP4_ADDR_ANY4 IP_ADDR_ANY
#endif

/* lwIP 2.0 compatibility: IPADDR_TYPE_ANY */
#ifndef IPADDR_TYPE_ANY
#if LWIP_IPV6
#define IPADDR_TYPE_ANY IPADDR_TYPE_V4
#else
#define IPADDR_TYPE_ANY IPADDR_TYPE_V4
#endif
#endif

/* lwIP 2.0 compatibility: IPADDR_ANY_TYPE_INIT */
#ifndef IPADDR_ANY_TYPE_INIT
#if LWIP_IPV6
#define IPADDR_ANY_TYPE_INIT { IPADDR_TYPE_V4 }
#else
#define IPADDR_ANY_TYPE_INIT { 0 }
#endif
#endif

/* mbedtls version compatibility: check handshake state */
/* mbedtls 2.x: ssl.state is public field, mbedtls 3.x: use MBEDTLS_PRIVATE() macro to access private fields */
#if !defined(MBEDTLS_PRIVATE)
#define MBEDTLS_PRIVATE(x) x
#endif

/* mbedtls handshake complete state value */
#if !defined(MBEDTLS_SSL_HANDSHAKE_OVER)
/* If not defined, try to define as common value */
#define MBEDTLS_SSL_HANDSHAKE_OVER 0
#endif

/* lwIP 2.1 compatibility: NETIF_FLAG_POINTTOPOINT may not exist */
#ifndef NETIF_FLAG_POINTTOPOINT
#define NETIF_FLAG_POINTTOPOINT 0
#endif

/* lwIP 2.1 compatibility: NETIF_FLAG_NOARP may not exist in older versions */
#ifndef NETIF_FLAG_NOARP
#define NETIF_FLAG_NOARP 0
#endif

#ifndef OVPN_MAX_KEY_LEN
#define OVPN_MAX_KEY_LEN 64
#endif

#define OVPN_HMAC_LEN 32
#define OVPN_REPLAY_WINDOW 32
#define OVPN_PING_INTERVAL_MS 10000
#define OVPN_DEAD_INTERVAL_MS 30000
#define OVPN_FLAG_PING 0x01
#define OVPN_FLAG_PONG 0x02

struct ovpn_data_hdr {
    uint32_t seq;
    uint16_t len;
    uint8_t  flags;
    uint8_t  rsv;
};

static err_t ovpn_netif_output_ip4(struct netif *n, struct pbuf *p, const ip4_addr_t *addr);
#if LWIP_IPV6
static err_t ovpn_netif_output_ip6(struct netif *n, struct pbuf *p, const ip6_addr_t *addr);
#endif
static void ovpn_udp_recv(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port);
static err_t ovpn_netif_init(struct netif *n);
static err_t ovpn_send_frame(ovpn_client_t *cli, struct pbuf *payload, uint8_t flags);
static int ovpn_hmac(const ovpn_client_t *cli, const uint8_t *hdr, size_t hdr_len, const uint8_t *payload, size_t payload_len, uint8_t *out);
static int ovpn_replay_accept(ovpn_client_t *cli, uint32_t seq);
static void ovpn_ping_timer(void *arg);
static int ovpn_tls_init(ovpn_client_t *cli, const ovpn_client_cfg_t *cfg);
static void ovpn_tls_free(ovpn_client_t *cli);
static int ovpn_tls_udp_send(void *ctx, const unsigned char *buf, size_t len);
static int ovpn_tls_udp_recv(void *ctx, unsigned char *buf, size_t len);
static void ovpn_tls_process_rx(ovpn_client_t *cli);

int ovpn_client_init(ovpn_client_t *cli, const ovpn_client_cfg_t *cfg) {
    if (!cli || !cfg) {
        return -1;
    }
    memset(cli, 0, sizeof(*cli));
    cli->remote_ip = cfg->remote_ip;
    cli->remote_port = cfg->remote_port;
    cli->adapter_index = cfg->adapter_index ? cfg->adapter_index : NW_ADAPTER_INDEX_LWIP_USER0;
    cli->mtu = cfg->tun_mtu ? cfg->tun_mtu : 1500;
    if (cfg->static_key && cfg->static_key_len) {
        cli->key_len = (cfg->static_key_len > OVPN_MAX_KEY_LEN) ? OVPN_MAX_KEY_LEN : cfg->static_key_len;
        memcpy(cli->key, cfg->static_key, cli->key_len);
    }
    cli->event_cb = cfg->event_cb;
    cli->user_data = cfg->user_data;
    
    if (cfg->ca_cert_pem && cfg->client_cert_pem && cfg->client_key_pem) {
        // Copy CA certificate to heap memory
        cli->ca_cert_buf = (uint8_t *)luat_heap_malloc(cfg->ca_cert_len + 1);
        if (!cli->ca_cert_buf) {
            return -2;
        }
        memcpy(cli->ca_cert_buf, cfg->ca_cert_pem, cfg->ca_cert_len);
        cli->ca_cert_buf[cfg->ca_cert_len] = '\0';  // Add string terminator
        cli->ca_cert_len = cfg->ca_cert_len;
        
        // Copy client certificate to heap memory
        cli->client_cert_buf = (uint8_t *)luat_heap_malloc(cfg->client_cert_len + 1);
        if (!cli->client_cert_buf) {
            luat_heap_free(cli->ca_cert_buf);
            cli->ca_cert_buf = NULL;
            return -2;
        }
        memcpy(cli->client_cert_buf, cfg->client_cert_pem, cfg->client_cert_len);
        cli->client_cert_buf[cfg->client_cert_len] = '\0';
        cli->client_cert_len = cfg->client_cert_len;
        
        // Copy client private key to heap memory
        cli->client_key_buf = (uint8_t *)luat_heap_malloc(cfg->client_key_len + 1);
        if (!cli->client_key_buf) {
            luat_heap_free(cli->ca_cert_buf);
            luat_heap_free(cli->client_cert_buf);
            cli->ca_cert_buf = NULL;
            cli->client_cert_buf = NULL;
            return -2;
        }
        memcpy(cli->client_key_buf, cfg->client_key_pem, cfg->client_key_len);
        cli->client_key_buf[cfg->client_key_len] = '\0';
        cli->client_key_len = cfg->client_key_len;
        
        // Allocate TLS temporary buffer
        cli->tls_buf = (uint8_t *)luat_heap_malloc(1600);
        if (!cli->tls_buf) {
            luat_heap_free(cli->ca_cert_buf);
            luat_heap_free(cli->client_cert_buf);
            luat_heap_free(cli->client_key_buf);
            cli->ca_cert_buf = NULL;
            cli->client_cert_buf = NULL;
            cli->client_key_buf = NULL;
            return -2;
        }
        
        // Initialize TLS using copied certificate data
        ovpn_client_cfg_t cfg_copy = *cfg;  // Copy configuration structure
        cfg_copy.ca_cert_pem = (const char *)cli->ca_cert_buf;
        cfg_copy.ca_cert_len = cli->ca_cert_len;
        cfg_copy.client_cert_pem = (const char *)cli->client_cert_buf;
        cfg_copy.client_cert_len = cli->client_cert_len;
        cfg_copy.client_key_pem = (const char *)cli->client_key_buf;
        cfg_copy.client_key_len = cli->client_key_len;
        
        if (ovpn_tls_init(cli, &cfg_copy) != 0) {
            luat_heap_free(cli->ca_cert_buf);
            luat_heap_free(cli->client_cert_buf);
            luat_heap_free(cli->client_key_buf);
            luat_heap_free(cli->tls_buf);
            cli->ca_cert_buf = NULL;
            cli->client_cert_buf = NULL;
            cli->client_key_buf = NULL;
            cli->tls_buf = NULL;
            return -2;
        }
        cli->use_tls = 1;
    }
    cli->last_activity_ms = sys_now();
    cli->last_ping_ms = cli->last_activity_ms;
    return 0;
}

static void ovpn_attach_netif(ovpn_client_t *cli) {
    if (cli->adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        cli->adapter_index = NW_ADAPTER_INDEX_LWIP_USER0;
    }
    /* lwIP 2.0/2.1/2.2 compatibility: netif_add parameters */
#if LWIP_VERSION_MAJOR >= 2 && LWIP_VERSION_MINOR >= 1
    netif_add(&cli->netif, IP4_ADDR_ANY4, IP4_ADDR_ANY4, IP4_ADDR_ANY4, cli, ovpn_netif_init, netif_input);
#else
    /* lwIP 2.0: netif_add accepts ip4_addr_t* type */
    ip4_addr_t ipaddr, netmask, gw;
    ip4_addr_set_zero(&ipaddr);
    ip4_addr_set_zero(&netmask);
    ip4_addr_set_zero(&gw);
    netif_add(&cli->netif, &ipaddr, &netmask, &gw, cli, ovpn_netif_init, netif_input);
#endif
    netif_set_up(&cli->netif);
    netif_set_link_up(&cli->netif);
    net_lwip2_set_netif(cli->adapter_index, &cli->netif);
    net_lwip2_register_adapter(cli->adapter_index);
}

int ovpn_client_start(ovpn_client_t *cli) {
    if (!cli) {
        return -1;
    }
    if (cli->started) {
        return 0;
    }
    if (ip_addr_isany(&cli->remote_ip)) {
        LLOGE("remote ip missing");
        return -2;
    }
    if (!cli->use_tls && cli->key_len == 0) {
        LLOGE("static key missing");
        return -3;
    }
    /* lwIP 2.0/2.1/2.2 compatibility: use different UDP creation methods based on version */
#if LWIP_VERSION_MAJOR >= 2 && LWIP_VERSION_MINOR >= 1
    cli->udp = udp_new_ip_type(IPADDR_TYPE_ANY);
#else
    cli->udp = udp_new();
#endif
    if (!cli->udp) {
        LLOGE("udp alloc fail");
        return -3;
    }
    /* lwIP 2.0/2.1/2.2 compatibility: initialize any_addr */
#if LWIP_VERSION_MAJOR >= 2 && LWIP_VERSION_MINOR >= 1
    ip_addr_t any_addr = IPADDR_ANY_TYPE_INIT;
#else
    ip_addr_t any_addr;
    ip_addr_set_any(IP_IS_V6(&cli->remote_ip), &any_addr);
#endif
    if (udp_bind(cli->udp, &any_addr, 0) != ERR_OK) {
        udp_remove(cli->udp);
        cli->udp = NULL;
        LLOGE("udp bind fail");
        return -4;
    }
    udp_recv(cli->udp, ovpn_udp_recv, cli);
    ovpn_attach_netif(cli);
    sys_timeout(OVPN_PING_INTERVAL_MS, ovpn_ping_timer, cli);
    cli->started = 1;
    /* Trigger connection established event (static key mode triggers immediately, TLS mode waits for handshake completion) */
    if (!cli->use_tls && cli->event_cb) {
        cli->event_cb(OVPN_EVENT_CONNECTED, cli->user_data);
    }
    return 0;
}

void ovpn_client_stop(ovpn_client_t *cli) {
    if (!cli) {
        return;
    }
    if (cli->udp) {
        udp_remove(cli->udp);
        cli->udp = NULL;
    }
    sys_untimeout(ovpn_ping_timer, cli);
    if (cli->started) {
        netif_set_down(&cli->netif);
        netif_remove(&cli->netif);
    }
    cli->started = 0;
    if (cli->use_tls) {
        ovpn_tls_free(cli);
    }
    /* Trigger disconnected event */
    if (cli->event_cb) {
        cli->event_cb(OVPN_EVENT_DISCONNECTED, cli->user_data);
    }
}

static err_t ovpn_send_frame(ovpn_client_t *cli, struct pbuf *payload, uint8_t flags) {
    if (!cli || !cli->udp) {
        return ERR_CLSD;
    }
    uint16_t payload_len = payload ? (uint16_t)payload->tot_len : 0;
    if (payload_len > cli->mtu) {
        return ERR_VAL;
    }
    /* Build the logical header used for ping/replay even in TLS mode. */
    struct ovpn_data_hdr hdr = {0};
    hdr.seq = lwip_htonl(cli->tx_seq++);
    hdr.len = lwip_htons(payload_len);
    hdr.flags = flags;

    if (cli->use_tls) {
        if (!cli->tls_ready) {
            return ERR_INPROGRESS;
        }
        uint16_t frame_len = (uint16_t)(sizeof(hdr) + payload_len);
        if (frame_len > 1600 || !cli->tls_buf) {
            return ERR_VAL;
        }
        memcpy(cli->tls_buf, &hdr, sizeof(hdr));
        if (payload_len) {
            pbuf_copy_partial(payload, cli->tls_buf + sizeof(hdr), payload_len, 0);
        }
        int wret = mbedtls_ssl_write(&cli->ssl, cli->tls_buf, frame_len);
        if (wret > 0) {
            cli->stats.tx_pkts++;
            cli->stats.tx_bytes += payload_len;
            if (flags == OVPN_FLAG_PING) {
                cli->stats.ping_sent++;
            }
            cli->last_activity_ms = sys_now();
            if (cli->debug) {
                LLOGD("tx(tls) seq=%lu len=%u flags=0x%02X", (unsigned long)lwip_ntohl(hdr.seq), payload_len, flags);
            }
            /* Trigger data TX event (non-PING packets) */
            if (payload_len > 0 && cli->event_cb) {
                cli->event_cb(OVPN_EVENT_DATA_TX, cli->user_data);
            }
            return ERR_OK;
        }
        return ERR_CLSD;
    }

    uint16_t frame_len = sizeof(hdr) + payload_len + OVPN_HMAC_LEN;
    struct pbuf *q = pbuf_alloc(PBUF_TRANSPORT, frame_len, PBUF_RAM);
    if (!q) {
        return ERR_MEM;
    }
    pbuf_take(q, &hdr, sizeof(hdr));
    uint8_t *frame_payload = ((uint8_t *)q->payload) + sizeof(hdr);
    if (payload_len) {
        pbuf_copy_partial(payload, frame_payload, payload_len, 0);
    }
    uint8_t *mac_pos = frame_payload + payload_len;
    if (ovpn_hmac(cli, (const uint8_t *)&hdr, sizeof(hdr), frame_payload, payload_len, mac_pos) != 0) {
        pbuf_free(q);
        return ERR_VAL;
    }
    err_t err = udp_sendto(cli->udp, q, &cli->remote_ip, cli->remote_port);
    if (err == ERR_OK) {
        cli->stats.tx_pkts++;
        cli->stats.tx_bytes += payload_len;
        if (flags == OVPN_FLAG_PING) {
            cli->stats.ping_sent++;
        }
        cli->last_activity_ms = sys_now();
        if (cli->debug) {
            LLOGD("tx seq=%lu len=%u flags=0x%02X", (unsigned long)lwip_ntohl(hdr.seq), payload_len, flags);
        }
        /* Trigger data TX event (non-PING packets) */
        if (payload_len > 0 && cli->event_cb) {
            cli->event_cb(OVPN_EVENT_DATA_TX, cli->user_data);
        }
    }
    pbuf_free(q);
    return err;
}

static int ovpn_hmac(const ovpn_client_t *cli, const uint8_t *hdr, size_t hdr_len, const uint8_t *payload, size_t payload_len, uint8_t *out) {
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_context_t ctx;
    if (!info || !out || !cli || cli->key_len == 0) {
        return -1;
    }
    mbedtls_md_init(&ctx);
    if (mbedtls_md_setup(&ctx, info, 1) != 0) {
        mbedtls_md_free(&ctx);
        return -1;
    }
    if (mbedtls_md_hmac_starts(&ctx, cli->key, cli->key_len) != 0) {
        mbedtls_md_free(&ctx);
        return -1;
    }
    mbedtls_md_hmac_update(&ctx, hdr, hdr_len);
    if (payload_len) {
        mbedtls_md_hmac_update(&ctx, payload, payload_len);
    }
    int ret = mbedtls_md_hmac_finish(&ctx, out);
    mbedtls_md_free(&ctx);
    return ret;
}

static int ovpn_replay_accept(ovpn_client_t *cli, uint32_t seq) {
    if (!cli) {
        return 0;
    }
    if (!cli->rx_initialized) {
        cli->rx_initialized = 1;
        cli->rx_max_seq = seq;
        cli->rx_window = 1u;
        return 1;
    }
    if (seq > cli->rx_max_seq) {
        uint32_t shift = seq - cli->rx_max_seq;
        if (shift >= OVPN_REPLAY_WINDOW) {
            cli->rx_window = 1u;
        } else {
            cli->rx_window = (cli->rx_window << shift) | 1u;
        }
        cli->rx_max_seq = seq;
        return 1;
    }
    uint32_t diff = cli->rx_max_seq - seq;
    if (diff >= OVPN_REPLAY_WINDOW) {
        return 0;
    }
    uint32_t mask = 1u << diff;
    if (cli->rx_window & mask) {
        return 0;
    }
    cli->rx_window |= mask;
    return 1;
}

static void ovpn_ping_timer(void *arg) {
    ovpn_client_t *cli = (ovpn_client_t *)arg;
    if (!cli || !cli->started) {
        return;
    }
    uint32_t now = sys_now();
    if ((now - cli->last_activity_ms) >= OVPN_PING_INTERVAL_MS) {
        if (!(cli->use_tls && !cli->tls_ready)) {
            ovpn_send_frame(cli, NULL, OVPN_FLAG_PING);
            cli->last_ping_ms = now;
        }
    }
    if ((now - cli->last_activity_ms) >= OVPN_DEAD_INTERVAL_MS) {
        if (cli->debug) {
            LLOGW("keepalive timeout");
        }
        /* Trigger keepalive timeout event (triggered once per timer cycle) */
        if (cli->event_cb && (now - cli->last_activity_ms) < (OVPN_DEAD_INTERVAL_MS + OVPN_PING_INTERVAL_MS)) {
            cli->event_cb(OVPN_EVENT_KEEPALIVE_TIMEOUT, cli->user_data);
        }
    }
    sys_timeout(OVPN_PING_INTERVAL_MS, ovpn_ping_timer, cli);
}

static err_t ovpn_send_payload(ovpn_client_t *cli, struct pbuf *payload) {
    if (!cli) {
        return ERR_VAL;
    }
    return ovpn_send_frame(cli, payload, 0);
}

static err_t ovpn_netif_output_ip4(struct netif *n, struct pbuf *p, const ip4_addr_t *addr) {
    LWIP_UNUSED_ARG(addr);
    ovpn_client_t *cli = (ovpn_client_t *)n->state;
    if (!cli) {
        return ERR_VAL;
    }
    return ovpn_send_payload(cli, p);
}

#if LWIP_IPV6
static err_t ovpn_netif_output_ip6(struct netif *n, struct pbuf *p, const ip6_addr_t *addr) {
    LWIP_UNUSED_ARG(addr);
    ovpn_client_t *cli = (ovpn_client_t *)n->state;
    if (!cli) {
        return ERR_VAL;
    }
    return ovpn_send_payload(cli, p);
}
#endif

static void ovpn_udp_recv(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port) {
    LWIP_UNUSED_ARG(pcb);
    LWIP_UNUSED_ARG(addr);
    LWIP_UNUSED_ARG(port);
    ovpn_client_t *cli = (ovpn_client_t *)arg;
    if (!cli || !p) {
        if (p) pbuf_free(p);
        return;
    }
    if (cli->use_tls) {
        if (cli->rx_pending.pkt) {
            pbuf_free(cli->rx_pending.pkt);
        }
        cli->rx_pending.pkt = p;
        cli->rx_pending.offset = 0;
        ovpn_tls_process_rx(cli);
        return;
    }
    if (p->tot_len < (sizeof(struct ovpn_data_hdr) + OVPN_HMAC_LEN)) {
        cli->stats.drop_malformed++;
        pbuf_free(p);
        return;
    }
    struct ovpn_data_hdr hdr;
    pbuf_copy_partial(p, &hdr, sizeof(hdr), 0);
    uint16_t plen = lwip_ntohs(hdr.len);
    uint32_t seq = lwip_ntohl(hdr.seq);
    uint16_t expect_len = (uint16_t)(sizeof(hdr) + plen + OVPN_HMAC_LEN);
    if (p->tot_len < expect_len) {
        cli->stats.drop_malformed++;
        pbuf_free(p);
        return;
    }
    if (!ovpn_replay_accept(cli, seq)) {
        cli->stats.drop_replay++;
        pbuf_free(p);
        return;
    }
    struct pbuf *ip = NULL;
    if (plen) {
        ip = pbuf_alloc(PBUF_IP, plen, PBUF_RAM);
        if (!ip) {
            pbuf_free(p);
            return;
        }
        pbuf_copy_partial(p, ip->payload, plen, sizeof(hdr));
    }
    uint8_t mac_calc[OVPN_HMAC_LEN];
    uint8_t mac_recv[OVPN_HMAC_LEN];
    pbuf_copy_partial(p, mac_recv, OVPN_HMAC_LEN, sizeof(hdr) + plen);
    if (ovpn_hmac(cli, (uint8_t *)&hdr, sizeof(hdr), ip ? (uint8_t *)ip->payload : NULL, plen, mac_calc) != 0 ||
        memcmp(mac_calc, mac_recv, OVPN_HMAC_LEN) != 0) {
        cli->stats.drop_auth++;
        /* Trigger authentication failed event */
        if (cli->event_cb) {
            cli->event_cb(OVPN_EVENT_AUTH_FAILED, cli->user_data);
        }
        if (ip) pbuf_free(ip);
        pbuf_free(p);
        return;
    }
    cli->last_activity_ms = sys_now();
    if (hdr.flags & OVPN_FLAG_PING) {
        cli->stats.ping_recv++;
        ovpn_send_frame(cli, NULL, OVPN_FLAG_PONG);
        if (ip) pbuf_free(ip);
        pbuf_free(p);
        return;
    }
    if (hdr.flags & OVPN_FLAG_PONG) {
        if (ip) pbuf_free(ip);
        pbuf_free(p);
        return;
    }
    if (ip) {
        err_t err = cli->netif.input(ip, &cli->netif);
        if (err != ERR_OK) {
            pbuf_free(ip);
        } else {
            cli->stats.rx_pkts++;
            cli->stats.rx_bytes += plen;
            /* Trigger data RX event */
            if (cli->event_cb) {
                cli->event_cb(OVPN_EVENT_DATA_RX, cli->user_data);
            }
        }
    }
    if (cli->debug) {
        LLOGD("rx seq=%lu len=%u flags=0x%02X", (unsigned long)seq, plen, hdr.flags);
    }
    pbuf_free(p);
}

static int ovpn_tls_udp_send(void *ctx, const unsigned char *buf, size_t len) {
    ovpn_client_t *cli = (ovpn_client_t *)ctx;
    if (!cli || !cli->udp) {
        return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    }
    /* Allocate a transient pbuf for the DTLS record. */
    struct pbuf *q = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
    if (!q) {
        return MBEDTLS_ERR_SSL_ALLOC_FAILED;
    }
    pbuf_take(q, buf, len);
    err_t err = udp_sendto(cli->udp, q, &cli->remote_ip, cli->remote_port);
    pbuf_free(q);
    if (err != ERR_OK) {
        return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    }
    return (int)len;
}

static int ovpn_tls_udp_recv(void *ctx, unsigned char *buf, size_t len) {
    ovpn_client_t *cli = (ovpn_client_t *)ctx;
    if (!cli || !cli->rx_pending.pkt) {
        return MBEDTLS_ERR_SSL_WANT_READ;
    }
    struct pbuf *p = cli->rx_pending.pkt;
    uint16_t remain = p->tot_len - cli->rx_pending.offset;
    uint16_t take = (remain > len) ? (uint16_t)len : remain;
    pbuf_copy_partial(p, buf, take, cli->rx_pending.offset);
    cli->rx_pending.offset += take;
    if (cli->rx_pending.offset >= p->tot_len) {
        pbuf_free(p);
        cli->rx_pending.pkt = NULL;
        cli->rx_pending.offset = 0;
    }
    return (int)take;
}

static void ovpn_tls_set_delay(void *ctx, uint32_t int_ms, uint32_t fin_ms) {
    ovpn_client_t *cli = (ovpn_client_t *)ctx;
    cli->dtls_timer.int_ms = int_ms ? (sys_now() + int_ms) : 0;
    cli->dtls_timer.fin_ms = fin_ms ? (sys_now() + fin_ms) : 0;
}

static int ovpn_tls_get_delay(void *ctx) {
    ovpn_client_t *cli = (ovpn_client_t *)ctx;
    uint32_t now = sys_now();
    if (cli->dtls_timer.fin_ms == 0) {
        return -1;
    }
    if (now >= cli->dtls_timer.fin_ms) {
        return 2;
    }
    if (cli->dtls_timer.int_ms && now >= cli->dtls_timer.int_ms) {
        return 1;
    }
    return 0;
}

static int tls_myrand( void *rng_state, unsigned char *output, size_t len ) {
    (void)rng_state;
    luat_crypto_trng((char*)output, len);
    return 0;
}


static int ovpn_tls_init(ovpn_client_t *cli, const ovpn_client_cfg_t *cfg) {
    /* Initialize DTLS contexts and load credentials. */
    mbedtls_ssl_init(&cli->ssl);
    mbedtls_ssl_config_init(&cli->conf);
    mbedtls_x509_crt_init(&cli->ca);
    mbedtls_x509_crt_init(&cli->client_cert);
    mbedtls_pk_init(&cli->client_key);
    mbedtls_ctr_drbg_init(&cli->drbg);
    mbedtls_entropy_init(&cli->entropy);

    const char *pers = "ovpn-dtls";
    int ret = mbedtls_ctr_drbg_seed(&cli->drbg, mbedtls_entropy_func, &cli->entropy,
                                    (const unsigned char *)pers, strlen(pers));
    if (ret != 0) {
        return ret;
    }
    ret = mbedtls_x509_crt_parse(&cli->ca, (const unsigned char *)cfg->ca_cert_pem, cfg->ca_cert_len);
    if (ret != 0) {
        return ret;
    }
    ret = mbedtls_x509_crt_parse(&cli->client_cert, (const unsigned char *)cfg->client_cert_pem, cfg->client_cert_len);
    if (ret != 0) {
        return ret;
    }
    /* mbedtls 3.x adds RNG parameters to pk_parse_key */
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
    ret = mbedtls_pk_parse_key(&cli->client_key, (const unsigned char *)cfg->client_key_pem, cfg->client_key_len, 
                                NULL, 0, mbedtls_ctr_drbg_random, &cli->drbg);
#else
    ret = mbedtls_pk_parse_key(&cli->client_key, (const unsigned char *)cfg->client_key_pem, cfg->client_key_len, tls_myrand, 0);
#endif
    if (ret != 0) {
        return ret;
    }
    ret = mbedtls_ssl_config_defaults(&cli->conf,
                                      MBEDTLS_SSL_IS_CLIENT,
                                      MBEDTLS_SSL_TRANSPORT_DATAGRAM,
                                      MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        return ret;
    }
    mbedtls_ssl_conf_authmode(&cli->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&cli->conf, &cli->ca, NULL);
    ret = mbedtls_ssl_conf_own_cert(&cli->conf, &cli->client_cert, &cli->client_key);
    if (ret != 0) {
        return ret;
    }
    mbedtls_ssl_conf_rng(&cli->conf, mbedtls_ctr_drbg_random, &cli->drbg);
    //mbedtls_ssl_conf_min_version(&cli->conf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3);

    ret = mbedtls_ssl_setup(&cli->ssl, &cli->conf);
    if (ret != 0) {
        return ret;
    }
    if (cfg->remote_host) {
        mbedtls_ssl_set_hostname(&cli->ssl, cfg->remote_host);
    }
    mbedtls_ssl_set_bio(&cli->ssl, cli, ovpn_tls_udp_send, ovpn_tls_udp_recv, NULL);
    mbedtls_ssl_set_timer_cb(&cli->ssl, cli, ovpn_tls_set_delay, ovpn_tls_get_delay);
    cli->tls_ready = 0;
    return 0;
}

static void ovpn_tls_free(ovpn_client_t *cli) {
    if (!cli || !cli->use_tls) {
        return;
    }
    if (cli->rx_pending.pkt) {
        pbuf_free(cli->rx_pending.pkt);
        cli->rx_pending.pkt = NULL;
    }
    if (cli->tls_buf) {
        luat_heap_free(cli->tls_buf);
        cli->tls_buf = NULL;
    }
    // Free certificate data copies
    if (cli->ca_cert_buf) {
        luat_heap_free(cli->ca_cert_buf);
        cli->ca_cert_buf = NULL;
    }
    if (cli->client_cert_buf) {
        luat_heap_free(cli->client_cert_buf);
        cli->client_cert_buf = NULL;
    }
    if (cli->client_key_buf) {
        luat_heap_free(cli->client_key_buf);
        cli->client_key_buf = NULL;
    }
    mbedtls_ssl_free(&cli->ssl);
    mbedtls_ssl_config_free(&cli->conf);
    mbedtls_x509_crt_free(&cli->ca);
    mbedtls_x509_crt_free(&cli->client_cert);
    mbedtls_pk_free(&cli->client_key);
    mbedtls_ctr_drbg_free(&cli->drbg);
    mbedtls_entropy_free(&cli->entropy);
}

static void ovpn_tls_process_rx(ovpn_client_t *cli) {
    /* Drive DTLS handshake and decrypt any app data buffered from udp recv. */
    if (!cli || !cli->use_tls) {
        return;
    }
    if (!cli->tls_ready) {
        while (!cli->tls_ready) {
            int ret = mbedtls_ssl_handshake_step(&cli->ssl);
            if (ret == 0) {
                /* mbedtls version compatibility: check if handshake is complete */
                /* Use MBEDTLS_PRIVATE macro to be compatible with mbedtls 2.x/3.x */
                int handshake_done = (cli->ssl.MBEDTLS_PRIVATE(state) == MBEDTLS_SSL_HANDSHAKE_OVER);
                if (handshake_done) {
                    cli->tls_ready = 1;
                    if (cli->debug) {
                        LLOGI("dtls handshake ok");
                    }
                    /* Trigger TLS handshake OK event */
                    if (cli->event_cb) {
                        cli->event_cb(OVPN_EVENT_TLS_HANDSHAKE_OK, cli->user_data);
                    }
                }
                continue;
            }
            if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
                break;
            }
            if (cli->debug) {
                LLOGE("dtls handshake err %d", ret);
            }
            /* Trigger TLS handshake FAIL event */
            if (cli->event_cb) {
                cli->event_cb(OVPN_EVENT_TLS_HANDSHAKE_FAIL, cli->user_data);
            }
            return;
        }
    }

    if (!cli->tls_ready) {
        return;
    }

    if (!cli->tls_buf) {
        return;
    }
    for (;;) {
        int rlen = mbedtls_ssl_read(&cli->ssl, cli->tls_buf, 1600);
        if (rlen > 0) {
            if ((size_t)rlen < sizeof(struct ovpn_data_hdr)) {
                cli->stats.drop_malformed++;
                continue;
            }
            struct ovpn_data_hdr hdr;
            memcpy(&hdr, cli->tls_buf, sizeof(hdr));
            uint16_t plen = lwip_ntohs(hdr.len);
            uint32_t seq = lwip_ntohl(hdr.seq);
            if ((size_t)rlen < sizeof(hdr) + plen) {
                cli->stats.drop_malformed++;
                continue;
            }
            if (!ovpn_replay_accept(cli, seq)) {
                cli->stats.drop_replay++;
                continue;
            }
            cli->last_activity_ms = sys_now();
            if (hdr.flags & OVPN_FLAG_PING) {
                cli->stats.ping_recv++;
                ovpn_send_frame(cli, NULL, OVPN_FLAG_PONG);
                continue;
            }
            if (hdr.flags & OVPN_FLAG_PONG) {
                continue;
            }
            if (plen) {
                struct pbuf *ip = pbuf_alloc(PBUF_IP, plen, PBUF_RAM);
                if (!ip) {
                    continue;
                }
                memcpy(ip->payload, cli->tls_buf + sizeof(hdr), plen);
                err_t err = cli->netif.input(ip, &cli->netif);
                if (err != ERR_OK) {
                    pbuf_free(ip);
                } else {
                    cli->stats.rx_pkts++;
                    cli->stats.rx_bytes += plen;
                    /* Trigger data RX event */
                    if (cli->event_cb) {
                        cli->event_cb(OVPN_EVENT_DATA_RX, cli->user_data);
                    }
                }
            }
            if (cli->debug) {
                LLOGD("rx(tls) seq=%lu len=%u flags=0x%02X", (unsigned long)seq, plen, hdr.flags);
            }
            continue;
        }
        if (rlen == MBEDTLS_ERR_SSL_WANT_READ || rlen == MBEDTLS_ERR_SSL_WANT_WRITE) {
            break;
        }
        if (rlen == 0) {
            /* EOF */
            break;
        }
        if (cli->debug) {
            LLOGE("dtls read err %d", rlen);
        }
        break;
    }
}

static err_t ovpn_netif_init(struct netif *n) {
    ovpn_client_t *cli = (ovpn_client_t *)n->state;
    n->mtu = cli->mtu;
    n->flags = NETIF_FLAG_POINTTOPOINT | NETIF_FLAG_NOARP | NETIF_FLAG_LINK_UP;
    n->output = ovpn_netif_output_ip4;
#if LWIP_IPV6
    n->output_ip6 = ovpn_netif_output_ip6;
#endif
    n->name[0] = 'o';
    n->name[1] = 'v';
    return ERR_OK;
}

void ovpn_client_get_stats(ovpn_client_t *cli, ovpn_client_stats_t *out) {
    if (!cli || !out) {
        return;
    }
    *out = cli->stats;
}

void ovpn_client_set_debug(ovpn_client_t *cli, int enable) {
    if (!cli) {
        return;
    }
    cli->debug = enable ? 1 : 0;
}
