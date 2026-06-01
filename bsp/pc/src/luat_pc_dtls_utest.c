#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_mcu.h"
#include "luat_crypto.h"
#include "luat_pc_dtls_utest.h"


#include <pthread.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#endif

#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/ssl.h"

typedef struct dtls_utest_timer {
    uint64_t start_ms;
    uint32_t int_ms;
    uint32_t fin_ms;
} dtls_utest_timer_t;

static void dtls_utest_timer_set(void *data, uint32_t int_ms, uint32_t fin_ms)
{
    dtls_utest_timer_t *timer = (dtls_utest_timer_t *)data;
    timer->start_ms = luat_mcu_tick64_ms();
    timer->int_ms = int_ms;
    timer->fin_ms = fin_ms;
}

static int dtls_utest_timer_get(void *data)
{
    dtls_utest_timer_t *timer = (dtls_utest_timer_t *)data;
    uint64_t elapsed;
    if (timer->fin_ms == 0) {
        return -1;
    }
    elapsed = luat_mcu_tick64_ms() - timer->start_ms;
    if (elapsed >= timer->fin_ms) {
        return 2;
    }
    if (elapsed >= timer->int_ms) {
        return 1;
    }
    return 0;
}

#define DTLS_UTEST_MAX_PSK_LEN        64
#define DTLS_UTEST_MAX_PSK_ID_LEN     64
#define DTLS_UTEST_ACCEPT_TIMEOUT_MS  10000
#define DTLS_UTEST_HANDSHAKE_MS       10000
#define DTLS_UTEST_IO_TIMEOUT_MS      5000
#define DTLS_UTEST_POLL_MS            50

struct luat_pc_dtls_utest_server {
    volatile int ready;
    volatile int stop_requested;
    volatile int done;
    volatile int result;
    uint16_t port;
    char error_stage[32];
    pthread_t thread;
    int thread_started;
    char psk_id[DTLS_UTEST_MAX_PSK_ID_LEN];
    uint8_t psk[DTLS_UTEST_MAX_PSK_LEN];
    size_t psk_len;
};

static void dtls_utest_set_error(luat_pc_dtls_utest_server_t *server, const char *stage) {
    size_t n = strlen(stage);
    if (n >= sizeof(server->error_stage)) {
        n = sizeof(server->error_stage) - 1;
    }
    memcpy(server->error_stage, stage, n);
    server->error_stage[n] = 0;
}

static void dtls_utest_clear_error(luat_pc_dtls_utest_server_t *server) {
    server->error_stage[0] = 0;
}

static uint64_t dtls_utest_now_ms(void) {
    return luat_mcu_tick64_ms();
}

static void dtls_utest_sleep_ms(uint32_t sleep_ms) {
    mbedtls_net_usleep((unsigned long)sleep_ms * 1000UL);
}

static int dtls_utest_entropy_source(void *data, unsigned char *output, size_t len, size_t *olen) {
    (void)data;
    if (luat_crypto_trng((char *)output, len) != 0) {
        return MBEDTLS_ERR_ENTROPY_SOURCE_FAILED;
    }
    *olen = len;
    return 0;
}

static int dtls_utest_port_from_socket(mbedtls_net_context *listen_fd, uint16_t *out_port) {
    struct sockaddr_in addr;
#ifdef _WIN32
    int addr_len = (int)sizeof(addr);
#else
    socklen_t addr_len = (socklen_t)sizeof(addr);
#endif
    memset(&addr, 0, sizeof(addr));
    if (getsockname(listen_fd->fd, (struct sockaddr *)&addr, &addr_len) != 0) {
        return -1;
    }
    *out_port = ntohs(addr.sin_port);
    return *out_port ? 0 : -1;
}

static int dtls_utest_wait_accept(luat_pc_dtls_utest_server_t *server,
                                  mbedtls_net_context *listen_fd,
                                  mbedtls_net_context *client_fd,
                                  unsigned char *client_ip,
                                  size_t client_ip_size,
                                  size_t *client_ip_len) {
    uint64_t deadline = dtls_utest_now_ms() + DTLS_UTEST_ACCEPT_TIMEOUT_MS;
    int ret;

    while (!server->stop_requested) {
        ret = mbedtls_net_poll(listen_fd, MBEDTLS_NET_POLL_READ, DTLS_UTEST_POLL_MS);
        if (ret == 0) {
            if (dtls_utest_now_ms() >= deadline) {
                return MBEDTLS_ERR_SSL_TIMEOUT;
            }
            continue;
        }
        if (ret < 0) {
            return ret;
        }
        ret = mbedtls_net_accept(listen_fd, client_fd, client_ip, client_ip_size, client_ip_len);
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            if (dtls_utest_now_ms() >= deadline) {
                return MBEDTLS_ERR_SSL_TIMEOUT;
            }
            continue;
        }
        return ret;
    }

    return -1;
}

