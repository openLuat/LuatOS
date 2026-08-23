/* luat_pc_http_utest.c - Local HTTP/HTTPS helper server for utest.
 *
 * Provides a C-side pthread server on 127.0.0.1 with an ephemeral port,
 * used by luat_http_utest.c to run deterministic local HTTP/HTTPS tests
 * without external network dependency.
 *
 * Architecture mirrors luat_pc_dtls_utest.c (proven DTLS loopback helper).
 */
#include "luat_base.h"

#ifdef LUAT_USE_UTEST

#include "luat_malloc.h"
#include "luat_mcu.h"
#include "luat_crypto.h"
#include "luat_pc_http_utest.h"

#define LUAT_LOG_TAG "pc_http_utest"
#include "luat_log.h"

#include <pthread.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef int socklen_t;
#define HTTP_UTEST_CLOSE(s) closesocket(s)
#define HTTP_UTEST_POLL WSAPoll
#else
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <poll.h>
#define HTTP_UTEST_CLOSE(s) close(s)
#define HTTP_UTEST_POLL poll
#endif

#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/pk.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/error.h"

/* ─── Constants ─────────────────────────────────────────────────────────────── */
#define HTTP_UTEST_POLL_MS        50
#define HTTP_UTEST_MAX_REQ_SIZE   (256 * 1024)  /* max request body we'll read */
#define HTTP_UTEST_MAX_HEADERS    32
#define HTTP_UTEST_SLOW_DELAY_MS  3000

/* ─── Server struct ─────────────────────────────────────────────────────────── */
struct luat_pc_http_utest_server {
    volatile int ready;
    volatile int stop_requested;
    volatile int done;
    volatile int result;
    uint16_t port;
    char error_stage[32];
    pthread_t thread;
    int thread_started;
    /* TLS config (copied from cfg at start) */
    int use_tls;
    uint8_t *ca_pem;
    size_t ca_pem_len;
    uint8_t *srv_cert_pem;
    size_t srv_cert_pem_len;
    uint8_t *srv_key_pem;
    size_t srv_key_pem_len;
};

/* ─── Helpers ───────────────────────────────────────────────────────────────── */
static void http_utest_set_error(luat_pc_http_utest_server_t *srv, const char *stage) {
    size_t n = strlen(stage);
    if (n >= sizeof(srv->error_stage)) n = sizeof(srv->error_stage) - 1;
    memcpy(srv->error_stage, stage, n);
    srv->error_stage[n] = 0;
}

static uint64_t http_utest_now_ms(void) {
    return luat_mcu_tick64_ms();
}

static void http_utest_sleep_ms(uint32_t ms) {
    mbedtls_net_usleep((unsigned long)ms * 1000UL);
}

static int http_utest_entropy_source(void *data, unsigned char *output, size_t len, size_t *olen) {
    (void)data;
    if (luat_crypto_trng((char *)output, len) != 0) {
        return MBEDTLS_ERR_ENTROPY_SOURCE_FAILED;
    }
    *olen = len;
    return 0;
}

/* ─── Minimal HTTP request parsing ─────────────────────────────────────────── */
typedef struct {
    char method[16];
    char path[256];
    char body[HTTP_UTEST_MAX_REQ_SIZE];
    size_t body_len;
    char headers_raw[4096]; /* raw header block for /headers echo */
} http_utest_request_t;

/* Read from a TLS or plain connection. Returns bytes read, 0 on close, <0 error. */
typedef int (*http_utest_recv_fn)(void *ctx, unsigned char *buf, size_t len);
typedef int (*http_utest_send_fn)(void *ctx, const unsigned char *buf, size_t len);

typedef struct {
    http_utest_recv_fn recv;
    http_utest_send_fn send;
    void *ctx;
} http_utest_io_t;

static int io_recv_plain(void *ctx, unsigned char *buf, size_t len) {
    int fd = *(int *)ctx;
#ifdef _WIN32
    int r = recv(fd, (char *)buf, (int)len, 0);
#else
    int r = (int)recv(fd, buf, len, 0);
#endif
    return r;
}

