/*
 * IKEv2 initiator (RFC 7296) for LuatOS netdrv.
 *
 * Tunnel mode client with:
 *   - IKE_SA_INIT: aes256-sha256-modp2048 / aes128-sha1-modp2048
 *   - IKE_AUTH: EAP-MSCHAPv2 (RFC 2759/3079) + server certificate chain
 *     verification (Let's Encrypt ISRG Root X1 by default) + SAN check
 *   - NAT-T (RFC 3948): UDP 500 -> 4500, keepalives
 *   - DPD liveness checks
 *   - CHILD_SA rekey via CREATE_CHILD_SA without PFS (no KE)
 *   - IKE SA expiry -> full session rebuild
 *   - CP (Configuration Payload): virtual IPv4 + DNS
 *
 * Threading model (same as L2TP/OpenVPN clients):
 *   - all state machine work runs on the tcpip thread (marshaled with
 *     tcpip_callback_with_block);
 *   - the adapter callback only copies the datagram and posts it to the
 *     tcpip thread.
 */

#include "ipsec_ike.h"
#include "ipsec_crypto.h"
#include "ipsec_vendor_chap_ms.h"

#include <string.h>
#include <stdio.h>

#include "lwip/def.h"
#include "lwip/pbuf.h"
#include "lwip/ip4.h"
#include "lwip/tcpip.h"
#include "lwip/timeouts.h"
#include "lwip/sys.h"
#include "net_lwip2.h"
#include "luat_netdrv.h"
#include "luat_mem.h"
#include "luat_crypto.h"
#include "mbedtls/aes.h"
#include "mbedtls/md.h"
#include "mbedtls/sha1.h"

#define LUAT_LOG_TAG "ipsec_ike"
#include "luat_log.h"

/* lwIP compatibility defines for NETIF flags */
#ifndef NETIF_FLAG_POINTTOPOINT
#define NETIF_FLAG_POINTTOPOINT 0
#endif
#ifndef NETIF_FLAG_NOARP
#define NETIF_FLAG_NOARP 0
#endif

/* Forward declarations */
static void ipsec_do_start(void *arg);
static void ipsec_do_stop(void *arg);
static void ipsec_do_rx(void *arg);
static void ipsec_retrans_timer(void *arg);
static void ipsec_tick_timer(void *arg);
static void ipsec_keepalive_timer(void *arg);
static void ipsec_retry_timer(void *arg);
static void ipsec_stop_internal(ipsec_client_t *cli);
static void ipsec_schedule_retry(ipsec_client_t *cli, const char *reason);
static int  ipsec_transport_is_online(ipsec_client_t *cli);
static int  ipsec_switch_socket(ipsec_client_t *cli, uint16_t port);
static int  ipsec_send_msg(ipsec_client_t *cli, const uint8_t *buf, uint16_t len,
                           int retransmit);
static void ipsec_start_retrans(ipsec_client_t *cli);
static void ipsec_cancel_retrans(ipsec_client_t *cli);
static void ipsec_set_online(ipsec_client_t *cli, int online);
static void ipsec_dump_frame(const char *tag, const uint8_t *data, uint16_t len);

/* ========== Byte helpers ========== */

static void ike_put16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)(v);
}

static void ike_put32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)(v);
}