static int dtls_utest_do_handshake(luat_pc_dtls_utest_server_t *server, mbedtls_ssl_context *ssl) {
    uint64_t deadline = dtls_utest_now_ms() + DTLS_UTEST_HANDSHAKE_MS;
    int ret;

    while (!server->stop_requested) {
        ret = mbedtls_ssl_handshake(ssl);
        if (ret == 0 || ret == MBEDTLS_ERR_SSL_HELLO_VERIFY_REQUIRED) {
            return ret;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE || ret == MBEDTLS_ERR_SSL_TIMEOUT) {
            if (dtls_utest_now_ms() >= deadline) {
                return MBEDTLS_ERR_SSL_TIMEOUT;
            }
            continue;
        }
        return ret;
    }

    return -1;
}

static int dtls_utest_read_once(luat_pc_dtls_utest_server_t *server,
                                mbedtls_ssl_context *ssl,
                                unsigned char *buf,
                                size_t buf_len,
                                size_t *out_len) {
    uint64_t deadline = dtls_utest_now_ms() + DTLS_UTEST_IO_TIMEOUT_MS;
    int ret;

    while (!server->stop_requested) {
        ret = mbedtls_ssl_read(ssl, buf, buf_len);
        if (ret > 0) {
            *out_len = (size_t)ret;
            return 0;
        }
        if (ret == 0) {
            return -1;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE || ret == MBEDTLS_ERR_SSL_TIMEOUT) {
            if (dtls_utest_now_ms() >= deadline) {
                return MBEDTLS_ERR_SSL_TIMEOUT;
            }
            continue;
        }
        return ret;
    }

    return -1;
}

static int dtls_utest_write_exact(luat_pc_dtls_utest_server_t *server,
                                  mbedtls_ssl_context *ssl,
                                  const unsigned char *buf,
                                  size_t len) {
    uint64_t deadline = dtls_utest_now_ms() + DTLS_UTEST_IO_TIMEOUT_MS;
    size_t offset = 0;
    int ret;

    while (!server->stop_requested && offset < len) {
        ret = mbedtls_ssl_write(ssl, buf + offset, len - offset);
        if (ret > 0) {
            offset += (size_t)ret;
            continue;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE || ret == MBEDTLS_ERR_SSL_TIMEOUT) {
            if (dtls_utest_now_ms() >= deadline) {
                return MBEDTLS_ERR_SSL_TIMEOUT;
            }
            continue;
        }
        return ret ? ret : -1;
    }

    return offset == len ? 0 : -1;
}

static void *dtls_utest_server_thread(void *arg) {
    static const char *pers = "luat_pc_dtls_utest";
    luat_pc_dtls_utest_server_t *server = (luat_pc_dtls_utest_server_t *)arg;
    mbedtls_net_context listen_fd;
    mbedtls_net_context client_fd;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_entropy_context entropy;
    dtls_utest_timer_t timer;
    unsigned char client_ip[32];
    unsigned char io_buf[256];
    size_t client_ip_len = 0;
    size_t io_len = 0;
    int ret;

    server->result = -1;
    dtls_utest_set_error(server, "helper_start_failed");

    mbedtls_net_init(&listen_fd);
    mbedtls_net_init(&client_fd);
    mbedtls_ssl_init(&ssl);
    mbedtls_ssl_config_init(&conf);
    mbedtls_ctr_drbg_init(&ctr_drbg);
    mbedtls_entropy_init(&entropy);
    memset(&timer, 0, sizeof(timer));

    ret = mbedtls_entropy_add_source(&entropy, dtls_utest_entropy_source, NULL, 32,
                                     MBEDTLS_ENTROPY_SOURCE_STRONG);
    if (ret != 0) {
        goto cleanup;
    }

    ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy,
                                (const unsigned char *)pers, strlen(pers));
    if (ret != 0) {
        goto cleanup;
    }

    ret = mbedtls_ssl_config_defaults(&conf,
                                      MBEDTLS_SSL_IS_SERVER,
                                      MBEDTLS_SSL_TRANSPORT_DATAGRAM,
                                      MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        goto cleanup;
    }

    mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &ctr_drbg);
    mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);
    mbedtls_ssl_conf_dtls_cookies(&conf, NULL, NULL, NULL);
    mbedtls_ssl_conf_read_timeout(&conf, DTLS_UTEST_POLL_MS);

    ret = mbedtls_ssl_conf_psk(&conf,
                               server->psk,
                               server->psk_len,
                               (const unsigned char *)server->psk_id,
                               strlen(server->psk_id));
    if (ret != 0) {
        goto cleanup;
    }

    ret = mbedtls_ssl_setup(&ssl, &conf);
    if (ret != 0) {
        goto cleanup;
    }
    mbedtls_ssl_set_datagram_packing(&ssl, 0);
    mbedtls_ssl_set_timer_cb(&ssl, &timer, dtls_utest_timer_set, dtls_utest_timer_get);

    ret = mbedtls_net_bind(&listen_fd, "127.0.0.1", "0", MBEDTLS_NET_PROTO_UDP);
    if (ret != 0) {
        goto cleanup;
    }

    ret = dtls_utest_port_from_socket(&listen_fd, &server->port);
    if (ret != 0) {
        goto cleanup;
    }

    server->ready = 1;

    while (!server->stop_requested) {
        memset(client_ip, 0, sizeof(client_ip));
        client_ip_len = 0;
        mbedtls_net_free(&client_fd);
        mbedtls_net_init(&client_fd);

        ret = dtls_utest_wait_accept(server,
                                     &listen_fd,
                                     &client_fd,
                                     client_ip,
                                     sizeof(client_ip),
                                     &client_ip_len);
        if (ret != 0) {
            if (ret == -1 && server->stop_requested) {
                goto cleanup;
            }
            dtls_utest_set_error(server, "dtls_connect_timeout");
            goto cleanup;
        }

        ret = mbedtls_net_set_block(&client_fd);
        if (ret != 0) {
            dtls_utest_set_error(server, "dtls_connect_timeout");
            goto cleanup;
        }

        mbedtls_ssl_session_reset(&ssl);
        mbedtls_ssl_set_bio(&ssl,
                            &client_fd,
                            mbedtls_net_send,
                            mbedtls_net_recv,
                            mbedtls_net_recv_timeout);
        ret = dtls_utest_do_handshake(server, &ssl);
        if (ret == MBEDTLS_ERR_SSL_HELLO_VERIFY_REQUIRED) {
            continue;
        }
        if (ret != 0) {
            dtls_utest_set_error(server, "dtls_connect_timeout");
            goto cleanup;
        }
        break;
    }

    ret = dtls_utest_read_once(server, &ssl, io_buf, sizeof(io_buf), &io_len);
    if (ret != 0) {
        dtls_utest_set_error(server, "dtls_echo_mismatch");
        goto cleanup;
    }

    ret = dtls_utest_write_exact(server, &ssl, io_buf, io_len);
    if (ret != 0) {
        dtls_utest_set_error(server, "dtls_tx_timeout");
        goto cleanup;
    }

    dtls_utest_clear_error(server);
    server->result = 0;