static int io_send_plain(void *ctx, const unsigned char *buf, size_t len) {
    int fd = *(int *)ctx;
    size_t sent = 0;
    while (sent < len) {
#ifdef _WIN32
        int r = send(fd, (const char *)(buf + sent), (int)(len - sent), 0);
#else
        int r = (int)send(fd, buf + sent, len - sent, 0);
#endif
        if (r <= 0) return r;
        sent += (size_t)r;
    }
    return (int)sent;
}

static int io_recv_tls(void *ctx, unsigned char *buf, size_t len) {
    mbedtls_ssl_context *ssl = (mbedtls_ssl_context *)ctx;
    int ret = mbedtls_ssl_read(ssl, buf, len);
    if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE)
        return 0;
    if (ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY)
        return 0;
    return ret;
}

static int io_send_tls(void *ctx, const unsigned char *buf, size_t len) {
    mbedtls_ssl_context *ssl = (mbedtls_ssl_context *)ctx;
    size_t sent = 0;
    while (sent < len) {
        int ret = mbedtls_ssl_write(ssl, buf + sent, len - sent);
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE)
            continue;
        if (ret < 0)
            return ret;
        sent += (size_t)ret;
    }
    return (int)sent;
}

/* Read all available data until we have full headers + body.
 * Returns 0 on success, -1 on error/close. */
static int http_utest_read_request(http_utest_io_t *io, http_utest_request_t *req) {
    char buf[8192];
    size_t total = 0;
    char *header_end = NULL;
    int content_length = 0;
    size_t header_len = 0;

    memset(req, 0, sizeof(*req));

    /* Phase 1: read until we find \r\n\r\n */
    while (total < sizeof(buf) - 1) {
        int r = io->recv(io->ctx, (unsigned char *)(buf + total), sizeof(buf) - 1 - total);
        if (r <= 0) {
            if (total == 0) return -1;
            break;
        }
        total += (size_t)r;
        buf[total] = '\0';
        header_end = strstr(buf, "\r\n\r\n");
        if (header_end) break;
    }

    if (!header_end) return -1;

    header_len = (size_t)(header_end - buf) + 4;

    /* Parse request line: METHOD PATH HTTP/x.x */
    {
        char *line_end = strstr(buf, "\r\n");
        if (!line_end) return -1;
        *line_end = '\0';
        if (sscanf(buf, "%15s %255s", req->method, req->path) != 2) return -1;
        *line_end = '\r';
    }

    /* Store raw headers for echo */
    {
        size_t copy_len = header_len < sizeof(req->headers_raw) - 1 ? header_len : sizeof(req->headers_raw) - 1;
        memcpy(req->headers_raw, buf, copy_len);
        req->headers_raw[copy_len] = '\0';
    }

    /* Parse Content-Length */
    {
        const char *cl = strstr(buf, "Content-Length:");
        if (!cl) cl = strstr(buf, "content-length:");
        if (cl) {
            content_length = atoi(cl + 15);
            if (content_length < 0) content_length = 0;
            if (content_length > HTTP_UTEST_MAX_REQ_SIZE) content_length = HTTP_UTEST_MAX_REQ_SIZE;
        }
    }

    /* Phase 2: read remaining body if needed */
    {
        size_t body_have = total - header_len;
        size_t body_need = (size_t)content_length;
        size_t body_copy = body_have < body_need ? body_have : body_need;

        if (body_copy > 0) {
            memcpy(req->body, buf + header_len, body_copy);
        }
        req->body_len = body_copy;

        while (req->body_len < body_need && req->body_len < HTTP_UTEST_MAX_REQ_SIZE) {
            int r = io->recv(io->ctx, (unsigned char *)(req->body + req->body_len),
                            body_need - req->body_len);
            if (r <= 0) break;
            req->body_len += (size_t)r;
        }
    }

    return 0;
}

/* ─── Route handling ────────────────────────────────────────────────────────── */
static void http_utest_send_response(http_utest_io_t *io, int status, const char *status_text,
                                     const char *content_type, const char *extra_headers,
                                     const char *body, size_t body_len) {
    char header[1024];
    int hlen = snprintf(header, sizeof(header),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %d\r\n"
        "%s"
        "Connection: close\r\n"
        "\r\n",
        status, status_text, content_type, (int)body_len,
        extra_headers ? extra_headers : "");
    io->send(io->ctx, (const unsigned char *)header, (size_t)hlen);
    if (body && body_len > 0) {
        io->send(io->ctx, (const unsigned char *)body, body_len);
    }
}

