#ifndef LUAT_PC_DTLS_UTEST_H
#define LUAT_PC_DTLS_UTEST_H

#include <stddef.h>
#include <stdint.h>

typedef struct luat_pc_dtls_utest_server luat_pc_dtls_utest_server_t;

int luat_pc_dtls_utest_server_start(luat_pc_dtls_utest_server_t **out_server,
                                    const char *psk_id,
                                    const uint8_t *psk,
                                    size_t psk_len);
int luat_pc_dtls_utest_server_wait_ready(luat_pc_dtls_utest_server_t *server,
                                         uint32_t timeout_ms,
                                         uint16_t *out_port);
const char *luat_pc_dtls_utest_server_error(luat_pc_dtls_utest_server_t *server);
int luat_pc_dtls_utest_server_stop(luat_pc_dtls_utest_server_t *server,
                                   uint32_t timeout_ms);

#endif
