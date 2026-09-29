/* SRTP keying and packet protection shared by SDES and DTLS-SRTP. */
#ifndef LUAT_VOIP_SECURITY_H
#define LUAT_VOIP_SECURITY_H

#include <stddef.h>
#include <stdint.h>

#define LUAT_VOIP_SECURITY_KEY_BYTES 30U
#define LUAT_VOIP_SECURITY_KEY_TEXT 41U
#define LUAT_VOIP_SECURITY_FINGERPRINT_TEXT 96U
#define LUAT_VOIP_SECURITY_TAG_BYTES 10U
#define LUAT_VOIP_SECURITY_DATAGRAM_MAX 4096U
#define LUAT_VOIP_SECURITY_TIMEOUT_MS 15000U
#define LUAT_VOIP_SECURITY_SUITE "AES_CM_128_HMAC_SHA1_80"

typedef struct luat_voip_security luat_voip_security_t;
typedef struct luat_voip_security_identity luat_voip_security_identity_t;

typedef enum {
    LUAT_VOIP_SECURITY_NONE = 0,
    LUAT_VOIP_SECURITY_SDES,
    LUAT_VOIP_SECURITY_DTLS
} luat_voip_security_mode_t;

typedef enum {
    LUAT_VOIP_SECURITY_NEW = 0,
    LUAT_VOIP_SECURITY_HANDSHAKING,
    LUAT_VOIP_SECURITY_READY,
    LUAT_VOIP_SECURITY_FAILED
} luat_voip_security_state_t;

enum {
    LUAT_VOIP_SECURITY_OK = 0,
    LUAT_VOIP_SECURITY_PENDING = 1,
    LUAT_VOIP_SECURITY_E_INVALID = -1,
    LUAT_VOIP_SECURITY_E_MEMORY = -2,
    LUAT_VOIP_SECURITY_E_UNSUPPORTED = -3,
    LUAT_VOIP_SECURITY_E_CRYPTO = -4,
    LUAT_VOIP_SECURITY_E_STATE = -5,
    LUAT_VOIP_SECURITY_E_TIMEOUT = -6,
    LUAT_VOIP_SECURITY_E_FINGERPRINT = -7,
    LUAT_VOIP_SECURITY_E_PROFILE = -8,
    LUAT_VOIP_SECURITY_E_AUTH = -9,
    LUAT_VOIP_SECURITY_E_REPLAY = -10,
    LUAT_VOIP_SECURITY_E_IO = -11
};

typedef struct {
    luat_voip_security_mode_t mode;
    char key[LUAT_VOIP_SECURITY_KEY_TEXT]; /* SDES base64 key + salt. Sensitive. */
    char fingerprint[LUAT_VOIP_SECURITY_FINGERPRINT_TEXT]; /* SHA-256, colon hex. */
} luat_voip_security_info_t;

typedef struct {
    const char *suite;       /* SDES: exactly LUAT_VOIP_SECURITY_SUITE. */
    const char *key;         /* SDES: base64, exactly 30 decoded bytes. */
    const char *fingerprint; /* DTLS: SHA-256 colon hex. */
    uint8_t dtls_client;     /* Local negotiated setup: active=1, passive=0. */
} luat_voip_security_remote_t;

/** Raw UDP datagram sender: return len on success, 0 when temporarily unavailable,
 * or a negative value on failure.
 * The callback must consume/copy bytes before returning; it must not reenter ctx. */
typedef int (*luat_voip_security_send_t)(void *opaque, const uint8_t *data, size_t len);

/** Create a runtime P-256 DTLS identity. Refcounted; never stores keys on disk. */
luat_voip_security_identity_t *luat_voip_security_identity_create(int *error);
void luat_voip_security_identity_retain(luat_voip_security_identity_t *identity);
void luat_voip_security_identity_release(luat_voip_security_identity_t *identity);

/** Create local keying material. DTLS retains identity; NULL creates one. */
luat_voip_security_t *luat_voip_security_create(luat_voip_security_mode_t mode,
        luat_voip_security_identity_t *identity, int *error);
/** Fresh negotiation with identical local key/identity, no remote or runtime state. */
luat_voip_security_t *luat_voip_security_clone_local(const luat_voip_security_t *source, int *error);
void luat_voip_security_retain(luat_voip_security_t *ctx);
void luat_voip_security_release(luat_voip_security_t *ctx);
int luat_voip_security_info(const luat_voip_security_t *ctx, luat_voip_security_info_t *info);
/** Configure a NEW context once, before handing it to the VoIP worker. */
int luat_voip_security_set_remote(luat_voip_security_t *ctx, const luat_voip_security_remote_t *remote);
int luat_voip_security_configured(const luat_voip_security_t *ctx);

/** Worker-only APIs. start returns OK for SDES or PENDING for DTLS.
 * Refcount operations alone are thread safe; all runtime calls are serialized
 * by the VoIP worker. Keep a worker reference until callbacks stop. */
int luat_voip_security_start(luat_voip_security_t *ctx, luat_voip_security_send_t send, void *opaque);
/** Drive nonblocking handshake/retransmission, including after READY for final-flight retries.
 * Call after feed and at least every 50 ms while HANDSHAKING. */
int luat_voip_security_step(luat_voip_security_t *ctx);
/** Copy one complete DTLS datagram. Call step before feeding another datagram. */
int luat_voip_security_feed(luat_voip_security_t *ctx, const uint8_t *data, size_t len);
int luat_voip_security_is_dtls(const uint8_t *data, size_t len);
luat_voip_security_state_t luat_voip_security_state(const luat_voip_security_t *ctx);
luat_voip_security_mode_t luat_voip_security_mode(const luat_voip_security_t *ctx);
int luat_voip_security_error(const luat_voip_security_t *ctx);
const char *luat_voip_security_error_name(int error);
/** In-place RTP protection. capacity must include TAG_BYTES beyond plaintext.
 * Once protected, the RTP packet index is consumed even if UDP send fails. */
int luat_voip_security_protect(luat_voip_security_t *ctx, uint8_t *packet, size_t *length, size_t capacity);
int luat_voip_security_unprotect(luat_voip_security_t *ctx, uint8_t *packet, size_t *length);

#endif