static void http_utest_handle_request(luat_pc_http_utest_server_t *srv,
                                      http_utest_io_t *io,
                                      http_utest_request_t *req) {
    const char *path = req->path;

    /* Strip query string */
    char clean_path[256];
    {
        const char *q = strchr(path, '?');
        size_t plen = q ? (size_t)(q - path) : strlen(path);
        if (plen >= sizeof(clean_path)) plen = sizeof(clean_path) - 1;
        memcpy(clean_path, path, plen);
        clean_path[plen] = '\0';
        path = clean_path;
    }

    /* Route: /drop - close immediately without response */
    if (strcmp(path, "/drop") == 0) {
        return; /* caller closes socket */
    }

    /* Route: /malformed - send garbage */
    if (strcmp(path, "/malformed") == 0) {
        const char *garbage = "THIS IS NOT HTTP\r\n\r\n";
        io->send(io->ctx, (const unsigned char *)garbage, strlen(garbage));
        return;
    }

    /* Route: /slow - delay then respond */
    if (strcmp(path, "/slow") == 0) {
        http_utest_sleep_ms(HTTP_UTEST_SLOW_DELAY_MS);
        if (srv->stop_requested) return;
        http_utest_send_response(io, 200, "OK", "text/plain", NULL, "slow response", 13);
        return;
    }

    /* Route: /bytes/N - respond with N bytes */
    if (strncmp(path, "/bytes/", 7) == 0) {
        int n = atoi(path + 7);
        if (n <= 0) n = 64;
        if (n > 1024 * 1024) n = 1024 * 1024;
        {
            char *big = (char *)luat_heap_malloc((size_t)n);
            if (big) {
                memset(big, 'A', (size_t)n);
                http_utest_send_response(io, 200, "OK", "application/octet-stream", NULL, big, (size_t)n);
                luat_heap_free(big);
            } else {
                http_utest_send_response(io, 500, "Internal Server Error", "text/plain", NULL, "OOM", 3);
            }
        }
        return;
    }

    /* Route: /status/NNN */
    if (strncmp(path, "/status/", 8) == 0) {
        int code = atoi(path + 8);
        const char *text = "Unknown";
        if (code == 301) text = "Moved Permanently";
        else if (code == 404) text = "Not Found";
        else if (code == 500) text = "Internal Server Error";
        else if (code == 200) text = "OK";
        else if (code == 201) text = "Created";
        else if (code == 204) text = "No Content";
        {
            char extra[128] = "";
            if (code == 301) {
                snprintf(extra, sizeof(extra), "Location: http://127.0.0.1/\r\n");
            }
            char body[64];
            int blen = snprintf(body, sizeof(body), "status %d", code);
            http_utest_send_response(io, code, text, "text/plain",
                                     extra[0] ? extra : NULL, body, (size_t)blen);
        }
        return;
    }

    /* Route: /headers - echo request headers as body */
    if (strcmp(path, "/headers") == 0) {
        http_utest_send_response(io, 200, "OK", "text/plain", NULL,
                                 req->headers_raw, strlen(req->headers_raw));
        return;
    }

    /* Route: /post - echo body back */
    if (strcmp(path, "/post") == 0) {
        char resp_body[512];
        int rlen = snprintf(resp_body, sizeof(resp_body),
            "{\"method\":\"%s\",\"body_len\":%d,\"ok\":true}",
            req->method, (int)req->body_len);
        /* If there's a request body, append it */
        if (req->body_len > 0 && req->body_len < 256) {
            rlen = snprintf(resp_body, sizeof(resp_body),
                "{\"method\":\"%s\",\"body\":\"%.*s\",\"ok\":true}",
                req->method, (int)req->body_len, req->body);
        }
        http_utest_send_response(io, 200, "OK", "application/json", NULL, resp_body, (size_t)rlen);
        return;
    }

    /* Route: /get */
    if (strcmp(path, "/get") == 0) {
        const char *body = "{\"method\":\"GET\",\"ok\":true}";
        http_utest_send_response(io, 200, "OK", "application/json", NULL, body, strlen(body));
        return;
    }

    /* Route: / (root) */
    if (strcmp(path, "/") == 0) {
        http_utest_send_response(io, 200, "OK", "text/plain", NULL, "OK", 2);
        return;
    }

    /* Default: 404 */
    {
        char body[128];
        int blen = snprintf(body, sizeof(body), "Not Found: %s", path);
        http_utest_send_response(io, 404, "Not Found", "text/plain", NULL, body, (size_t)blen);
    }
}

