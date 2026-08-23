#ifndef LUAT_PC_HTTP_UTEST_H
#define LUAT_PC_HTTP_UTEST_H

#include <stddef.h>
#include <stdint.h>

typedef struct luat_pc_http_utest_server luat_pc_http_utest_server_t;

/* Configuration for the local HTTP/HTTPS test server. */
typedef struct {
    int use_tls;                  /* 0 = plain HTTP, 1 = HTTPS (TLS stream) */
    const uint8_t *ca_pem;        /* CA certificate PEM (TLS mode) */
    size_t ca_pem_len;
    const uint8_t *srv_cert_pem;  /* Server certificate PEM (TLS mode) */
    size_t srv_cert_pem_len;
    const uint8_t *srv_key_pem;   /* Server private key PEM (TLS mode) */
    size_t srv_key_pem_len;
} luat_pc_http_utest_cfg_t;

/* Start the helper server thread. Returns 0 on success. */
int luat_pc_http_utest_server_start(luat_pc_http_utest_server_t **out_server,
                                    const luat_pc_http_utest_cfg_t *cfg);

/* Wait until the server is ready (listening). Returns 0 on success,
 * writes the ephemeral port to *out_port. */
int luat_pc_http_utest_server_wait_ready(luat_pc_http_utest_server_t *server,
                                         uint32_t timeout_ms,
                                         uint16_t *out_port);

/* Get the last error stage string. */
const char *luat_pc_http_utest_server_error(luat_pc_http_utest_server_t *server);

/* Request stop and join the server thread. Returns server result (0 = ok). */
int luat_pc_http_utest_server_stop(luat_pc_http_utest_server_t *server,
                                   uint32_t timeout_ms);

#endif