cleanup:
    mbedtls_ssl_close_notify(&ssl);
    mbedtls_net_free(&client_fd);
    mbedtls_net_free(&listen_fd);
    mbedtls_ssl_free(&ssl);
    mbedtls_ssl_config_free(&conf);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    server->done = 1;
    return NULL;
}

int luat_pc_dtls_utest_server_start(luat_pc_dtls_utest_server_t **out_server,
                                    const char *psk_id,
                                    const uint8_t *psk,
                                    size_t psk_len) {
    luat_pc_dtls_utest_server_t *server;

    if (!out_server || !psk_id || !psk || !psk_len ||
        psk_len >= DTLS_UTEST_MAX_PSK_LEN || strlen(psk_id) >= DTLS_UTEST_MAX_PSK_ID_LEN) {
        return -1;
    }

    server = luat_heap_malloc(sizeof(luat_pc_dtls_utest_server_t));
    if (!server) {
        return -1;
    }
    memset(server, 0, sizeof(luat_pc_dtls_utest_server_t));
    server->result = -1;
    memcpy(server->psk, psk, psk_len);
    server->psk_len = psk_len;
    memcpy(server->psk_id, psk_id, strlen(psk_id) + 1);
    dtls_utest_set_error(server, "helper_start_failed");

    if (pthread_create(&server->thread, NULL, dtls_utest_server_thread, server) != 0) {
        luat_heap_free(server);
        return -1;
    }
    server->thread_started = 1;
    *out_server = server;
    return 0;
}

int luat_pc_dtls_utest_server_wait_ready(luat_pc_dtls_utest_server_t *server,
                                         uint32_t timeout_ms,
                                         uint16_t *out_port) {
    uint64_t deadline;

    if (!server) {
        return -1;
    }

    deadline = dtls_utest_now_ms() + timeout_ms;
    while (dtls_utest_now_ms() < deadline) {
        if (server->ready) {
            if (out_port) {
                *out_port = server->port;
            }
            return 0;
        }
        if (server->done) {
            return -1;
        }
        dtls_utest_sleep_ms(10);
    }
    return -1;
}

const char *luat_pc_dtls_utest_server_error(luat_pc_dtls_utest_server_t *server) {
    if (!server || !server->error_stage[0]) {
        return "helper_start_failed";
    }
    return server->error_stage;
}

int luat_pc_dtls_utest_server_stop(luat_pc_dtls_utest_server_t *server,
                                   uint32_t timeout_ms) {
    int result = -1;
    uint64_t deadline;

    if (!server) {
        return -1;
    }

    server->stop_requested = 1;
    if (server->thread_started) {
        deadline = dtls_utest_now_ms() + timeout_ms;
        while (!server->done && dtls_utest_now_ms() < deadline) {
            dtls_utest_sleep_ms(10);
        }
        if (!server->done) {
            return -1;
        }
        pthread_join(server->thread, NULL);
    }
    result = server->result;
    luat_heap_free(server);
    return result;
}