/* ─── Server thread ─────────────────────────────────────────────────────────── */
static void *http_utest_server_thread(void *arg) {
    luat_pc_http_utest_server_t *srv = (luat_pc_http_utest_server_t *)arg;

    mbedtls_net_context listen_fd;
    mbedtls_net_init(&listen_fd);

    /* TLS resources */
    mbedtls_ssl_config conf;
    mbedtls_ssl_context ssl;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_entropy_context entropy;
    mbedtls_x509_crt ca_chain, srv_crt;
    mbedtls_pk_context srv_key;
    int tls_inited = 0, certs_inited = 0;
    int ret;

    mbedtls_ssl_config_init(&conf);
    mbedtls_ssl_init(&ssl);
    mbedtls_ctr_drbg_init(&ctr_drbg);
    mbedtls_entropy_init(&entropy);

    /* Seed RNG */
    mbedtls_entropy_add_source(&entropy, http_utest_entropy_source, NULL, 32,
                               MBEDTLS_ENTROPY_SOURCE_STRONG);
    ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy,
                                (const unsigned char *)"http_utest", 10);
    if (ret != 0) {
        http_utest_set_error(srv, "rng_seed_failed");
        goto cleanup;
    }

    /* Bind to 127.0.0.1:0 (ephemeral port) using TCP */
    ret = mbedtls_net_bind(&listen_fd, "127.0.0.1", "0", MBEDTLS_NET_PROTO_TCP);
    if (ret != 0) {
        http_utest_set_error(srv, "bind_failed");
        goto cleanup;
    }

    /* Get the actual port */
    {
        struct sockaddr_in addr;
#ifdef _WIN32
        int addr_len = (int)sizeof(addr);
#else
        socklen_t addr_len = (socklen_t)sizeof(addr);
#endif
        memset(&addr, 0, sizeof(addr));
        if (getsockname(listen_fd.fd, (struct sockaddr *)&addr, &addr_len) != 0) {
            http_utest_set_error(srv, "getsockname_failed");
            goto cleanup;
        }
        srv->port = ntohs(addr.sin_port);
        if (srv->port == 0) {
            http_utest_set_error(srv, "port_zero");
            goto cleanup;
        }
    }

    /* Setup TLS if needed */
    if (srv->use_tls) {
        ret = mbedtls_ssl_config_defaults(&conf,
                                          MBEDTLS_SSL_IS_SERVER,
                                          MBEDTLS_SSL_TRANSPORT_STREAM,
                                          MBEDTLS_SSL_PRESET_DEFAULT);
        if (ret != 0) {
            http_utest_set_error(srv, "ssl_config_defaults");
            goto cleanup;
        }
        mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &ctr_drbg);
        mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);
        tls_inited = 1;

        /* Load certificates */
        mbedtls_x509_crt_init(&ca_chain);
        mbedtls_x509_crt_init(&srv_crt);
        mbedtls_pk_init(&srv_key);
        certs_inited = 1;

        ret = mbedtls_x509_crt_parse(&ca_chain, srv->ca_pem, srv->ca_pem_len);
        if (ret != 0) {
            http_utest_set_error(srv, "parse_ca_failed");
            goto cleanup;
        }
        ret = mbedtls_x509_crt_parse(&srv_crt, srv->srv_cert_pem, srv->srv_cert_pem_len);
        if (ret != 0) {
            http_utest_set_error(srv, "parse_srv_cert_failed");
            goto cleanup;
        }
        ret = mbedtls_pk_parse_key(&srv_key, srv->srv_key_pem, srv->srv_key_pem_len,
                                   NULL, 0
#if MBEDTLS_VERSION_NUMBER >= 0x03000000 && MBEDTLS_VERSION_NUMBER < 0x04000000
                                   , mbedtls_ctr_drbg_random, &ctr_drbg
#endif
                                   );
        if (ret != 0) {
            http_utest_set_error(srv, "parse_srv_key_failed");
            goto cleanup;
        }
        mbedtls_ssl_conf_ca_chain(&conf, &ca_chain, NULL);
        mbedtls_ssl_conf_own_cert(&conf, &srv_crt, &srv_key);
    }

    /* Mark ready */
    srv->ready = 1;

    /* ─── Main accept loop ─── */
    while (!srv->stop_requested) {
        struct pollfd pfd;
        int poll_ret;

        pfd.fd = listen_fd.fd;
        pfd.events = POLLIN;
        pfd.revents = 0;

        poll_ret = HTTP_UTEST_POLL(&pfd, 1, HTTP_UTEST_POLL_MS);
        if (poll_ret < 0) {
            break;
        }
        if (poll_ret == 0) {
            continue; /* timeout, check stop flag */
        }
        if (!(pfd.revents & POLLIN)) {
            continue;
        }

        /* Accept a connection */
        if (srv->use_tls) {
            /* TLS path */
            mbedtls_net_context client_fd;
            mbedtls_net_init(&client_fd);

            ret = mbedtls_net_accept(&listen_fd, &client_fd, NULL, 0, NULL);
            if (ret != 0) {
                mbedtls_net_free(&client_fd);
                continue;
            }

            mbedtls_ssl_setup(&ssl, &conf);
            mbedtls_ssl_set_bio(&ssl, &client_fd, mbedtls_net_send, mbedtls_net_recv, NULL);

            /* Handshake with timeout */
            {
                uint64_t hs_deadline = http_utest_now_ms() + 10000;
                int hs_done = 0;
                while (http_utest_now_ms() < hs_deadline && !srv->stop_requested) {
                    ret = mbedtls_ssl_handshake(&ssl);
                    if (ret == 0) { hs_done = 1; break; }
                    if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
                        break;
                    }
                    http_utest_sleep_ms(5);
                }
                if (!hs_done) {
                    mbedtls_ssl_close_notify(&ssl);
                    mbedtls_ssl_free(&ssl);
                    mbedtls_ssl_init(&ssl);
                    mbedtls_net_free(&client_fd);
                    continue;
                }
            }

            /* Handle request over TLS */
            {
                http_utest_io_t io;
                http_utest_request_t req;
                io.recv = io_recv_tls;
                io.send = io_send_tls;
                io.ctx = &ssl;

                if (http_utest_read_request(&io, &req) == 0) {
                    http_utest_handle_request(srv, &io, &req);
                }
            }

            mbedtls_ssl_close_notify(&ssl);
            mbedtls_ssl_free(&ssl);
            mbedtls_ssl_init(&ssl);
            mbedtls_net_free(&client_fd);
        } else {
            /* Plain TCP path */
            mbedtls_net_context client_fd;
            mbedtls_net_init(&client_fd);

            ret = mbedtls_net_accept(&listen_fd, &client_fd, NULL, 0, NULL);
            if (ret != 0) {
                mbedtls_net_free(&client_fd);
                continue;
            }

            {
                http_utest_io_t io;
                http_utest_request_t req;
                int client_socket = client_fd.fd;
                io.recv = io_recv_plain;
                io.send = io_send_plain;
                io.ctx = &client_socket;

                if (http_utest_read_request(&io, &req) == 0) {
                    http_utest_handle_request(srv, &io, &req);
                }
            }

            mbedtls_net_free(&client_fd);
        }
    }

    srv->result = 0;