static uint16_t ike_get16(const uint8_t *p)
{
    return (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
}

static uint32_t ike_get32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

/* ========== IKE message structure helpers ========== */

static void ike_build_header(uint8_t *buf, const uint8_t *spii, const uint8_t *spir,
                             uint8_t next, uint8_t extype, uint8_t flags,
                             uint8_t msgid, uint16_t len)
{
    memcpy(buf, spii, 8);
    memcpy(buf + 8, spir, 8);
    buf[16] = next;
    buf[17] = 0x20; /* major 2, minor 0 */
    buf[18] = extype;
    buf[19] = flags;
    ike_put32(buf + 20, msgid); /* 4-octet big-endian message ID */
    ike_put32(buf + 24, len);
}

/* Write a generic payload header, return pointer to the payload body */
static uint8_t *ike_payload_hdr(uint8_t *p, uint8_t next)
{
    p[0] = next;
    p[1] = 0;
    ike_put16(p + 2, 0); /* length patched by caller */
    return p + 4;
}

static void ike_payload_len(uint8_t *p, uint16_t len)
{
    ike_put16(p + 2, len);
}

/* Walk an unencrypted payload chain; find first payload of \p type */
static int ike_find_payload(const uint8_t *msg, uint16_t msg_len,
                            uint8_t next, uint8_t type,
                            const uint8_t **pp, uint16_t *plen)
{
    const uint8_t *p = msg + 28; /* skip IKE header */
    const uint8_t *end = msg + msg_len;

    while (next != 0) {
        uint16_t len;
        if (p + 4 > end) {
            LLOGE("auth2 walk: short header");
            return -1;
        }
        len = ike_get16(p + 2);
        if (len < 4 || p + len > end) {
            LLOGE("auth2 walk: bad len %u", (unsigned)len);
            return -1;
        }
        if (next == type) {
            *pp = p;
            *plen = len;
            return 0;
        }
        next = p[0];
        p += len;
    }
    return -1;
}

/* ========== SA proposal builders ========== */

/* Build the IKE SA payload with two proposals (aes256-sha256-modp2048 first).
 * Returns payload length. */
static uint16_t ike_build_ike_sa(uint8_t *p)
{
    uint8_t *sa_hdr = p;
    uint8_t *t;

    ike_payload_hdr(p, IPSEC_PAYLOAD_KE);
    p += 4;

    /* Proposal 1: AES-256 + PRF-SHA256 + INTEG-SHA256-128 + DH14 */
    p[0] = 2; /* more proposals follow */
    p[1] = 0;
    ike_put16(p + 2, 44);
    p[4] = 1;  /* proposal num */
    p[5] = IPSEC_PROTO_IKE;
    p[6] = 0;  /* SPI size */
    p[7] = 4;  /* num transforms */
    p += 8;

    p[0] = 3;
    p[1] = 0;
    ike_put16(p + 2, 12);
    p[4] = IPSEC_TRANSFORM_ENCR;
    p[5] = 0;
    ike_put16(p + 6, IPSEC_ENCR_AES_CBC);
    ike_put16(p + 8, 0x800E); /* KEY_LENGTH attribute, TV form */
    ike_put16(p + 10, 256);
    p += 12;

    t = p;
    t[0] = 3; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_PRF; t[5] = 0; ike_put16(t + 6, IPSEC_PRF_HMAC_SHA2_256);
    p += 8;

    t = p;
    t[0] = 3; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_INTEG; t[5] = 0; ike_put16(t + 6, IPSEC_INTEG_HMAC_SHA2_256_128);
    p += 8;

    t = p;
    t[0] = 0; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_DH; t[5] = 0; ike_put16(t + 6, IPSEC_DH_MODP_2048);
    p += 8;

    /* Proposal 2: AES-128 + PRF-SHA1 + INTEG-SHA1-96 + DH14 */
    p[0] = 0; /* last proposal */
    p[1] = 0;
    ike_put16(p + 2, 44);
    p[4] = 2;
    p[5] = IPSEC_PROTO_IKE;
    p[6] = 0;
    p[7] = 4;
    p += 8;

    t = p;
    t[0] = 3; t[1] = 0; ike_put16(t + 2, 12);
    t[4] = IPSEC_TRANSFORM_ENCR; t[5] = 0; ike_put16(t + 6, IPSEC_ENCR_AES_CBC);
    ike_put16(t + 8, 0x800E);
    ike_put16(t + 10, 128);
    p += 12;

    t = p;
    t[0] = 3; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_PRF; t[5] = 0; ike_put16(t + 6, IPSEC_PRF_HMAC_SHA1);
    p += 8;

    t = p;
    t[0] = 3; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_INTEG; t[5] = 0; ike_put16(t + 6, IPSEC_INTEG_HMAC_SHA1_96);
    p += 8;

    t = p;
    t[0] = 0; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_DH; t[5] = 0; ike_put16(t + 6, IPSEC_DH_MODP_2048);
    p += 8;

    ike_payload_len(sa_hdr, (uint16_t)(p - sa_hdr));
    return (uint16_t)(p - sa_hdr);
}

/* Build the ESP SA payload with two proposals, using \p spi (network order) */
static uint16_t ike_build_esp_sa(uint8_t *p, uint32_t spi)
{
    uint8_t *sa_hdr = p;

    ike_payload_hdr(p, 0); /* next patched by caller */
    p += 4;

    /* Proposal 1: AES-256-CBC + HMAC-SHA2-256-128, no ESN */
    p[0] = 2; p[1] = 0; ike_put16(p + 2, 40);
    p[4] = 1; p[5] = IPSEC_PROTO_ESP; p[6] = 4; p[7] = 3;
    ike_put32(p + 8, spi);
    p += 12;

    p[0] = 3; p[1] = 0; ike_put16(p + 2, 12);
    p[4] = IPSEC_TRANSFORM_ENCR; p[5] = 0; ike_put16(p + 6, IPSEC_ENCR_AES_CBC);
    ike_put16(p + 8, 0x800E); ike_put16(p + 10, 256);
    p += 12;

    {
    uint8_t *t = p;
    t[0] = 3; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_INTEG; t[5] = 0; ike_put16(t + 6, IPSEC_INTEG_HMAC_SHA2_256_128);
    }
    p += 8;

    {
    uint8_t *t = p;
    t[0] = 0; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_ESN; t[5] = 0; ike_put16(t + 6, IPSEC_ESN_NONE);
    }
    p += 8;

    /* Proposal 2: AES-128-CBC + HMAC-SHA1-96, no ESN */
    p[0] = 0; p[1] = 0; ike_put16(p + 2, 40);
    p[4] = 2; p[5] = IPSEC_PROTO_ESP; p[6] = 4; p[7] = 3;
    ike_put32(p + 8, spi);
    p += 12;

    p[0] = 3; p[1] = 0; ike_put16(p + 2, 12);
    p[4] = IPSEC_TRANSFORM_ENCR; p[5] = 0; ike_put16(p + 6, IPSEC_ENCR_AES_CBC);
    ike_put16(p + 8, 0x800E); ike_put16(p + 10, 128);
    p += 12;

    {
    uint8_t *t = p;
    t[0] = 3; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_INTEG; t[5] = 0; ike_put16(t + 6, IPSEC_INTEG_HMAC_SHA1_96);
    }
    p += 8;

    {
    uint8_t *t = p;
    t[0] = 0; t[1] = 0; ike_put16(t + 2, 8);
    t[4] = IPSEC_TRANSFORM_ESN; t[5] = 0; ike_put16(t + 6, IPSEC_ESN_NONE);
    }
    p += 8;

    ike_payload_len(sa_hdr, (uint16_t)(p - sa_hdr));
    return (uint16_t)(p - sa_hdr);
}

/* Build TSi/TSr payloads (0.0.0.0/0, all protocols/ports) */
static uint16_t ike_build_ts(uint8_t *p, uint8_t type)
{
    uint8_t *hdr = p;
    ike_payload_hdr(p, type == IPSEC_PAYLOAD_TSI ? IPSEC_PAYLOAD_TSR : 0);
    p += 4;
    p[0] = 1; /* number of TSs */
    p[1] = 0; p[2] = 0; p[3] = 0;
    p[4] = 7; /* TS_IPV4_ADDR_RANGE */
    p[5] = 0; /* all protocols */
    ike_put16(p + 6, 16);
    ike_put16(p + 8, 0);      /* start port */
    ike_put16(p + 10, 0xFFFF);/* end port */
    p[12] = 0; p[13] = 0; p[14] = 0; p[15] = 0;          /* start 0.0.0.0 */
    p[16] = 255; p[17] = 255; p[18] = 255; p[19] = 255;  /* end 255.255.255.255 */
    p += 20;
    ike_payload_len(hdr, (uint16_t)(p - hdr));
    return (uint16_t)(p - hdr);
}

/* Build a CFG_REQUEST payload (INTERNAL_IP4_ADDRESS + INTERNAL_IP4_DNS) */
static uint16_t ike_build_cp_request(uint8_t *p)
{
    uint8_t *hdr = p;
    ike_payload_hdr(p, 0);
    p += 4;
    p[0] = IPSEC_CFG_REQUEST;
    p[1] = 0; p[2] = 0; p[3] = 0;
    /* INTERNAL_IP4_ADDRESS, empty value */
    ike_put16(p + 4, IPSEC_CFG_INTERNAL_IP4_ADDRESS);
    ike_put16(p + 6, 0);
    /* INTERNAL_IP4_DNS, empty value */
    ike_put16(p + 8, IPSEC_CFG_INTERNAL_IP4_DNS);
    ike_put16(p + 10, 0);
    p += 12;
    ike_payload_len(hdr, (uint16_t)(p - hdr));
    return (uint16_t)(p - hdr);
}

/* Build IDi payload (ID_RFC822_ADDR with username) */
static uint16_t ike_build_idi(ipsec_client_t *cli, uint8_t *p)
{
    uint8_t *hdr = p;
    size_t ulen = cli->username_len;
    ike_payload_hdr(p, 0);
    p += 4;
    p[0] = IPSEC_ID_RFC822_ADDR;
    p[1] = 0; p[2] = 0; p[3] = 0;
    if (ulen > 60)
        ulen = 60;
    memcpy(p + 4, cli->username, ulen);
    p += 4 + ulen;
    ike_payload_len(hdr, (uint16_t)(p - hdr));
    /* save RestOfInitIDPayload (IDType | RESERVED | IDData) */
    cli->idi_rest_len = (uint16_t)(4 + ulen);
    memcpy(cli->idi_rest, hdr + 4, cli->idi_rest_len);
    return (uint16_t)(p - hdr);
}

/* Build EAP payload around a raw EAP message */
static uint16_t ike_build_eap_payload(uint8_t *p, const uint8_t *eap, uint16_t eap_len)
{
    uint8_t *hdr = p;
    ike_payload_hdr(p, 0);
    p += 4;
    memcpy(p, eap, eap_len);
    p += eap_len;
    ike_payload_len(hdr, (uint16_t)(p - hdr));
    return (uint16_t)(p - hdr);
}

/* Build AUTH payload (shared-secret MAC style) */
static uint16_t ike_build_auth_payload(uint8_t *p, const uint8_t *auth, uint16_t auth_len)
{
    uint8_t *hdr = p;
    ike_payload_hdr(p, 0);
    p += 4;
    p[0] = IPSEC_AUTH_SHARED_SECRET;
    p[1] = 0; p[2] = 0; p[3] = 0;
    memcpy(p + 4, auth, auth_len);
    p += 4 + auth_len;
    ike_payload_len(hdr, (uint16_t)(p - hdr));
    return (uint16_t)(p - hdr);
}

/* ========== SK (Encrypted payload) crypto ========== */

static int ike_sk_encrypt(ipsec_client_t *cli, uint8_t *msg,
                          const uint8_t *inner, uint16_t inner_len,
                          uint8_t first_type, uint16_t *msg_len)
{
    uint8_t *sk_hdr = msg + 28;
    uint8_t *iv = sk_hdr + 4;
    uint8_t *ct = iv + 16;
    uint8_t icv[32];
    uint8_t iv_buf[16];
    uint8_t pad_len;
    uint16_t ct_len;
    uint16_t total;
    mbedtls_aes_context aes;
    mbedtls_md_type_t md_type;
    uint16_t integ_len = cli->ike_integ == IPSEC_INTEG_SHA1 ? IPSEC_ESP_ICV_SHA1_LEN
                                                            : IPSEC_ESP_ICV_SHA256_LEN;
    int ret;

    sk_hdr[0] = first_type;
    sk_hdr[1] = 0;

    /* Plaintext: inner payloads | padding | pad_len */
    pad_len = (uint8_t)((16 - ((inner_len + 1) % 16)) % 16);
    if (inner_len > 0)
        memcpy(ct, inner, inner_len);
    memset(ct + inner_len, 0, pad_len);
    ct[inner_len + pad_len] = pad_len;
    ct_len = (uint16_t)(inner_len + pad_len + 1);

    /* mbedtls_aes_crypt_cbc() writes the last ciphertext block back into the
     * iv buffer, so use a scratch IV and keep the packet IV intact. */
    luat_crypto_trng((char *)iv_buf, 16);
    memcpy(iv, iv_buf, 16);
    mbedtls_aes_init(&aes);
    ret = mbedtls_aes_setkey_enc(&aes, cli->sk_ei,
                                 cli->ike_enc == IPSEC_ENC_AES128 ? 128 : 256);
    if (ret == 0)
        ret = mbedtls_aes_crypt_cbc(&aes, MBEDTLS_AES_ENCRYPT, ct_len,
                                    iv_buf, ct, ct);
    mbedtls_aes_free(&aes);
    if (ret != 0)
        return -1;

    ike_put16(sk_hdr + 2, (uint16_t)(4 + 16 + ct_len + integ_len));
    total = (uint16_t)(28 + 4 + 16 + ct_len + integ_len);
    ike_build_header(msg, cli->spii, cli->spir, IPSEC_PAYLOAD_SK,
                     cli->last_exchange, IPSEC_FLAG_INITIATOR, cli->pending_msgid,
                     total);
    total = (uint16_t)(total - integ_len); /* bytes covered by the ICV */
    md_type = cli->ike_integ == IPSEC_INTEG_SHA1 ? MBEDTLS_MD_SHA1 : MBEDTLS_MD_SHA256;
    /* The ICV covers the IKE message only.  strongSwan strips the 4-byte
     * non-ESP marker before parsing, so the marker must NOT be included. */
    if (mbedtls_md_hmac(mbedtls_md_info_from_type(md_type),
                        cli->sk_ai, cli->ike_integ == IPSEC_INTEG_SHA1 ? 20 : 32,
                        msg, total, icv) != 0)
        return -1;
    memcpy(msg + total, icv, integ_len);
    total = (uint16_t)(total + integ_len);
    *msg_len = total;
    return 0;
}

/* Decrypt the SK payload of a received message.
 * \p msg is the IKE message with the 4-byte non-ESP marker already removed
 * (strongSwan strips the marker before processing, so the ICV does not
 * cover it either). */
static int ike_sk_decrypt(ipsec_client_t *cli, const uint8_t *msg,
                          uint16_t msg_len, const uint8_t *sk,
                          uint16_t sk_len, uint8_t *inner,
                          uint16_t inner_cap, uint16_t *inner_len,
                          uint8_t *first_type)
{
    uint8_t icv[32];
    uint8_t expected[32];
    const uint8_t *iv = sk + 4;
    const uint8_t *ct;
    uint16_t ct_len;
    uint16_t integ_len = cli->ike_integ == IPSEC_INTEG_SHA1 ? IPSEC_ESP_ICV_SHA1_LEN
                                                            : IPSEC_ESP_ICV_SHA256_LEN;
    uint8_t pad_len;
    uint8_t iv_copy[16];
    mbedtls_aes_context aes;
    mbedtls_md_type_t md_type;
    int ret;

    if (sk_len < (uint16_t)(4 + 16 + 1 + integ_len))
        return -1;
    ct = sk + 4 + 16;
    ct_len = (uint16_t)(sk_len - 4 - 16 - integ_len);
    if ((ct_len % 16) != 0)
        return -1;

    /* ICV input = the whole IKE message minus the ICV */
    memcpy(icv, msg + msg_len - integ_len, integ_len);
    md_type = cli->ike_integ == IPSEC_INTEG_SHA1 ? MBEDTLS_MD_SHA1 : MBEDTLS_MD_SHA256;
    if (mbedtls_md_hmac(mbedtls_md_info_from_type(md_type),
                        cli->sk_ar, cli->ike_integ == IPSEC_INTEG_SHA1 ? 20 : 32,
                        msg, msg_len - integ_len, expected) != 0)
        return -1;
    if (memcmp(icv, expected, integ_len) != 0) {
        LLOGD("IKE SK integrity check failed");
        return -1;
    }

    memcpy(iv_copy, iv, 16);
    mbedtls_aes_init(&aes);
    ret = mbedtls_aes_setkey_dec(&aes, cli->sk_er,
                                 cli->ike_enc == IPSEC_ENC_AES128 ? 128 : 256);
    if (ret == 0)
        ret = mbedtls_aes_crypt_cbc(&aes, MBEDTLS_AES_DECRYPT, ct_len,
                                    iv_copy, ct, inner);
    mbedtls_aes_free(&aes);
    if (ret != 0)
        return -1;

    pad_len = inner[ct_len - 1];
    if (pad_len + 1 > ct_len)
        return -1;
    *inner_len = (uint16_t)(ct_len - pad_len - 1);
    *first_type = sk[0];
    return 0;
}

/* ========== Notify helpers ========== */

typedef struct ike_notify {
    uint16_t type;
    const uint8_t *data;
    uint16_t data_len;
} ike_notify_t;

/* Walk a notify payload body; collect all notifications up to max_count */
static int ike_parse_notifies(const uint8_t *body, uint16_t body_len,
                              ike_notify_t *out, int max_count)
{
    const uint8_t *p = body;
    const uint8_t *end = body + body_len;
    int n = 0;

    while (p + 4 <= end) {
        uint8_t proto = p[0];
        uint8_t spi_size = p[1];
        uint16_t type = ike_get16(p + 2);
        const uint8_t *data = p + 4 + spi_size;
        if (data > end)
            break;
        if (n < max_count) {
            out[n].type = type;
            out[n].data = data;
            out[n].data_len = (uint16_t)(end - data);
            n++;
        }
        p = data;
        (void)proto;
    }
    return n;
}

/* Build a NAT-D notification payload (SHA-1 of SPIs|IP|port) */
static uint16_t ike_build_natd(uint8_t *p, const uint8_t *spii, const uint8_t *spir,
                               const ip4_addr_t *ip, uint16_t port, uint16_t type)
{
    uint8_t *hdr = p;
    uint8_t hash[20];
    uint8_t input[8 + 8 + 4 + 2];
    const uint8_t *ip4 = (const uint8_t *)ip;

    ike_payload_hdr(p, IPSEC_PAYLOAD_NOTIFY);
    p += 4;
    p[0] = 0; p[1] = 0;
    ike_put16(p + 2, type);
    p += 4;

    memcpy(input, spii, 8);
    memcpy(input + 8, spir, 8);
    memcpy(input + 16, ip4, 4);
    ike_put16(input + 20, port);
    mbedtls_sha1(input, sizeof(input), hash);
    memcpy(p, hash, 20);
    p += 20;

    ike_payload_len(hdr, (uint16_t)(p - hdr));
    return (uint16_t)(p - hdr);
}

static uint16_t ike_build_cookie_notify(uint8_t *p, const uint8_t *cookie, uint16_t cookie_len)
{
    uint8_t *hdr = p;
    ike_payload_hdr(p, 0);
    p += 4;
    p[0] = 0; p[1] = 0;
    ike_put16(p + 2, IPSEC_NOTIFY_COOKIE);
    p += 4;
    memcpy(p, cookie, cookie_len);
    p += cookie_len;
    ike_payload_len(hdr, (uint16_t)(p - hdr));
    return (uint16_t)(p - hdr);
}

/* ========== SA parsing ========== */

/* Extract the chosen proposal's algorithms from an SA payload body */
static int ike_parse_sa(const uint8_t *sa, uint16_t sa_len, uint8_t expect_proto,
                        uint32_t *spi_out, ipsec_ike_algs_t *algs,
                        uint8_t *esp_enc, uint8_t *esp_integ, uint16_t *esp_keylen)
{
    const uint8_t *p = sa + 4; /* skip payload header */
    const uint8_t *end = sa + sa_len;

    while (p + 8 <= end) {
        uint16_t prop_len = ike_get16(p + 2);
        uint8_t num = p[4];
        uint8_t proto = p[5];
        uint8_t spi_size = p[6];
        uint8_t num_trans = p[7];
        const uint8_t *trans_end;
        const uint8_t *t;
        uint8_t enc_found = 0, prf_found = 0, integ_found = 0, dh_found = 0, esn_found = 0;

        (void)num;
        if (prop_len < 8 || p + prop_len > end)
            return -1;
        trans_end = p + prop_len;
        t = p + 8 + spi_size;
        if (t > trans_end)
            return -1;

        if (spi_out && spi_size == 4)
            *spi_out = ike_get32(p + 8);

        while (t + 8 <= trans_end && num_trans-- > 0) {
            uint16_t tlen = ike_get16(t + 2);
            uint8_t ttype = t[4];
            uint16_t tid = ike_get16(t + 6);
            if (tlen < 8 || t + tlen > trans_end)
                return -1;

            switch (ttype) {
            case IPSEC_TRANSFORM_ENCR:
                if (tid == IPSEC_ENCR_AES_CBC) {
                    /* KEY_LENGTH attribute */
                    uint16_t keylen = 0;
                    if (tlen >= 12 && ike_get16(t + 8) == 0x800E)
                        keylen = ike_get16(t + 10);
                    if (keylen == 128 || keylen == 256) {
                        enc_found = 1;
                        if (esp_enc) *esp_enc = keylen == 128 ? IPSEC_ENC_AES128 : IPSEC_ENC_AES256;
                        if (esp_keylen) *esp_keylen = keylen;
                    }
                }
                break;
            case IPSEC_TRANSFORM_PRF:
                if (tid == IPSEC_PRF_HMAC_SHA1) {
                    prf_found = 1;
                    if (algs) algs->prf = IPSEC_PRF_SHA1;
                } else if (tid == IPSEC_PRF_HMAC_SHA2_256) {
                    prf_found = 1;
                    if (algs) algs->prf = IPSEC_PRF_SHA256;
                }
                break;
            case IPSEC_TRANSFORM_INTEG:
                if (tid == IPSEC_INTEG_HMAC_SHA1_96) {
                    integ_found = 1;
                    if (esp_integ) *esp_integ = IPSEC_INTEG_SHA1;
                    if (algs) algs->integ = IPSEC_INTEG_SHA1;
                } else if (tid == IPSEC_INTEG_HMAC_SHA2_256_128) {
                    integ_found = 1;
                    if (esp_integ) *esp_integ = IPSEC_INTEG_SHA256;
                    if (algs) algs->integ = IPSEC_INTEG_SHA256;
                }
                break;
            case IPSEC_TRANSFORM_DH:
                if (tid == IPSEC_DH_MODP_2048) {
                    dh_found = 1;
                    if (algs) algs->enc = algs->enc; /* keep */
                }
                break;
            case IPSEC_TRANSFORM_ESN:
                if (tid == IPSEC_ESN_NONE)
                    esn_found = 1;
                break;
            default:
                break;
            }
            t += tlen;
        }

        if (proto == expect_proto) {
            if (expect_proto == IPSEC_PROTO_IKE) {
                if (enc_found && prf_found && integ_found && dh_found)
                    return 0;
            } else {
                if (enc_found && integ_found)
                    return 0;
            }
        }
        p += prop_len;
    }
    return -1;
}

/* ========== NAT-T helpers ========== */

static int ipsec_get_local_ip(ipsec_client_t *cli, ip4_addr_t *ip4)
{
    luat_ip_addr_t lip;
    luat_ip_addr_t mask;
    luat_ip_addr_t gw;

    if (cli->netc && network_get_local_ip_info(cli->netc, &lip, &mask, &gw) == 0) {
        if (IP_IS_V4(&lip)) {
            *ip4 = *ip_2_ip4(&lip);
            return 0;
        }
    }
    ip4_addr_set_zero(ip4);
    return -1;
}

/* Check one NAT-D payload against the expected hash */
static int ipsec_natd_matches(const uint8_t *payload, uint16_t payload_len,
                              const uint8_t *spii, const uint8_t *spir,
                              const ip4_addr_t *ip, uint16_t port)
{
    uint8_t hash[20];
    uint8_t input[8 + 8 + 4 + 2];

    if (payload_len < 24) /* 4 hdr + 20 hash */
        return 0;
    memcpy(input, spii, 8);
    memcpy(input + 8, spir, 8);
    memcpy(input + 16, ip, 4);
    ike_put16(input + 20, port);
    mbedtls_sha1(input, sizeof(input), hash);
    return memcmp(hash, payload + 24 - 20, 20) == 0;
}

/* ========== Message sending ========== */

static int ipsec_udp_send(ipsec_client_t *cli, const uint8_t *data, uint16_t len,
                          uint16_t port)
{
    uint32_t tx_len = 0;
    int ret;

    if (!cli->netc || len == 0)
        return -1;
    ret = network_tx(cli->netc, data, len, 0, &cli->remote_ip, port, &tx_len, 0);
    return (ret >= 0 && tx_len == len) ? 0 : -1;
}

/* Dump a frame for netdrv.debug (only when debug is enabled) */
static void ipsec_dump_frame(const char *tag, const uint8_t *data, uint16_t len)
{
    char hex[128];
    uint16_t off = 0;
    while (off < len) {
        int i, n = len - off;
        if (n > 32) n = 32;
        for (i = 0; i < n; i++)
            sprintf(hex + i * 3, "%02X ", data[off + i]);
        hex[i * 3] = '\0';
        LLOGD("%s(%u@%u): %s", tag, (unsigned)len, (unsigned)off, hex);
        off = (uint16_t)(off + n);
    }
}

/* Send an IKE message and optionally arm the retransmit timer */
static int ipsec_send_msg(ipsec_client_t *cli, const uint8_t *buf, uint16_t len,
                          int retransmit)
{
    uint8_t txbuf[4 + IPSEC_IKE_TX_LEN];
    const uint8_t *tx = buf;
    uint16_t tx_len = len;
    int ret;

    if (cli->ike_port == IPSEC_ESP_PORT) {
        /* RFC 3948: non-ESP marker (4 zero bytes) before the IKE message */
        memset(txbuf, 0, 4);
        memcpy(txbuf + 4, buf, len);
        tx = txbuf;
        tx_len = (uint16_t)(len + 4);
    }
    if (cli->debug) {
        LLOGD("IKE TX port=%u len=%u phase=%d", (unsigned)cli->ike_port, tx_len, cli->phase);
        ipsec_dump_frame("IKE_TX", tx, tx_len);
    }
    ret = ipsec_udp_send(cli, tx, tx_len, cli->ike_port);
    if (ret != 0) {
        LLOGE("IKE TX failed");
        return -1;
    }
    if (retransmit) {
        memcpy(cli->last_tx, tx, tx_len);
        cli->last_tx_len = tx_len;
        cli->retrans_count = 0;
        ipsec_start_retrans(cli);
    }
    return 0;
}

static void ipsec_start_retrans(ipsec_client_t *cli)
{
    sys_timeout(IPSEC_RETRANS_BASE_MS, ipsec_retrans_timer, cli);
}

static void ipsec_cancel_retrans(ipsec_client_t *cli)
{
    sys_untimeout(ipsec_retrans_timer, cli);
    cli->retrans_count = 0;
}

/* ========== IKE_SA_INIT ========== */

static int ike_send_sa_init(ipsec_client_t *cli)
{
    uint8_t buf[IPSEC_IKE_TX_LEN];
    uint16_t len;
    uint8_t *p = buf + 28;
    uint16_t plen;
    ip4_addr_t local_ip;

    /* new SPIi unless this is a cookie retry */
    if (!cli->cookie_len) {
        uint32_t tmp;
        do {
            luat_crypto_trng((char *)&tmp, 4);
            ike_put32(cli->spii, tmp);
        } while (ike_get32(cli->spii) == 0);
    }
    memset(cli->spir, 0, 8);
    cli->pending_msgid = 0;
    cli->last_exchange = IPSEC_EXCH_IKE_SA_INIT;

    plen = ike_build_ike_sa(p);
    p[0] = IPSEC_PAYLOAD_KE;
    p += plen;

    /* KE payload */
    {
        uint8_t *ke = p;
        ike_payload_hdr(p, IPSEC_PAYLOAD_NONCE);
        p += 4;
        ike_put16(p, IPSEC_DH_MODP_2048);
        ike_put16(p + 2, 0);
        p += 4;
        {
        size_t kei_len = IPSEC_DH_PUB_LEN;
        if (ipsec_dh_make_public(&cli->dhm, cli->kei, &kei_len) != 0) {
            LLOGE("DH make_public failed");
            return -1;
        }
        cli->kei_len = (uint16_t)kei_len;
        }
        memcpy(p, cli->kei, cli->kei_len);
        p += cli->kei_len;
        ike_payload_len(ke, (uint16_t)(p - ke));
    }

    /* Ni */
    {
        uint8_t *ni = p;
        ike_payload_hdr(p, IPSEC_PAYLOAD_NOTIFY);
        p += 4;
        luat_crypto_trng((char *)cli->ni, IPSEC_NONCE_LEN);
        cli->ni_len = IPSEC_NONCE_LEN;
        memcpy(p, cli->ni, cli->ni_len);
        p += cli->ni_len;
        ike_payload_len(ni, (uint16_t)(p - ni));
    }

    ipsec_get_local_ip(cli, &local_ip);
    p += ike_build_natd(p, cli->spii, cli->spir, &local_ip, cli->ike_port,
                        IPSEC_NOTIFY_NAT_DETECTION_SOURCE);
    {
        uint8_t *natd2 = p;
        p += ike_build_natd(p, cli->spii, cli->spir,
                            ip_2_ip4(&cli->remote_ip), cli->ike_port,
                            IPSEC_NOTIFY_NAT_DETECTION_DEST);
        if (cli->cookie_len)
            p += ike_build_cookie_notify(p, cli->cookie, cli->cookie_len);
        else
            natd2[0] = 0; /* second NAT-D is the last payload */
    }

    len = (uint16_t)(p - buf);
    ike_build_header(buf, cli->spii, cli->spir, IPSEC_PAYLOAD_SA,
                     IPSEC_EXCH_IKE_SA_INIT, IPSEC_FLAG_INITIATOR, 0, len);

    /* remember the exact bytes for AUTH computation */
    memcpy(cli->sa_init_tx, buf, len);
    cli->sa_init_tx_len = len;
    return ipsec_send_msg(cli, buf, len, 1);
}

/* ========== IKE_AUTH builders ========== */

/* Message 3: SK { IDi, SAi2, TSi, TSr, CP(CFG_REQUEST) } */
static int ike_send_auth1(ipsec_client_t *cli)
{
    uint8_t buf[IPSEC_IKE_TX_LEN];
    uint8_t inner[1024];
    uint16_t inner_len;
    uint16_t msg_len;
    uint8_t *p = inner;
    uint16_t plen;
    uint32_t esp_spi;

    /* fresh outbound ESP SPI */
    luat_crypto_trng((char *)&esp_spi, 4);
    if (esp_spi == 0)
        esp_spi = 0x12345678;
    cli->esp_spi_out = esp_spi;

    cli->pending_msgid = ++cli->msgid;
    cli->last_exchange = IPSEC_EXCH_IKE_AUTH;

    plen = ike_build_idi(cli, p);
    p[0] = IPSEC_PAYLOAD_SA;
    p += plen;
    plen = ike_build_esp_sa(p, esp_spi);
    p[0] = IPSEC_PAYLOAD_TSI;
    p += plen;
    plen = ike_build_ts(p, IPSEC_PAYLOAD_TSI);
    p[0] = IPSEC_PAYLOAD_TSR;
    p += plen;
    plen = ike_build_ts(p, IPSEC_PAYLOAD_TSR);
    p[0] = IPSEC_PAYLOAD_CP;
    p += plen;
    plen = ike_build_cp_request(p);
    p[0] = 0; /* last inner payload */
    p += plen;
    inner_len = (uint16_t)(p - inner);

    if (ike_sk_encrypt(cli, buf, inner, inner_len, IPSEC_PAYLOAD_IDI, &msg_len) != 0)
        return -1;
    cli->phase = IPSEC_STATE_AUTH1_SENT;
    return ipsec_send_msg(cli, buf, msg_len, 1);
}

/* Build an EAP Identity response message */
static int ike_send_eap_identity(ipsec_client_t *cli, uint8_t eap_id)
{
    uint8_t buf[IPSEC_IKE_TX_LEN];
    uint8_t inner[512];
    uint8_t eap[300];
    uint16_t eap_len;
    uint16_t inner_len;
    uint16_t msg_len;
    size_t ulen = cli->username_len;
    uint8_t *p = inner;

    if (ulen > 250)
        ulen = 250;
    eap[0] = IPSEC_EAP_CODE_RESPONSE;
    eap[1] = eap_id;
    ike_put16(eap + 2, (uint16_t)(5 + ulen));
    eap[4] = IPSEC_EAP_TYPE_IDENTITY;
    memcpy(eap + 5, cli->username, ulen);
    eap_len = (uint16_t)(5 + ulen);

    cli->pending_msgid = ++cli->msgid;
    cli->last_exchange = IPSEC_EXCH_IKE_AUTH;
    p += ike_build_eap_payload(p, eap, eap_len);
    inner_len = (uint16_t)(p - inner);
    if (ike_sk_encrypt(cli, buf, inner, inner_len, IPSEC_PAYLOAD_EAP, &msg_len) != 0)
        return -1;
    cli->phase = IPSEC_STATE_EAP_SENT;
    return ipsec_send_msg(cli, buf, msg_len, 1);
}

/* Build an EAP-MSCHAPv2 Response message */
static int ike_send_eap_mschapv2_response(ipsec_client_t *cli, uint8_t eap_id,
                                          uint8_t mschap_id,
                                          const uint8_t *rchallenge)
{
    uint8_t buf[IPSEC_IKE_TX_LEN];
    uint8_t inner[512];
    uint8_t eap[400];
    uint8_t mschap_body[320];
    uint16_t mschap_len;
    uint16_t eap_len;
    uint16_t inner_len;
    uint16_t msg_len;
    uint8_t *p = inner;

    if (ipsec_mschapv2_make_response(cli->username, (uint16_t)cli->username_len,
                                     cli->password, (uint16_t)cli->password_len,
                                     rchallenge,
                                     cli->mschap_peer_challenge,
                                     cli->mschap_nt_response,
                                     cli->mschap_auth_response,
                                     cli->msk,
                                     mschap_body, sizeof(mschap_body), &mschap_len) != 0) {
        LLOGE("mschapv2 response build failed");
        return -1;
    }
    mschap_body[1] = mschap_id; /* echo the challenge's MS-CHAPv2-ID */
    cli->msk_valid = 1;
    cli->mschap_ready = 1;
    cli->eap_id = eap_id;

    eap[0] = IPSEC_EAP_CODE_RESPONSE;
    eap[1] = eap_id;
    ike_put16(eap + 2, (uint16_t)(5 + mschap_len));
    eap[4] = IPSEC_EAP_TYPE_MSCHAPV2;
    memcpy(eap + 5, mschap_body, mschap_len);
    eap_len = (uint16_t)(5 + mschap_len);

    cli->pending_msgid = ++cli->msgid;
    cli->last_exchange = IPSEC_EXCH_IKE_AUTH;
    p += ike_build_eap_payload(p, eap, eap_len);
    inner_len = (uint16_t)(p - inner);
    if (ike_sk_encrypt(cli, buf, inner, inner_len, IPSEC_PAYLOAD_EAP, &msg_len) != 0)
        return -1;
    cli->phase = IPSEC_STATE_EAP_SENT;
    return ipsec_send_msg(cli, buf, msg_len, 1);
}

/* Acknowledge an MS-CHAPv2 Success request (opcode 3) */
static int ike_send_mschapv2_ack(ipsec_client_t *cli, uint8_t eap_id)
{
    uint8_t buf[IPSEC_IKE_TX_LEN];
    uint8_t inner[128];
    uint8_t eap[6];
    uint16_t inner_len;
    uint16_t msg_len;
    uint8_t *p = inner;

    eap[0] = IPSEC_EAP_CODE_RESPONSE;
    eap[1] = eap_id;
    ike_put16(eap + 2, 6); /* short message: code+id+len+type+opcode */
    eap[4] = IPSEC_EAP_TYPE_MSCHAPV2;
    eap[5] = 3; /* opcode: Success */

    cli->pending_msgid = ++cli->msgid;
    cli->last_exchange = IPSEC_EXCH_IKE_AUTH;
    p += ike_build_eap_payload(p, eap, 6);
    inner_len = (uint16_t)(p - inner);
    if (ike_sk_encrypt(cli, buf, inner, inner_len, IPSEC_PAYLOAD_EAP, &msg_len) != 0)
        return -1;
    cli->phase = IPSEC_STATE_EAP_SENT;
    return ipsec_send_msg(cli, buf, msg_len, 1);
}

/* Final initiator AUTH (message 7), MSK-based shared secret */
static int ike_send_final_auth(ipsec_client_t *cli)
{
    uint8_t buf[IPSEC_IKE_TX_LEN];
    uint8_t inner[128];
    uint8_t auth[32];
    uint8_t maced_id[32];
    uint8_t signed_octets[IPSEC_IKE_TX_LEN + IPSEC_NONCE_LEN + 32];
    uint16_t signed_len;
    uint16_t inner_len;
    uint16_t msg_len;
    uint16_t plen;
    uint8_t *p = inner;

    /* MACedIDForI = prf(SK_pi, RestOfInitIDPayload) */
    if (ipsec_prf(cli->ike_prf, cli->sk_pi, ipsec_prf_len(cli->ike_prf),
                  cli->idi_rest, cli->idi_rest_len, maced_id) != 0)
        return -1;
    signed_len = cli->sa_init_tx_len;
    memcpy(signed_octets, cli->sa_init_tx, signed_len);
    memcpy(signed_octets + signed_len, cli->nr, cli->nr_len);
    signed_len = (uint16_t)(signed_len + cli->nr_len);
    memcpy(signed_octets + signed_len, maced_id, ipsec_prf_len(cli->ike_prf));
    signed_len = (uint16_t)(signed_len + ipsec_prf_len(cli->ike_prf));

    if (ipsec_compute_auth_shared(cli->ike_prf, cli->msk, 64,
                                  signed_octets, signed_len,
                                  auth, sizeof(auth)) != 0)
        return -1;
    cli->pending_msgid = ++cli->msgid;
    cli->last_exchange = IPSEC_EXCH_IKE_AUTH;
    plen = ike_build_auth_payload(p, auth, ipsec_prf_len(cli->ike_prf));
    p[0] = 0;
    p += plen;
    inner_len = (uint16_t)(p - inner);
    if (ike_sk_encrypt(cli, buf, inner, inner_len, IPSEC_PAYLOAD_AUTH, &msg_len) != 0)
        return -1;
    cli->phase = IPSEC_STATE_AUTH2_SENT;
    return ipsec_send_msg(cli, buf, msg_len, 1);
}

/* ========== CREATE_CHILD_SA (CHILD_SA rekey, no PFS) ========== */

static int ike_send_create_child_sa(ipsec_client_t *cli)
{
    uint8_t buf[IPSEC_IKE_TX_LEN];
    uint8_t inner[1024];
    uint16_t inner_len;
    uint16_t msg_len;
    uint8_t *p = inner;
    uint16_t plen;
    uint32_t esp_spi;

    luat_crypto_trng((char *)&esp_spi, 4);
    if (esp_spi == 0)
        esp_spi = 0x9abcdef0;
    cli->esp_spi_out = esp_spi;

    cli->pending_msgid = ++cli->msgid;
    cli->last_exchange = IPSEC_EXCH_CREATE_CHILD_SA;

    plen = ike_build_esp_sa(p, esp_spi);
    p[0] = IPSEC_PAYLOAD_NONCE;
    p += plen;
    {
        uint8_t *ni = p;
        ike_payload_hdr(p, IPSEC_PAYLOAD_TSI);
        p += 4;
        luat_crypto_trng((char *)cli->ni, IPSEC_NONCE_LEN);
        cli->ni_len = IPSEC_NONCE_LEN;
        memcpy(p, cli->ni, cli->ni_len);
        p += cli->ni_len;
        ike_payload_len(ni, (uint16_t)(p - ni));
    }
    plen = ike_build_ts(p, IPSEC_PAYLOAD_TSI);
    p[0] = IPSEC_PAYLOAD_TSR;
    p += plen;
    plen = ike_build_ts(p, IPSEC_PAYLOAD_TSR);
    p[0] = 0;
    p += plen;
    inner_len = (uint16_t)(p - inner);

    if (ike_sk_encrypt(cli, buf, inner, inner_len, IPSEC_PAYLOAD_SA, &msg_len) != 0)
        return -1;
    cli->phase = IPSEC_STATE_REKEY_SENT;
    cli->esp_rekey_inflight = 1;
    return ipsec_send_msg(cli, buf, msg_len, 1);
}

/* ========== DPD / Informational ========== */

static int ike_send_dpd(ipsec_client_t *cli)
{
    uint8_t buf[IPSEC_IKE_TX_LEN];
    uint16_t msg_len;

    cli->pending_msgid = ++cli->msgid;
    cli->last_exchange = IPSEC_EXCH_INFORMATIONAL;
    if (ike_sk_encrypt(cli, buf, NULL, 0, 0, &msg_len) != 0)
        return -1;
    return ipsec_send_msg(cli, buf, msg_len, 1);
}

/* Send Delete payloads (ESP SA + IKE SA) in an INFORMATIONAL request */
static int ike_send_delete(ipsec_client_t *cli)
{
    uint8_t buf[IPSEC_IKE_TX_LEN];
    uint8_t inner[512];
    uint16_t inner_len;
    uint16_t msg_len;
    uint8_t *p = inner;
    uint8_t *hdr;
    uint8_t slot = cli->esp_slot;

    /* Delete: ESP SPI */
    hdr = p;
    ike_payload_hdr(p, IPSEC_PAYLOAD_DELETE);
    p += 4;
    p[0] = IPSEC_PROTO_ESP;
    p[1] = 4;
    ike_put16(p + 2, 1);
    p += 4;
    if (cli->esp_out[slot].valid)
        ike_put32(p, cli->esp_out[slot].spi);
    else
        ike_put32(p, cli->esp_spi_out);
    p += 4;
    ike_payload_len(hdr, (uint16_t)(p - hdr));

    /* Delete: IKE SA */
    hdr = p;
    ike_payload_hdr(p, 0);
    p += 4;
    p[0] = IPSEC_PROTO_IKE;
    p[1] = 8;
    ike_put16(p + 2, 1);
    p += 4;
    memcpy(p, cli->spii, 8);
    p += 8;
    ike_payload_len(hdr, (uint16_t)(p - hdr));

    inner_len = (uint16_t)(p - inner);
    cli->pending_msgid = ++cli->msgid;
    cli->last_exchange = IPSEC_EXCH_INFORMATIONAL;
    if (ike_sk_encrypt(cli, buf, inner, inner_len, IPSEC_PAYLOAD_DELETE, &msg_len) != 0)
        return -1;
    /* no retransmit: best effort before teardown */
    return ipsec_udp_send(cli, buf, msg_len, cli->ike_port);
}

/* ========== ESP key installation ========== */

static int ipsec_install_child_sas(ipsec_client_t *cli, uint32_t in_spi,
                                   const uint8_t *keymat)
{
    uint8_t enc_len = ipsec_enc_len(cli->esp_enc);
    uint8_t integ_len = ipsec_integ_len(cli->esp_integ);
    uint8_t new_slot = cli->esp_slot ^ 1;
    const uint8_t *k = keymat;

    /* IKEv2 SPI direction: the initiator sends with the SPI the responder
     * assigned (SAr2), and receives with the SPI it proposed (SAi2). */
    ipsec_esp_sa_init(&cli->esp_out[new_slot], in_spi,
                      cli->esp_enc, cli->esp_integ, k, k + enc_len);
    k += enc_len + integ_len;
    ipsec_esp_sa_init(&cli->esp_in[new_slot], cli->esp_spi_out,
                      cli->esp_enc, cli->esp_integ, k, k + enc_len);

    /* old current SA becomes dying (kept for RX grace) */
    if (cli->esp_slot != new_slot && cli->esp_out[cli->esp_slot].valid) {
        cli->esp_out[cli->esp_slot].dying = 1;
        cli->esp_in[cli->esp_slot].dying = 1;
        cli->esp_sa_created_ms[cli->esp_slot] = sys_now();
    }
    cli->esp_slot = new_slot;
    cli->esp_sa_created_ms[new_slot] = sys_now();
    cli->esp_created_ms = sys_now();
    cli->esp_rekey_inflight = 0;
    return 0;
}

/* ========== Inbound payload processing ========== */

/* Apply CP(CFG_REPLY): virtual IPv4 + DNS */
static void ipsec_apply_cfg_reply(ipsec_client_t *cli, const uint8_t *body,
                                  uint16_t body_len)
{
    const uint8_t *p = body + 4; /* skip CFG type + reserved */
    const uint8_t *end = body + body_len;
    uint8_t got_addr = 0;

    while (p + 4 <= end) {
        uint16_t type = ike_get16(p) & 0x7FFF;
        uint16_t len = ike_get16(p + 2);
        const uint8_t *val = p + 4;
        if (val + len > end)
            break;
        switch (type) {
        case IPSEC_CFG_INTERNAL_IP4_ADDRESS:
            if (len >= 4) {
                ip4_addr_set_u32(&cli->v4, lwip_htonl(ike_get32(val)));
                got_addr = 1;
                LLOGI("CP virtual IP: %s", ip4addr_ntoa(&cli->v4));
            }
            break;
        case IPSEC_CFG_INTERNAL_IP4_NETMASK:
            if (len >= 4)
                ip4_addr_set_u32(&cli->v4mask, lwip_htonl(ike_get32(val)));
            break;
        case IPSEC_CFG_INTERNAL_IP4_DNS:
            if (len >= 4) {
                ip_addr_t dns;
                IP_ADDR4(&dns, val[0], val[1], val[2], val[3]);
                if (ip_addr_isany(&cli->dns1))
                    cli->dns1 = dns;
                else
                    cli->dns2 = dns;
            }
            break;
        default:
            break;
        }
        p = val + len;
    }
    if (got_addr)
        cli->cfg_ready = 1;
}

/* Parse an inbound IKE_AUTH response that carries the SAr2/TS/CP set */
static int ike_handle_auth2_payloads(ipsec_client_t *cli, const uint8_t *inner,
                                     uint16_t inner_len, uint8_t first_type)
{
    const uint8_t *p = inner;
    const uint8_t *end = inner + inner_len;
    uint8_t next = first_type;
    const uint8_t *sa_payload = NULL;
    const uint8_t *cp_payload = NULL;
    uint16_t sa_len = 0, cp_len = 0;

    while (next != 0) {
        uint16_t len;
        if (p + 4 > end)
            return -1;
        len = ike_get16(p + 2);
        if (len < 4 || p + len > end)
            return -1;
        switch (next) {
        case IPSEC_PAYLOAD_SA:
            sa_payload = p;
            sa_len = len;
            break;
        case IPSEC_PAYLOAD_CP:
            cp_payload = p;
            cp_len = len;
            break;
        case IPSEC_PAYLOAD_NOTIFY: {
            ike_notify_t notifies[4];
            int n = ike_parse_notifies(p + 4, (uint16_t)(len - 4), notifies, 4);
            int i;
            for (i = 0; i < n; i++) {
                if (notifies[i].type == IPSEC_NOTIFY_TS_UNACCEPTABLE) {
                    LLOGE("responder rejected our TS");
                    return -2;
                }
            }
            break;
        }
        default:
            break;
        }
        next = p[0];
        p += len;
    }

    if (!sa_payload) {
        LLOGE("final response missing SAr2");
        return -1;
    }

    {
        uint32_t in_spi = 0;
        uint8_t esp_enc = 0, esp_integ = 0;
        uint16_t esp_keylen = 0;
        ipsec_ike_algs_t algs;
        uint8_t keymat[4 * 32];
        uint16_t enc_len, integ_len;

        memset(&algs, 0, sizeof(algs));
        if (ike_parse_sa(sa_payload, sa_len, IPSEC_PROTO_ESP, &in_spi,
                         &algs, &esp_enc, &esp_integ, &esp_keylen) != 0) {
            LLOGE("failed to parse ESP SA from responder");
            return -1;
        }
        cli->esp_enc = esp_enc;
        cli->esp_integ = esp_integ;
        enc_len = ipsec_enc_len(esp_enc);
        integ_len = ipsec_integ_len(esp_integ);
        if (ipsec_derive_child_keymat(cli->ike_prf, cli->sk_d,
                                      ipsec_prf_len(cli->ike_prf),
                                      cli->ni, cli->ni_len,
                                      cli->nr, cli->nr_len,
                                      enc_len, integ_len, keymat) != 0)
            return -1;
        ipsec_install_child_sas(cli, in_spi, keymat);
    }

    if (cp_payload)
        ipsec_apply_cfg_reply(cli, cp_payload + 4, (uint16_t)(cp_len - 4));
    return 0;
}

/* Verify the responder's AUTH (shared-secret style over MSK) */
static int ike_verify_responder_auth(ipsec_client_t *cli, const uint8_t *auth,
                                     uint16_t auth_len)
{
    uint8_t maced_id[32];
    uint8_t signed_octets[IPSEC_IKE_BUF_LEN + IPSEC_NONCE_LEN + 32];
    uint8_t expected[32];
    uint16_t signed_len;
    uint16_t prf_len = ipsec_prf_len(cli->ike_prf);

    if (auth_len < prf_len)
        return -1;
    if (ipsec_prf(cli->ike_prf, cli->sk_pr, prf_len,
                  cli->idr_rest, cli->idr_rest_len, maced_id) != 0)
        return -1;

    signed_len = cli->sa_init_rx_len;
    memcpy(signed_octets, cli->sa_init_rx, signed_len);
    memcpy(signed_octets + signed_len, cli->ni, cli->ni_len);
    signed_len = (uint16_t)(signed_len + cli->ni_len);
    memcpy(signed_octets + signed_len, maced_id, prf_len);
    signed_len = (uint16_t)(signed_len + prf_len);

    if (ipsec_compute_auth_shared(cli->ike_prf, cli->msk, 64,
                                  signed_octets, signed_len,
                                  expected, sizeof(expected)) != 0)
        return -1;
    if (memcmp(expected, auth, prf_len) != 0) {
        LLOGE("responder final AUTH mismatch");
        return -1;
    }
    return 0;
}

/* Handle an EAP payload inside an IKE_AUTH response */
static void ike_handle_eap(ipsec_client_t *cli, const uint8_t *eap, uint16_t eap_len)
{
    uint8_t code, id, type = 0;
    const uint8_t *data;
    uint16_t data_len;

    if (eap_len < 4)
        return;
    code = eap[0];
    id = eap[1];
    if (ike_get16(eap + 2) != eap_len || eap_len < 4)
        return;
    if (code == IPSEC_EAP_CODE_REQUEST || code == IPSEC_EAP_CODE_RESPONSE) {
        if (eap_len < 5)
            return;
        type = eap[4];
        data = eap + 5;
        data_len = (uint16_t)(eap_len - 5);
    } else {
        data = eap + 4;
        data_len = (uint16_t)(eap_len - 4);
    }

    switch (code) {
    case IPSEC_EAP_CODE_REQUEST:
        if (type == IPSEC_EAP_TYPE_IDENTITY) {
            LLOGI("EAP Identity request");
            ike_send_eap_identity(cli, id);
        } else if (type == IPSEC_EAP_TYPE_MSCHAPV2) {
            uint8_t challenge[16];
            const char *name;
            uint16_t name_len;
            uint8_t mschap_id;
            if (data_len >= 1 && data[0] == 3) {
                /* MS-CHAPv2 Success request: verify authenticator response */
                if (cli->mschap_ready &&
                    ipsec_mschapv2_verify_success(cli->mschap_auth_response,
                                                  data, data_len) == 0) {
                    LLOGI("MS-CHAPv2 authenticator response OK");
                    ike_send_mschapv2_ack(cli, id);
                } else {
                    LLOGE("MS-CHAPv2 authenticator response mismatch");
                    ipsec_stop_internal(cli);
                    ipsec_schedule_retry(cli, "eap auth failed");
                }
            } else if (ipsec_mschapv2_parse_challenge(data, data_len, &mschap_id,
                                                      &name, &name_len,
                                                      challenge) == 0) {
                LLOGI("EAP-MSCHAPv2 challenge");
                ike_send_eap_mschapv2_response(cli, id, mschap_id, challenge);
            } else {
                LLOGE("unhandled MS-CHAPv2 request opcode %u", data_len ? data[0] : 0);
            }
        } else {
            LLOGE("unsupported EAP type %u", type);
        }
        break;
    case IPSEC_EAP_CODE_SUCCESS:
        LLOGI("EAP Success, sending final AUTH");
        if (ike_send_final_auth(cli) != 0) {
            ipsec_stop_internal(cli);
            ipsec_schedule_retry(cli, "final auth send failed");
        }
        break;
    case IPSEC_EAP_CODE_FAILURE:
        LLOGE("EAP Failure");
        ipsec_stop_internal(cli);
        ipsec_schedule_retry(cli, "eap failure");
        break;
    default:
        break;
    }
}

/* ========== Response handlers ========== */

/* IKE_SA_INIT response */
static void ike_handle_sa_init_response(ipsec_client_t *cli,
                                        const uint8_t *msg, uint16_t msg_len,
                                        uint16_t msgid,
                                        const uint8_t *datagram, uint16_t datagram_len,
                                        const luat_ip_addr_t *src_addr, uint16_t src_port)
{
    const uint8_t *sa_payload, *ke_payload, *nonce_payload, *notify_payload;
    uint16_t sa_len, ke_len, nonce_len, notify_len;
    uint8_t next = msg[16];
    ipsec_ike_algs_t algs;
    ike_notify_t notifies[12];
    int nnotify = 0;
    int i;
    int nat_source_mismatch = 0, nat_dest_mismatch = 0;
    ip4_addr_t local_ip;
    uint16_t local_port = cli->netc ? cli->netc->local_port : cli->ike_port;
    uint8_t cookie_found = 0;

    if (ike_find_payload(msg, msg_len, next, IPSEC_PAYLOAD_SA, &sa_payload, &sa_len) != 0) {
        LLOGE("IKE_SA_INIT response missing SA");
        goto fail;
    }
    if (ike_find_payload(msg, msg_len, next, IPSEC_PAYLOAD_KE, &ke_payload, &ke_len) != 0) {
        LLOGE("IKE_SA_INIT response missing KE");
        goto fail;
    }
    if (ike_find_payload(msg, msg_len, next, IPSEC_PAYLOAD_NONCE, &nonce_payload, &nonce_len) != 0) {
        LLOGE("IKE_SA_INIT response missing Ni");
        goto fail;
    }
    /* collect all notifications across every Notify payload */
    notify_payload = NULL;
    notify_len = 0;
    {
        const uint8_t *p = msg + 28;
        const uint8_t *end = msg + msg_len;
        uint8_t ntype = msg[16];
        while (ntype != 0) {
            uint16_t plen;
            if (p + 4 > end)
                break;
            plen = ike_get16(p + 2);
            if (plen < 4 || p + plen > end)
                break;
            if (ntype == IPSEC_PAYLOAD_NOTIFY) {
                int n = ike_parse_notifies(p + 4, (uint16_t)(plen - 4),
                                           notifies + nnotify, 12 - nnotify);
                nnotify += n;
            }
            ntype = p[0];
            p += plen;
        }
    }

    for (i = 0; i < nnotify; i++) {
        switch (notifies[i].type) {
        case IPSEC_NOTIFY_COOKIE:
            cookie_found = 1;
            if (notifies[i].data_len > sizeof(cli->cookie))
                goto fail;
            cli->cookie_len = notifies[i].data_len;
            memcpy(cli->cookie, notifies[i].data, cli->cookie_len);
            break;
        case IPSEC_NOTIFY_NO_PROPOSAL_CHOSEN:
            LLOGE("NO_PROPOSAL_CHOSEN");
            goto fail;
        case IPSEC_NOTIFY_USE_TRANSPORT_MODE:
            LLOGE("responder requires transport mode (unsupported)");
            goto fail;
        default:
            break;
        }
    }

    if (cookie_found) {
        LLOGI("received COOKIE, retrying IKE_SA_INIT");
        ike_send_sa_init(cli);
        return;
    }

    /* parse chosen proposal */
    memset(&algs, 0, sizeof(algs));
    algs.enc = IPSEC_ENC_AES256;
    algs.prf = IPSEC_PRF_SHA256;
    algs.integ = IPSEC_INTEG_SHA256;
    if (ike_parse_sa(sa_payload, sa_len, IPSEC_PROTO_IKE, NULL,
                     &algs, NULL, NULL, NULL) != 0) {
        LLOGE("unsupported IKE proposal from responder");
        goto fail;
    }
    cli->ike_enc = algs.enc;
    cli->ike_prf = algs.prf;
    cli->ike_integ = algs.integ;
    LLOGI("negotiated IKE: enc=%s prf=%s integ=%s",
          cli->ike_enc == IPSEC_ENC_AES128 ? "aes128" : "aes256",
          cli->ike_prf == IPSEC_PRF_SHA1 ? "sha1" : "sha256",
          cli->ike_integ == IPSEC_INTEG_SHA1 ? "sha1" : "sha256");

    /* KEr + Nr */
    if (ke_len < 8)
        goto fail;
    {
        uint16_t group = ike_get16(ke_payload + 4);
        uint16_t kelen = (uint16_t)(ke_len - 8);
        if (group != IPSEC_DH_MODP_2048 || kelen > sizeof(cli->ker)) {
            LLOGE("unexpected KE payload (group=%u len=%u)", group, kelen);
            goto fail;
        }
        memcpy(cli->ker, ke_payload + 8, kelen);
        cli->ker_len = kelen;
    }
    cli->nr_len = (uint16_t)(nonce_len - 4);
    if (cli->nr_len > sizeof(cli->nr))
        goto fail;
    memcpy(cli->nr, nonce_payload + 4, cli->nr_len);
    memcpy(cli->spir, msg + 8, 8);

    /* DH shared secret */
    if (ipsec_dh_read_public(&cli->dhm, cli->ker, cli->ker_len) != 0) {
        LLOGE("DH read_public failed");
        goto fail;
    }
    {
    size_t g_ir_len = sizeof(cli->g_ir);
    if (ipsec_dh_calc_secret(&cli->dhm, cli->g_ir, &g_ir_len) != 0) {
        LLOGE("DH calc_secret failed");
        goto fail;
    }
    cli->g_ir_len = (uint16_t)g_ir_len;
    }

    /* derive IKE keys */
    {
        uint8_t keys[7 * 32];
        uint16_t plen = ipsec_prf_len(cli->ike_prf);
        if (ipsec_derive_ike_keys(&algs, cli->ni, cli->ni_len,
                                  cli->nr, cli->nr_len,
                                  cli->g_ir, cli->g_ir_len,
                                  cli->spii, cli->spir, keys) != 0) {
            LLOGE("IKE key derivation failed");
            goto fail;
        }
        memcpy(cli->sk_d,  keys, ipsec_prf_len(cli->ike_prf));
        memcpy(cli->sk_ai, keys + 1 * ipsec_prf_len(cli->ike_prf), ipsec_prf_len(cli->ike_prf));
        memcpy(cli->sk_ar, keys + 2 * ipsec_prf_len(cli->ike_prf), ipsec_prf_len(cli->ike_prf));
        memcpy(cli->sk_ei, keys + 3 * ipsec_prf_len(cli->ike_prf), ipsec_enc_len(cli->ike_enc));
        memcpy(cli->sk_er, keys + 3 * ipsec_prf_len(cli->ike_prf) + ipsec_enc_len(cli->ike_enc),
               ipsec_enc_len(cli->ike_enc));
        memcpy(cli->sk_pi, keys + 3 * ipsec_prf_len(cli->ike_prf) + 2 * ipsec_enc_len(cli->ike_enc),
               ipsec_prf_len(cli->ike_prf));
        memcpy(cli->sk_pr, keys + 4 * ipsec_prf_len(cli->ike_prf) + 2 * ipsec_enc_len(cli->ike_enc),
               ipsec_prf_len(cli->ike_prf));
        cli->keys_valid = 1;
    }

    /* remember the response message (without the 4-byte marker, which
     * strongSwan strips on reception) for AUTH computation */
    {
        const uint8_t *rx = datagram;
        uint16_t rx_len = datagram_len;
        if (cli->ike_port == IPSEC_ESP_PORT && rx_len >= 4 &&
            rx[0] == 0 && rx[1] == 0 && rx[2] == 0 && rx[3] == 0) {
            rx += 4;
            rx_len = (uint16_t)(rx_len - 4);
        }
        memcpy(cli->sa_init_rx, rx, rx_len);
        cli->sa_init_rx_len = rx_len;
    }

    /* NAT detection */
    for (i = 0; i < nnotify; i++) {
        if (notifies[i].type == IPSEC_NOTIFY_NAT_DETECTION_SOURCE) {
            if (!ipsec_natd_matches(notifies[i].data - 4,
                                    (uint16_t)(notifies[i].data_len + 4),
                                    cli->spii, cli->spir,
                                    ip_2_ip4((ip_addr_t *)src_addr), src_port))
                nat_source_mismatch = 1;
        } else if (notifies[i].type == IPSEC_NOTIFY_NAT_DETECTION_DEST) {
            ipsec_get_local_ip(cli, &local_ip);
            if (!ipsec_natd_matches(notifies[i].data - 4,
                                    (uint16_t)(notifies[i].data_len + 4),
                                    cli->spii, cli->spir,
                                    &local_ip, local_port))
                nat_dest_mismatch = 1;
        }
    }
    if (nat_source_mismatch || nat_dest_mismatch || src_port == IPSEC_ESP_PORT) {
        cli->nat_detected = 1;
        LLOGI("NAT detected (src_mismatch=%d dest_mismatch=%d)", nat_source_mismatch, nat_dest_mismatch);
    }

    /* switch to 4500 if needed */
    if (cli->nat_detected && cli->ike_port == IPSEC_IKE_PORT) {
        if (ipsec_switch_socket(cli, IPSEC_ESP_PORT) != 0) {
            LLOGE("failed to switch to port 4500");
            goto fail;
        }
    }

    cli->phase = IPSEC_STATE_SA_INIT_SENT; /* keep, auth1 moves it on */
    if (ike_send_auth1(cli) != 0)
        goto fail;
    return;

fail:
    ipsec_stop_internal(cli);
    ipsec_schedule_retry(cli, "sa_init response");
    (void)msgid;
}

/* IKE_AUTH response (msgid 1): IDr, [CERT], AUTH, EAP */
static void ike_handle_auth1_response(ipsec_client_t *cli, const uint8_t *msg,
                                      uint16_t msg_len, uint16_t msgid)
{
    const uint8_t *sk_payload;
    uint16_t sk_len;
    uint8_t inner[IPSEC_IKE_BUF_LEN];
    uint16_t inner_len;
    uint8_t first_type;
    const uint8_t *p;
    uint8_t next;
    const uint8_t *end;
    const uint8_t *auth_payload = NULL;
    const uint8_t *idr_payload = NULL;
    const uint8_t *eap_payload = NULL;
    uint16_t auth_len = 0, idr_len = 0, eap_len = 0;
    int auth_failed = 0;

    (void)msgid;
    if (ike_find_payload(msg, msg_len, msg[16], IPSEC_PAYLOAD_SK,
                         &sk_payload, &sk_len) != 0)
        goto fail;
    if (ike_sk_decrypt(cli, msg, msg_len, sk_payload, sk_len,
                       inner, sizeof(inner), &inner_len, &first_type) != 0) {
        LLOGE("SK decrypt failed");
        goto fail;
    }

    p = inner;
    end = inner + inner_len;
    next = first_type;
    while (next != 0) {
        uint16_t len;
        if (p + 4 > end)
            goto fail;
        len = ike_get16(p + 2);
        if (len < 4 || p + len > end)
            goto fail;
        switch (next) {
        case IPSEC_PAYLOAD_IDR:
            idr_payload = p;
            idr_len = len;
            break;
        case IPSEC_PAYLOAD_CERT: {
            /* CERT: [encoding(1)][data] */
            const uint8_t *der = p + 4 + 1;
            uint16_t der_len = (uint16_t)(len - 5);
            if (p[4] == IPSEC_CERT_X509 && der_len > 0) {
                if (mbedtls_x509_crt_parse(&cli->server_cert, der, der_len) != 0) {
                    LLOGE("CERT parse failed");
                    goto fail;
                }
                cli->server_cert_valid = 1;
            }
            break;
        }
        case IPSEC_PAYLOAD_CERTREQ:
            break; /* ignore; we authenticate with EAP */
        case IPSEC_PAYLOAD_AUTH:
            auth_payload = p;
            auth_len = len;
            break;
        case IPSEC_PAYLOAD_EAP:
            eap_payload = p;
            eap_len = len;
            break;
        case IPSEC_PAYLOAD_NOTIFY: {
            ike_notify_t notifies[4];
            int n = ike_parse_notifies(p + 4, (uint16_t)(len - 4), notifies, 4);
            int i;
            for (i = 0; i < n; i++) {
                if (notifies[i].type == IPSEC_NOTIFY_AUTH_FAILED)
                    auth_failed = 1;
            }
            break;
        }
        default:
            break;
        }
        next = p[0];
        p += len;
    }

    if (auth_failed) {
        LLOGE("AUTHENTICATION_FAILED notify");
        goto fail;
    }
    if (!idr_payload || !auth_payload) {
        LLOGE("IKE_AUTH response missing IDr/AUTH");
        goto fail;
    }

    /* capture RestOfRespIDPayload */
    cli->idr_rest_len = (uint16_t)(idr_len - 4);
    if (cli->idr_rest_len > sizeof(cli->idr_rest))
        cli->idr_rest_len = sizeof(cli->idr_rest);
    memcpy(cli->idr_rest, idr_payload + 4, cli->idr_rest_len);

    /* verify server certificate chain + SAN */
    if (!cli->server_cert_valid) {
        LLOGE("no server certificate received");
        goto fail;
    }
    if (ipsec_verify_cert_chain(&cli->server_cert, cli->ca_cert_pem,
                                cli->ca_cert_pem_len, cli->san, NULL) != 0) {
        LLOGE("server certificate verification failed");
        goto fail;
    }
    LLOGI("server certificate verified (SAN=%s)", cli->san);

    /* verify server AUTH (RSA/ECDSA signature) */
    {
        uint8_t maced_id[32];
        uint8_t signed_octets[IPSEC_IKE_BUF_LEN + IPSEC_NONCE_LEN + 32];
        uint16_t signed_len;
        uint16_t prf_len = ipsec_prf_len(cli->ike_prf);

        if (ipsec_prf(cli->ike_prf, cli->sk_pr, prf_len,
                      cli->idr_rest, cli->idr_rest_len, maced_id) != 0)
            goto fail;
        signed_len = cli->sa_init_rx_len;
        memcpy(signed_octets, cli->sa_init_rx, signed_len);
        memcpy(signed_octets + signed_len, cli->ni, cli->ni_len);
        signed_len = (uint16_t)(signed_len + cli->ni_len);
        memcpy(signed_octets + signed_len, maced_id, prf_len);
        signed_len = (uint16_t)(signed_len + prf_len);

        if (ipsec_verify_auth_signature(&cli->server_cert.pk,
                                        signed_octets, signed_len,
                                        auth_payload + 4 + 4, (uint16_t)(auth_len - 8)) != 0) {
            LLOGE("server AUTH signature verification failed");
            goto fail;
        }
    }
    cli->auth_received = 1;
    LLOGI("server AUTH verified");

    if (eap_payload) {
        ike_handle_eap(cli, eap_payload + 4, (uint16_t)(eap_len - 4));
    } else {
        LLOGE("no EAP payload in IKE_AUTH response");
        goto fail;
    }
    return;

fail:
    ipsec_stop_internal(cli);
    ipsec_schedule_retry(cli, "auth1 response");
}

/* IKE_AUTH response for EAP exchanges and the final AUTH exchange */
static void ike_handle_auth_response(ipsec_client_t *cli, const uint8_t *msg,
                                     uint16_t msg_len, uint16_t msgid)
{
    const uint8_t *sk_payload;
    uint16_t sk_len;
    uint8_t inner[IPSEC_IKE_BUF_LEN];
    uint16_t inner_len;
    uint8_t first_type;
    const uint8_t *p;
    uint8_t next;
    const uint8_t *end;
    const uint8_t *auth_payload = NULL;
    const uint8_t *eap_payload = NULL;
    uint16_t auth_len = 0, eap_len = 0;

    if (ike_find_payload(msg, msg_len, msg[16], IPSEC_PAYLOAD_SK,
                         &sk_payload, &sk_len) != 0)
        goto fail;
    if (ike_sk_decrypt(cli, msg, msg_len, sk_payload, sk_len,
                       inner, sizeof(inner), &inner_len, &first_type) != 0) {
        LLOGE("SK decrypt failed");
        goto fail;
    }

    p = inner;
    end = inner + inner_len;
    next = first_type;
    while (next != 0) {
        uint16_t len;
        if (p + 4 > end)
            goto fail;
        len = ike_get16(p + 2);
        if (len < 4 || p + len > end)
            goto fail;
        switch (next) {
        case IPSEC_PAYLOAD_AUTH:
            auth_payload = p;
            auth_len = len;
            break;
        case IPSEC_PAYLOAD_EAP:
            eap_payload = p;
            eap_len = len;
            break;
        case IPSEC_PAYLOAD_NOTIFY: {
            ike_notify_t notifies[4];
            int n = ike_parse_notifies(p + 4, (uint16_t)(len - 4), notifies, 4);
            int i;
            for (i = 0; i < n; i++) {
                if (notifies[i].type == IPSEC_NOTIFY_AUTH_FAILED) {
                    LLOGE("AUTHENTICATION_FAILED notify");
                    goto fail;
                }
            }
            break;
        }
        default:
            break;
        }
        next = p[0];
        p += len;
    }

    if (eap_payload) {
        ike_handle_eap(cli, eap_payload + 4, (uint16_t)(eap_len - 4));
        return;
    }
    if (auth_payload) {
        if (ike_verify_responder_auth(cli, auth_payload + 4 + 4,
                                      (uint16_t)(auth_len - 8)) != 0)
            goto fail;
        LLOGI("responder final AUTH verified");
        if (ike_handle_auth2_payloads(cli, inner, inner_len, first_type) != 0)
            goto fail;
        if (!cli->cfg_ready) {
            LLOGE("no virtual IP from CP");
            goto fail;
        }
        ipsec_set_online(cli, 1);
        return;
    }
    goto fail;

fail:
    ipsec_stop_internal(cli);
    ipsec_schedule_retry(cli, "auth response");
    (void)msgid;
}

/* CREATE_CHILD_SA response */
static void ike_handle_rekey_response(ipsec_client_t *cli, const uint8_t *msg,
                                      uint16_t msg_len, uint16_t msgid)
{
    const uint8_t *sk_payload;
    uint16_t sk_len;
    uint8_t inner[1024];
    uint16_t inner_len;
    uint8_t first_type;
    const uint8_t *p;
    uint8_t next;
    const uint8_t *end;
    const uint8_t *sa_payload = NULL;
    uint16_t sa_len = 0;

    (void)msgid;
    if (ike_find_payload(msg, msg_len, msg[16], IPSEC_PAYLOAD_SK,
                         &sk_payload, &sk_len) != 0)
        goto fail;
    if (ike_sk_decrypt(cli, msg, msg_len, sk_payload, sk_len,
                       inner, sizeof(inner), &inner_len, &first_type) != 0)
        goto fail;

    p = inner;
    end = inner + inner_len;
    next = first_type;
    while (next != 0) {
        uint16_t len;
        if (p + 4 > end)
            goto fail;
        len = ike_get16(p + 2);
        if (len < 4 || p + len > end)
            goto fail;
        if (next == IPSEC_PAYLOAD_SA) {
            sa_payload = p;
            sa_len = len;
        } else if (next == IPSEC_PAYLOAD_NOTIFY) {
            ike_notify_t notifies[4];
            int n = ike_parse_notifies(p + 4, (uint16_t)(len - 4), notifies, 4);
            int i;
            for (i = 0; i < n; i++) {
                if (notifies[i].type == IPSEC_NOTIFY_NO_PROPOSAL_CHOSEN ||
                    notifies[i].type == IPSEC_NOTIFY_TS_UNACCEPTABLE) {
                    LLOGE("rekey rejected (notify %u)", notifies[i].type);
                    goto fail_no_retry;
                }
            }
        }
        next = p[0];
        p += len;
    }
    if (!sa_payload)
        goto fail;

    {
        uint32_t in_spi = 0;
        uint8_t esp_enc = 0, esp_integ = 0;
        uint16_t esp_keylen = 0;
        ipsec_ike_algs_t algs;
        uint8_t keymat[4 * 32];
        uint16_t enc_len, integ_len;

        memset(&algs, 0, sizeof(algs));
        if (ike_parse_sa(sa_payload, sa_len, IPSEC_PROTO_ESP, &in_spi,
                         &algs, &esp_enc, &esp_integ, &esp_keylen) != 0)
            goto fail;
        enc_len = ipsec_enc_len(esp_enc);
        integ_len = ipsec_integ_len(esp_integ);
        if (ipsec_derive_child_keymat(cli->ike_prf, cli->sk_d,
                                      ipsec_prf_len(cli->ike_prf),
                                      cli->ni, cli->ni_len,
                                      cli->nr, cli->nr_len,
                                      enc_len, integ_len, keymat) != 0)
            goto fail;
        ipsec_install_child_sas(cli, in_spi, keymat);
    }
    LLOGI("CHILD_SA rekeyed");
    cli->phase = IPSEC_STATE_ESTABLISHED;
    return;

fail_no_retry:
fail:
    cli->esp_rekey_inflight = 0;
    cli->phase = IPSEC_STATE_ESTABLISHED;
    /* keep the tunnel running on the old SA */
}

/* INFORMATIONAL response (DPD ack / delete ack) */
static void ike_handle_informational_response(ipsec_client_t *cli, uint16_t msgid)
{
    if (cli->dpd_pending && msgid == cli->pending_msgid) {
        cli->dpd_pending = 0;
        cli->last_rx_ms = sys_now();
        LLOGD("DPD ack received");
    }
}

/* ========== IKE message dispatch ========== */

static void ike_handle_message(ipsec_client_t *cli, const uint8_t *data, uint16_t len,
                               const luat_ip_addr_t *src_addr, uint16_t src_port)
{
    uint8_t *msg;
    uint16_t msg_len;
    uint16_t hdr_len;
    uint8_t extype, flags, msgid;
    const uint8_t *datagram;
    uint16_t datagram_len;

    /* strip the RFC 3948 non-ESP marker (4 zero bytes) if present */
    if (cli->ike_port == IPSEC_ESP_PORT && len >= 4 &&
        data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 0) {
        msg = (uint8_t *)data + 4;
        msg_len = (uint16_t)(len - 4);
        datagram = data; /* keep full datagram for ICV/AUTH */
        datagram_len = len;
    } else {
        msg = (uint8_t *)data;
        msg_len = len;
        datagram = data;
        datagram_len = len;
    }
    if (msg_len < 28)
        return;

    hdr_len = ike_get32(msg + 24);
    if (hdr_len > msg_len || hdr_len < 28) {
        LLOGD("RX drop: bad hdr len %u/%u", (unsigned)hdr_len, (unsigned)msg_len);
        return;
    }
    extype = msg[18];
    flags = msg[19];
    msgid = (uint8_t)ike_get32(msg + 20);

    /* SPI checks */
    if (memcmp(msg, cli->spii, 8) != 0) {
        LLOGD("RX drop: SPIi mismatch");
        return;
    }
    if (!ip_addr_isany((const ip_addr_t *)src_addr) &&
        !ip_addr_eq(&cli->remote_ip, (const ip_addr_t *)src_addr)) {
        LLOGD("RX drop: source IP mismatch");
        return;
    }
    if (src_port != IPSEC_IKE_PORT && src_port != IPSEC_ESP_PORT) {
        LLOGD("RX drop: source port %u", (unsigned)src_port);
        return;
    }
    if (flags & IPSEC_FLAG_INITIATOR) {
        LLOGD("RX drop: initiator flag set");
        return; /* we are the initiator; reject requests from peer except below */
    }

    /* response to a pending request */
    if (!(flags & IPSEC_FLAG_RESPONSE)) {
        /* peer-initiated INFORMATIONAL (e.g. DPD): answer with empty response */
        if (extype == IPSEC_EXCH_INFORMATIONAL && cli->phase == IPSEC_STATE_ESTABLISHED) {
            uint8_t resp[128];
            uint16_t rlen;
            uint8_t saved_msgid = cli->pending_msgid;
            uint8_t saved_exchange = cli->last_exchange;
            cli->pending_msgid = msgid;
            cli->last_exchange = IPSEC_EXCH_INFORMATIONAL;
            if (ike_sk_encrypt(cli, resp, NULL, 0, 0, &rlen) == 0) {
                resp[19] = IPSEC_FLAG_RESPONSE | IPSEC_FLAG_INITIATOR;
                ipsec_udp_send(cli, resp, rlen, cli->ike_port);
            }
            cli->pending_msgid = saved_msgid;
            cli->last_exchange = saved_exchange;
        }
        return;
    }

    if (msgid != cli->pending_msgid) {
        LLOGD("RX drop: msgid %u != pending %u", (unsigned)msgid,
              (unsigned)cli->pending_msgid);
        return;
    }
    ipsec_cancel_retrans(cli);
    cli->last_rx_ms = sys_now();

    switch (cli->phase) {
    case IPSEC_STATE_SA_INIT_SENT:
        if (extype == IPSEC_EXCH_IKE_SA_INIT)
            ike_handle_sa_init_response(cli, msg, msg_len, msgid,
                                        datagram, datagram_len,
                                        src_addr, src_port);
        break;
    case IPSEC_STATE_AUTH1_SENT:
        if (extype == IPSEC_EXCH_IKE_AUTH)
            ike_handle_auth1_response(cli, msg, msg_len, msgid);
        break;
    case IPSEC_STATE_EAP_SENT:
    case IPSEC_STATE_AUTH2_SENT:
        if (extype == IPSEC_EXCH_IKE_AUTH)
            ike_handle_auth_response(cli, msg, msg_len, msgid);
        break;
    case IPSEC_STATE_REKEY_SENT:
        if (extype == IPSEC_EXCH_CREATE_CHILD_SA)
            ike_handle_rekey_response(cli, msg, msg_len, msgid);
        break;
    case IPSEC_STATE_ESTABLISHED:
        if (extype == IPSEC_EXCH_INFORMATIONAL)
            ike_handle_informational_response(cli, msgid);
        break;
    default:
        break;
    }
}

/* ========== Transport (adapter) ========== */

static int32_t ipsec_netc_callback(void *pData, void *pParam)
{
    OS_EVENT *event = (OS_EVENT *)pData;
    ipsec_client_t *cli = (ipsec_client_t *)pParam;
    if (!event || !cli || !cli->netc)
        return -1;

    if (event->ID == EV_NW_RESULT_EVENT) {
        uint8_t buf[IPSEC_IKE_BUF_LEN];
        uint32_t rx_len = 0;
        luat_ip_addr_t src_addr;
        uint16_t src_port = 0;
        int ret = network_rx(cli->netc, buf, sizeof(buf), 0,
                             &src_addr, &src_port, &rx_len);
        if (ret == 0 && rx_len > 0) {
            ipsec_rx_msg_t *msg = (ipsec_rx_msg_t *)luat_heap_malloc(
                sizeof(ipsec_rx_msg_t) + rx_len);
            if (msg == NULL)
                return 0;
            msg->cli = cli;
            msg->src_addr = src_addr;
            msg->src_port = src_port;
            msg->len = (uint16_t)rx_len;
            memcpy(msg->data, buf, rx_len);
            if (tcpip_callback_with_block(ipsec_do_rx, msg, 0) != ERR_OK)
                luat_heap_free(msg);
        }
    } else if (event->ID == EV_NW_RESULT_CLOSE || event->Param1 != 0) {
        cli->transport_err = 1;
    }
    return 0;
}

static void ipsec_do_rx(void *arg)
{
    ipsec_rx_msg_t *msg = (ipsec_rx_msg_t *)arg;
    if (msg && msg->cli) {
        ipsec_client_t *cli = msg->cli;
        if (cli->started) {
            if (cli->debug)
                ipsec_dump_frame("UDP_RX", msg->data, msg->len);
            if (cli->ike_port == IPSEC_ESP_PORT && msg->len >= 4 &&
                !(msg->data[0] == 0 && msg->data[1] == 0 &&
                  msg->data[2] == 0 && msg->data[3] == 0)) {
                /* ESP-in-UDP */
                uint8_t inner[1600];
                uint16_t inner_len = 0;
                int i;
                for (i = 0; i < 2; i++) {
                    ipsec_esp_sa_t *sa = &cli->esp_in[i];
                    if (!sa->valid)
                        continue;
                    if (ipsec_esp_decrypt(sa, msg->data, msg->len,
                                          inner, &inner_len) == 0) {
                        struct pbuf *ip = pbuf_alloc(PBUF_IP, inner_len, PBUF_RAM);
                        if (ip) {
                            memcpy(ip->payload, inner, inner_len);
                            cli->netif.input(ip, &cli->netif);
                        }
                        cli->last_rx_ms = sys_now();
                        if (cli->dpd_pending)
                            cli->dpd_pending = 0;
                        break;
                    }
                }
            } else {
                ike_handle_message(cli, msg->data, msg->len,
                                   &msg->src_addr, msg->src_port);
            }
        }
    }
    luat_heap_free(msg);
}

/* ========== Virtual netif ========== */

static err_t ipsec_netif_output_ip4(struct netif *n, struct pbuf *p,
                                    const ip4_addr_t *addr)
{
    ipsec_client_t *cli = (ipsec_client_t *)n->state;
    uint8_t buf[1600];
    uint8_t out[1600];
    uint16_t outlen = 0;
    uint16_t plen;
    uint32_t tx_len = 0;
    uint8_t slot;

    LWIP_UNUSED_ARG(addr);
    if (!cli || !cli->online)
        return ERR_IF;
    slot = cli->esp_slot;
    if (!cli->esp_out[slot].valid)
        return ERR_IF;
    plen = p->tot_len;
    if (plen > 1400)
        return ERR_VAL;
    pbuf_copy_partial(p, buf, plen, 0);
    if (ipsec_esp_encrypt(&cli->esp_out[slot], buf, plen, out, &outlen) != 0)
        return ERR_IF;
    if (cli->debug)
        LLOGD("ESP TX len=%u -> %u", plen, outlen);
    if (network_tx(cli->netc, out, outlen, 0, &cli->remote_ip,
                   IPSEC_ESP_PORT, &tx_len, 0) < 0) {
        LLOGE("ESP TX network_tx failed");
        return ERR_IF;
    }
    if (cli->debug && tx_len != outlen)
        LLOGD("ESP TX partial %u/%u", (unsigned)tx_len, (unsigned)outlen);
    return ERR_OK;
}

#if LWIP_IPV6
static err_t ipsec_netif_output_ip6(struct netif *n, struct pbuf *p,
                                    const ip6_addr_t *addr)
{
    LWIP_UNUSED_ARG(n); LWIP_UNUSED_ARG(p); LWIP_UNUSED_ARG(addr);
    return ERR_VAL; /* IPv6 inside tunnel not supported yet */
}
#endif

static err_t ipsec_netif_init(struct netif *n)
{
    ipsec_client_t *cli = (ipsec_client_t *)n->state;
    n->mtu = cli->mtu ? cli->mtu : IPSEC_DEFAULT_MTU;
    n->flags = NETIF_FLAG_POINTTOPOINT | NETIF_FLAG_NOARP | NETIF_FLAG_LINK_UP;
    n->output = ipsec_netif_output_ip4;
#if LWIP_IPV6
    n->output_ip6 = ipsec_netif_output_ip6;
#endif
    n->name[0] = 'i';
    n->name[1] = 'p';
    return ERR_OK;
}

static void ipsec_attach_netif(ipsec_client_t *cli)
{
    if (cli->netif_added)
        return;
    if (cli->adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY)
        cli->adapter_index = NW_ADAPTER_INDEX_LWIP_USER0;
#if LWIP_VERSION_MAJOR >= 2 && LWIP_VERSION_MINOR >= 1
    netif_add(&cli->netif, IP4_ADDR_ANY4, IP4_ADDR_ANY4, IP4_ADDR_ANY4,
              cli, ipsec_netif_init, netif_input);
#else
    {
        ip4_addr_t a, m, g;
        ip4_addr_set_zero(&a); ip4_addr_set_zero(&m); ip4_addr_set_zero(&g);
        netif_add(&cli->netif, &a, &m, &g, cli, ipsec_netif_init, netif_input);
    }
#endif
    netif_set_up(&cli->netif);
    netif_set_link_up(&cli->netif);
    net_lwip2_set_netif(cli->adapter_index, &cli->netif);
    net_lwip2_register_adapter(cli->adapter_index);
    cli->netif_added = 1;
}

/* ========== Online / offline ========== */

static void ipsec_set_online(ipsec_client_t *cli, int online)
{
    if (online && !cli->online) {
        cli->online = 1;
        cli->online_ms = sys_now();
        cli->esp_created_ms = sys_now();
        netif_set_addr(&cli->netif, &cli->v4, &cli->v4mask,
                       &cli->v4); /* point-to-point: gw = self */
        netif_set_up(&cli->netif);
        netif_set_link_up(&cli->netif);
        netif_set_default(&cli->netif);
        if (!ip_addr_isany(&cli->dns1))
            network_set_dns_server(cli->adapter_index, 0, (luat_ip_addr_t *)&cli->dns1);
        if (!ip_addr_isany(&cli->dns2))
            network_set_dns_server(cli->adapter_index, 1, (luat_ip_addr_t *)&cli->dns2);
        cli->phase = IPSEC_STATE_ESTABLISHED;
        LLOGI("IPsec tunnel online, v4=%s", ip4addr_ntoa(&cli->v4));
        if (cli->status_cb)
            cli->status_cb(cli, 0, cli->user_data);
    } else if (!online && cli->online) {
        cli->online = 0;
        if (netif_default == &cli->netif)
            netif_set_default(NULL);
        netif_set_link_down(&cli->netif);
        netif_set_down(&cli->netif);
        if (cli->status_cb)
            cli->status_cb(cli, -1, cli->user_data);
    }
}

/* ========== Socket management ========== */

static int ipsec_open_socket(ipsec_client_t *cli, uint16_t local_port,
                             uint16_t remote_port)
{
    int err;

    cli->netc = network_alloc_ctrl(cli->transport_index);
    if (!cli->netc) {
        LLOGE("netc alloc fail");
        return -1;
    }
    network_init_ctrl(cli->netc, NULL, ipsec_netc_callback, cli);
    network_set_base_mode(cli->netc, 0, 10000, 0, 0, 0, 0); /* UDP */
    if (network_set_local_port(cli->netc, local_port) != 0 && local_port != 0) {
        /* port busy: fall back to ephemeral */
        network_set_local_port(cli->netc, 0);
    }
    err = network_connect(cli->netc, NULL, 0, &cli->remote_ip, remote_port, 0);
    if (err < 0) {
        LLOGE("netc connect fail");
        network_force_close_socket(cli->netc);
        network_release_ctrl(cli->netc);
        cli->netc = NULL;
        return -1;
    }
    cli->netc->state = NW_STATE_ONLINE;
    return 0;
}

static void ipsec_close_socket(ipsec_client_t *cli)
{
    if (cli->netc) {
        network_ctrl_t *netc = cli->netc;
        cli->netc = NULL;
        network_close(netc, 0);
        network_force_close_socket(netc);
        network_release_ctrl(netc);
    }
}

static int ipsec_switch_socket(ipsec_client_t *cli, uint16_t port)
{
    ipsec_close_socket(cli);
    if (ipsec_open_socket(cli, port, port) != 0)
        return -1;
    cli->ike_port = port;
    LLOGI("switched to port %u", port);
    return 0;
}

/* ========== Timers ========== */

static void ipsec_retrans_timer(void *arg)
{
    ipsec_client_t *cli = (ipsec_client_t *)arg;
    if (!cli || !cli->started)
        return;
    if (cli->retrans_count >= IPSEC_RETRANS_MAX) {
        LLOGE("IKE request timed out (msgid=%u phase=%d)",
              (unsigned)cli->pending_msgid, cli->phase);
        ipsec_stop_internal(cli);
        ipsec_schedule_retry(cli, "request timeout");
        return;
    }
    cli->retrans_count++;
    LLOGD("IKE retransmit %u (msgid=%u)", (unsigned)cli->retrans_count,
          (unsigned)cli->pending_msgid);
    ipsec_udp_send(cli, cli->last_tx, cli->last_tx_len, cli->ike_port);
    sys_timeout(IPSEC_RETRANS_BASE_MS << (cli->retrans_count > 3 ? 3 : cli->retrans_count),
                ipsec_retrans_timer, cli);
}

static void ipsec_tick_timer(void *arg)
{
    ipsec_client_t *cli = (ipsec_client_t *)arg;
    uint32_t now = sys_now();

    if (!cli || !cli->started)
        return;

    /* transport error -> teardown + retry */
    if (cli->transport_err) {
        cli->transport_err = 0;
        LLOGW("transport socket error, scheduling retry");
        ipsec_stop_internal(cli);
        ipsec_schedule_retry(cli, "transport error");
        return;
    }

    if (cli->online) {
        /* DPD */
        if (now - cli->last_rx_ms >= IPSEC_DPD_INTERVAL_MS && !cli->dpd_pending) {
            cli->dpd_pending = 1;
            cli->dpd_sent_ms = now;
            LLOGD("sending DPD");
            ike_send_dpd(cli);
        } else if (cli->dpd_pending &&
                   now - cli->dpd_sent_ms >= IPSEC_DPD_INTERVAL_MS) {
            if (cli->dpd_pending >= IPSEC_DPD_MAX_PENDING) {
                LLOGE("DPD timeout, tearing down");
                ipsec_stop_internal(cli);
                ipsec_schedule_retry(cli, "dpd timeout");
                return;
            }
            cli->dpd_pending++;
            cli->dpd_sent_ms = now;
            ike_send_dpd(cli);
        }

        /* CHILD_SA rekey */
        if (!cli->esp_rekey_inflight &&
            now - cli->esp_created_ms >= IPSEC_ESP_LIFETIME_MS) {
            LLOGI("ESP SA lifetime reached, rekeying CHILD_SA");
            ike_send_create_child_sa(cli);
        }

        /* IKE SA lifetime -> full rebuild */
        if (now - cli->online_ms >= IPSEC_IKE_LIFETIME_MS) {
            LLOGI("IKE SA lifetime reached, full rebuild");
            ipsec_stop_internal(cli);
            ipsec_schedule_retry(cli, "ike lifetime");
            return;
        }
    }

    /* free dying SAs after grace */
    {
        int i;
        for (i = 0; i < 2; i++) {
            if (cli->esp_in[i].dying &&
                now - cli->esp_sa_created_ms[i] >= IPSEC_DYING_SA_GRACE_MS) {
                memset(&cli->esp_in[i], 0, sizeof(cli->esp_in[i]));
                memset(&cli->esp_out[i], 0, sizeof(cli->esp_out[i]));
            }
        }
    }

    sys_timeout(IPSEC_TICK_MS, ipsec_tick_timer, cli);
}

static void ipsec_keepalive_timer(void *arg)
{
    ipsec_client_t *cli = (ipsec_client_t *)arg;
    uint8_t keepalive = 0xFF;
    if (!cli || !cli->started)
        return;
    if (cli->nat_detected && cli->online)
        ipsec_udp_send(cli, &keepalive, 1, IPSEC_ESP_PORT);
    sys_timeout(IPSEC_KEEPALIVE_MS, ipsec_keepalive_timer, cli);
}

static uint32_t ipsec_next_backoff_ms(ipsec_client_t *cli)
{
    uint32_t base = cli->retry_base_ms ? cli->retry_base_ms : 1000;
    uint32_t max = cli->retry_max_ms ? cli->retry_max_ms : 60000;
    uint32_t delay;
    if (max < base)
        max = base;
    if (cli->retry_attempt >= 31)
        return max;
    delay = base << cli->retry_attempt;
    if (delay < base)
        return max;
    return delay > max ? max : delay;
}

static void ipsec_schedule_retry(ipsec_client_t *cli, const char *reason)
{
    uint32_t delay;
    if (!cli || !cli->retry_enable || cli->retry_timer_active || cli->user_close)
        return;
    delay = ipsec_next_backoff_ms(cli);
    if (!ipsec_transport_is_online(cli))
        delay = cli->retry_base_ms ? cli->retry_base_ms : 1000;
    cli->retry_timer_active = 1;
    cli->retry_attempt++;
    LLOGW("schedule retry in %u ms (%s)", (unsigned)delay, reason ? reason : "unknown");
    sys_timeout(delay, ipsec_retry_timer, cli);
}

static void ipsec_retry_timer(void *arg)
{
    ipsec_client_t *cli = (ipsec_client_t *)arg;
    if (!cli)
        return;
    cli->retry_timer_active = 0;
    if (cli->started)
        return;
    ipsec_client_start(cli);
}

static int ipsec_transport_is_online(ipsec_client_t *cli)
{
    int i;
    for (i = 0; i < NW_ADAPTER_QTY; i++) {
        if (i == cli->adapter_index)
            continue;
        if (luat_netdrv_is_ready(i))
            return 1;
    }
    if (cli->transport_index < NW_ADAPTER_QTY &&
        cli->transport_index != cli->adapter_index) {
        if (network_check_ready(NULL, cli->transport_index))
            return 1;
    }
    return 0;
}

/* ========== Lifecycle ========== */

static void ipsec_reset_session(ipsec_client_t *cli)
{
    cli->phase = IPSEC_STATE_IDLE;
    cli->msgid = 0;
    cli->pending_msgid = 0;
    cli->nat_detected = 0;
    cli->cookie_len = 0;
    memset(cli->spir, 0, 8);
    cli->ni_len = 0;
    cli->nr_len = 0;
    cli->kei_len = 0;
    cli->ker_len = 0;
    cli->g_ir_len = 0;
    cli->keys_valid = 0;
    cli->server_cert_valid = 0;
    cli->auth_received = 0;
    cli->msk_valid = 0;
    cli->mschap_ready = 0;
    cli->cfg_ready = 0;
    cli->dpd_pending = 0;
    cli->esp_rekey_inflight = 0;
    cli->esp_slot = 0;
    memset(cli->esp_in, 0, sizeof(cli->esp_in));
    memset(cli->esp_out, 0, sizeof(cli->esp_out));
    memset(&cli->v4, 0, sizeof(cli->v4));
    memset(&cli->v4mask, 0, sizeof(cli->v4mask));
    ip_addr_set_zero(&cli->dns1);
    ip_addr_set_zero(&cli->dns2);
    mbedtls_x509_crt_free(&cli->server_cert);
    mbedtls_x509_crt_init(&cli->server_cert);
    mbedtls_dhm_free(&cli->dhm);
    mbedtls_dhm_init(&cli->dhm);
    ipsec_dh_set_group14(&cli->dhm);
}

static int ipsec_start_internal(ipsec_client_t *cli)
{
    if (ip_addr_isany(&cli->remote_ip)) {
        LLOGE("remote ip missing");
        return -2;
    }
    if (!ipsec_transport_is_online(cli)) {
        LLOGW("transport offline, deferring start");
        return -6;
    }

    ipsec_attach_netif(cli);
    ipsec_reset_session(cli);
    /* start on 4500 directly when the gateway port is 4500 (NAT-T from the start) */
    cli->ike_port = (cli->remote_port == IPSEC_ESP_PORT) ? IPSEC_ESP_PORT : IPSEC_IKE_PORT;
    cli->last_rx_ms = sys_now();

    if (ipsec_open_socket(cli, cli->ike_port, cli->ike_port) != 0)
        return -3;

    if (ike_send_sa_init(cli) != 0) {
        ipsec_close_socket(cli);
        return -4;
    }
    cli->phase = IPSEC_STATE_SA_INIT_SENT;
    cli->started = 1;
    cli->retry_attempt = 0;
    cli->user_close = 0;
    sys_timeout(IPSEC_TICK_MS, ipsec_tick_timer, cli);
    sys_timeout(IPSEC_KEEPALIVE_MS, ipsec_keepalive_timer, cli);
    LLOGI("IPsec client started, connecting to %s:%u ...",
          ipaddr_ntoa(&cli->remote_ip), (unsigned)cli->remote_port);
    return 0;
}

static void ipsec_do_start(void *arg)
{
    ipsec_client_t *cli = (ipsec_client_t *)arg;
    int ret = ipsec_start_internal(cli);
    if (ret != 0) {
        LLOGE("ipsec start internal failed: %d", ret);
        ipsec_stop_internal(cli);
        ipsec_schedule_retry(cli, "start failed");
    }
}

int ipsec_client_start(ipsec_client_t *cli)
{
    err_t err;
    if (!cli)
        return -1;
    if (cli->started)
        return 0;
    if (cli->retry_timer_active)
        return -2;

    cli->started = 1;
    err = tcpip_callback_with_block(ipsec_do_start, cli, 0);
    if (err != ERR_OK) {
        cli->started = 0;
        LLOGE("tcpip callback fail: %d", err);
        return -5;
    }
    return 0;
}

static void ipsec_stop_internal(ipsec_client_t *cli)
{
    if (!cli)
        return;
    if (cli->tearing_down)
        return;
    cli->tearing_down = 1;

    /* best-effort Delete */
    if (cli->keys_valid && cli->online)
        ike_send_delete(cli);

    ipsec_cancel_retrans(cli);
    sys_untimeout(ipsec_tick_timer, cli);
    sys_untimeout(ipsec_keepalive_timer, cli);
    sys_untimeout(ipsec_retry_timer, cli);
    cli->retry_timer_active = 0;

    ipsec_set_online(cli, 0);
    ipsec_close_socket(cli);
    ipsec_reset_session(cli);
    cli->started = 0;
    cli->tearing_down = 0;
}

static void ipsec_do_stop(void *arg)
{
    ipsec_client_t *cli = (ipsec_client_t *)arg;
    if (!cli)
        return;
    ipsec_stop_internal(cli);
    cli->user_close = 0;
}

void ipsec_client_stop(ipsec_client_t *cli)
{
    if (!cli)
        return;
    cli->user_close = 1;
    tcpip_callback_with_block(ipsec_do_stop, cli, 0);
}

void ipsec_client_set_debug(ipsec_client_t *cli, int enable)
{
    if (cli)
        cli->debug = enable ? 1 : 0;
}

int ipsec_client_is_ready(ipsec_client_t *cli)
{
    return cli ? (cli->online ? 1 : 0) : 0;
}

/* ========== Init ========== */

int ipsec_client_init(ipsec_client_t *cli, const ipsec_client_cfg_t *cfg)
{
    if (!cli || !cfg)
        return -1;

    memset(cli, 0, sizeof(*cli));
    cli->remote_ip = cfg->remote_ip;
    cli->remote_port = cfg->remote_port ? cfg->remote_port : IPSEC_IKE_PORT;
    cli->mtu = cfg->mtu ? cfg->mtu : IPSEC_DEFAULT_MTU;
    cli->adapter_index = cfg->adapter_index;
    cli->transport_index = cfg->transport_index;
    cli->retry_enable = cfg->retry_enable;
    cli->retry_base_ms = cfg->retry_base_ms;
    cli->retry_max_ms = cfg->retry_max_ms;
    cli->status_cb = cfg->status_cb;
    cli->user_data = cfg->user_data;
    cli->ike_port = IPSEC_IKE_PORT;
    cli->san = cfg->san;

    if (cfg->username && cfg->username_len > 0) {
        cli->username = (char *)luat_heap_malloc(cfg->username_len);
        if (!cli->username)
            return -1;
        memcpy(cli->username, cfg->username, cfg->username_len);
        cli->username_len = cfg->username_len;
    }
    if (cfg->password && cfg->password_len > 0) {
        cli->password = (char *)luat_heap_malloc(cfg->password_len);
        if (!cli->password)
            return -1;
        memcpy(cli->password, cfg->password, cfg->password_len);
        cli->password_len = cfg->password_len;
    }
    if (cfg->ca_cert_pem && cfg->ca_cert_pem_len > 0) {
        /* keep the NUL terminator so mbedtls treats it as PEM */
        cli->ca_cert_pem = (char *)luat_heap_malloc(cfg->ca_cert_pem_len + 1);
        if (!cli->ca_cert_pem)
            return -1;
        memcpy(cli->ca_cert_pem, cfg->ca_cert_pem, cfg->ca_cert_pem_len);
        cli->ca_cert_pem[cfg->ca_cert_pem_len] = '\0';
        cli->ca_cert_pem_len = cfg->ca_cert_pem_len + 1;
    }
    if (cfg->san) {
        size_t sl = strlen(cfg->san);
        cli->san = (char *)luat_heap_malloc(sl + 1);
        if (!cli->san)
            return -1;
        memcpy(cli->san, cfg->san, sl + 1);
    } else if (!cli->san) {
        cli->san = (char *)luat_heap_malloc(32);
        if (!cli->san)
            return -1;
        snprintf(cli->san, 32, "%s", ipaddr_ntoa(&cli->remote_ip));
    }

    mbedtls_x509_crt_init(&cli->server_cert);
    mbedtls_dhm_init(&cli->dhm);
    if (ipsec_dh_set_group14(&cli->dhm) != 0) {
        LLOGE("DH group setup failed");
        return -1;
    }
    if (ipsec_mschapv2_self_test() != 0) {
        LLOGE("MS-CHAPv2 self test failed");
        return -1;
    }
    ip_addr_set_zero(&cli->dns1);
    ip_addr_set_zero(&cli->dns2);
    return 0;
}