cleanup:
    mbedtls_net_free(&listen_fd);
    if (tls_inited) {
        mbedtls_ssl_config_free(&conf);
    }
    if (certs_inited) {
        mbedtls_x509_crt_free(&ca_chain);
        mbedtls_x509_crt_free(&srv_crt);
        mbedtls_pk_free(&srv_key);
    }
    mbedtls_ssl_free(&ssl);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    srv->done = 1;
    return NULL;
}

/* ─── Public API ────────────────────────────────────────────────────────────── */
int luat_pc_http_utest_server_start(luat_pc_http_utest_server_t **out_server,
                                    const luat_pc_http_utest_cfg_t *cfg) {
    luat_pc_http_utest_server_t *srv;

    if (!out_server || !cfg) return -1;

    srv = (luat_pc_http_utest_server_t *)luat_heap_malloc(sizeof(luat_pc_http_utest_server_t));
    if (!srv) return -1;
    memset(srv, 0, sizeof(*srv));
    srv->result = -1;
    srv->use_tls = cfg->use_tls;

    if (cfg->use_tls) {
        if (!cfg->ca_pem || !cfg->srv_cert_pem || !cfg->srv_key_pem ||
            cfg->ca_pem_len == 0 || cfg->srv_cert_pem_len == 0 || cfg->srv_key_pem_len == 0) {
            luat_heap_free(srv);
            return -1;
        }
        srv->ca_pem = (uint8_t *)luat_heap_malloc(cfg->ca_pem_len);
        srv->srv_cert_pem = (uint8_t *)luat_heap_malloc(cfg->srv_cert_pem_len);
        srv->srv_key_pem = (uint8_t *)luat_heap_malloc(cfg->srv_key_pem_len);
        if (!srv->ca_pem || !srv->srv_cert_pem || !srv->srv_key_pem) {
            if (srv->ca_pem) luat_heap_free(srv->ca_pem);
            if (srv->srv_cert_pem) luat_heap_free(srv->srv_cert_pem);
            if (srv->srv_key_pem) luat_heap_free(srv->srv_key_pem);
            luat_heap_free(srv);
            return -1;
        }
        memcpy(srv->ca_pem, cfg->ca_pem, cfg->ca_pem_len);
        srv->ca_pem_len = cfg->ca_pem_len;
        memcpy(srv->srv_cert_pem, cfg->srv_cert_pem, cfg->srv_cert_pem_len);
        srv->srv_cert_pem_len = cfg->srv_cert_pem_len;
        memcpy(srv->srv_key_pem, cfg->srv_key_pem, cfg->srv_key_pem_len);
        srv->srv_key_pem_len = cfg->srv_key_pem_len;
    }

    http_utest_set_error(srv, "helper_start_failed");

    if (pthread_create(&srv->thread, NULL, http_utest_server_thread, srv) != 0) {
        if (srv->ca_pem) luat_heap_free(srv->ca_pem);
        if (srv->srv_cert_pem) luat_heap_free(srv->srv_cert_pem);
        if (srv->srv_key_pem) luat_heap_free(srv->srv_key_pem);
        luat_heap_free(srv);
        return -1;
    }
    srv->thread_started = 1;
    *out_server = srv;
    return 0;
}

int luat_pc_http_utest_server_wait_ready(luat_pc_http_utest_server_t *server,
                                         uint32_t timeout_ms,
                                         uint16_t *out_port) {
    uint64_t deadline;
    if (!server) return -1;

    deadline = http_utest_now_ms() + timeout_ms;
    while (http_utest_now_ms() < deadline) {
        if (server->ready) {
            if (out_port) *out_port = server->port;
            return 0;
        }
        if (server->done) return -1;
        http_utest_sleep_ms(10);
    }
    return -1;
}

const char *luat_pc_http_utest_server_error(luat_pc_http_utest_server_t *server) {
    if (!server || !server->error_stage[0]) return "helper_start_failed";
    return server->error_stage;
}

int luat_pc_http_utest_server_stop(luat_pc_http_utest_server_t *server,
                                   uint32_t timeout_ms) {
    int result = -1;
    uint64_t deadline;
    if (!server) return -1;

    server->stop_requested = 1;
    if (server->thread_started) {
        deadline = http_utest_now_ms() + timeout_ms;
        while (!server->done && http_utest_now_ms() < deadline) {
            http_utest_sleep_ms(10);
        }
        if (!server->done) return -1;
        pthread_join(server->thread, NULL);
    }
    result = server->result;
    if (server->ca_pem) { luat_heap_free(server->ca_pem); server->ca_pem = NULL; }
    if (server->srv_cert_pem) { luat_heap_free(server->srv_cert_pem); server->srv_cert_pem = NULL; }
    if (server->srv_key_pem) { luat_heap_free(server->srv_key_pem); server->srv_key_pem = NULL; }
    luat_heap_free(server);
    return result;
}

#endif /* LUAT_USE_UTEST */
