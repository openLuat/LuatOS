/**
 * @file luat_network_adapter_posix.c
 * @brief POSIX socket-based network adapter for bsp/pc (replaces libuv adapter).
 *
 * Architecture:
 *  - Each connected TCP socket runs a dedicated I/O pthread (PTHREAD_CREATE_DETACHED).
 *  - TCP server sockets run an accept pthread that stays alive as long as the socket is open.
 *  - UDP sockets run a single recv pthread.
 *  - DNS queries run in a temporary detached pthread (getaddrinfo).
 *  - All events are dispatched to the Lua thread via luat_msgbus_put().
 *  - malloc/free are used exclusively for buffers allocated in I/O threads, matching
 *    the framework's expectation (luat_network_adapter.c frees dns_ip with free()).
 */

/* luat_posix_compat.h must come first: sets up winsock2/pthreads include order. */
#include "luat_posix_compat.h"

#include "luat_base.h"
#include "luat_log.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_network_adapter.h"
#include "luat_timer_engine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LUAT_LOG_TAG "posix_net"
#include "luat_log.h"

/* ─── Platform socket abstractions ─────────────────────────────────────────── */
#if defined(_WIN32) || defined(_WIN64)
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #include <iphlpapi.h>
  typedef SOCKET       sock_fd_t;
  typedef WSAPOLLFD    poll_fd_t;
  #define INVALID_SOCK_FD    INVALID_SOCKET
  #define sock_close(fd)     closesocket(fd)
  #define sock_poll          WSAPoll
  #define sock_errno         WSAGetLastError()
  #define SOCK_EWOULDBLOCK   WSAEWOULDBLOCK
  #define SOCK_EINPROGRESS   WSAEWOULDBLOCK
  static inline void sock_nonblock(sock_fd_t fd) {
      u_long mode = 1; ioctlsocket(fd, FIONBIO, &mode);
  }
  static inline void sock_shutdown_rw(sock_fd_t fd) { shutdown(fd, SD_BOTH); }
  static inline int get_sock_error(sock_fd_t fd) {
      int err = 0; int len = sizeof(err);
      getsockopt(fd, SOL_SOCKET, SO_ERROR, (char*)&err, &len); return err;
  }
#else
  #include <sys/socket.h>
  #include <netinet/in.h>
  #include <netinet/tcp.h>
  #include <arpa/inet.h>
  #include <poll.h>
  #include <fcntl.h>
  #include <unistd.h>
  #include <netdb.h>
  #include <ifaddrs.h>
  typedef int          sock_fd_t;
  typedef struct pollfd poll_fd_t;
  #define INVALID_SOCK_FD   ((sock_fd_t)(-1))
  #define sock_close(fd)    close(fd)
  #define sock_poll         poll
  #define sock_errno        errno
  #define SOCK_EWOULDBLOCK  EWOULDBLOCK
  #define SOCK_EINPROGRESS  EINPROGRESS
  static inline void sock_nonblock(sock_fd_t fd) {
      fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
  }
  static inline void sock_shutdown_rw(sock_fd_t fd) { shutdown(fd, SHUT_RDWR); }
  static inline int get_sock_error(sock_fd_t fd) {
      int err = 0; socklen_t len = sizeof(err);
      getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len); return err;
  }
#endif

/* ─── Constants ─────────────────────────────────────────────────────────────── */
#define MAX_SOCK_NUM   32
#define POLL_TIMEOUT_MS  100   /* I/O thread poll granularity */
#define TCP_RECV_BUF  4096

#ifndef LUAT_CONF_NETWORK_DEBUG
#define LUAT_CONF_NETWORK_DEBUG 0
#endif
#if (LUAT_CONF_NETWORK_DEBUG == 0)
#undef LLOGD
#define LLOGD(...)
#endif

enum {
    SC_IDLE = 0,
    SC_USED,
    SC_CONNECTING,
    SC_CONNECTED,
    SC_CLOSING,
    SC_CLOSED,
    SC_LISTENING
};

static const char *const state_strs[] = {
    "空闲","已占用","连接中","已连接","关闭中","已关闭","监听中"
};
static const char *socket_state_str(int s) {
    return (s >= 0 && s <= SC_LISTENING) ? state_strs[s] : "?";
}

/* ─── Per-socket structures ─────────────────────────────────────────────────── */
typedef struct posix_udp_data {
    struct sockaddr_in from;
    void              *next;
    size_t             len;
    char               data[4];   /* variable-length tail */
} posix_udp_data_t;

typedef struct posix_conn {
    int             state;
    uint64_t        tag;
    void           *param;
    int             is_tcp;
    int             is_ipv6;

    sock_fd_t       fd;            /* client/data fd */
    sock_fd_t       server_fd;     /* TCP listen fd (server only) */
    struct sockaddr_in remote_addr; /* UDP "connected" peer */

    char           *recv_buff;     /* TCP rx buffer (malloc) */
    size_t          recv_size;
    pthread_mutex_t recv_lock;

    posix_udp_data_t *udp_data;   /* UDP rx queue head (malloc) */
    pthread_mutex_t  udp_lock;

    volatile int    io_stop;       /* 1 = request I/O thread to exit */
    int             io_running;    /* 1 = I/O thread is alive */
} posix_conn_t;

/* Event wrapper passed via luat_msgbus */
typedef struct {
    OS_EVENT              event;
    luat_network_cb_param_t param;
} posix_nw_event_t;

/* ─── Global state ───────────────────────────────────────────────────────────── */
typedef struct { CBFuncEx_t socket_cb; void *user_data; uint8_t next_idx; } posix_ctrl_t;
static posix_ctrl_t  ctrl;
static posix_conn_t  sockets[MAX_SOCK_NUM];
static uint64_t      socket_tag_counter = 0xFAFB;
static pthread_mutex_t g_socket_mutex  = PTHREAD_MUTEX_INITIALIZER;
/* Broadcast when any slot's io_running transitions 1→0 (slot becomes reusable) */
static pthread_cond_t  g_slot_free_cond = PTHREAD_COND_INITIALIZER;

/* ─── CHECK_SOCKET_ID macro ──────────────────────────────────────────────────── */
#define CHECK_SOCKET_ID \
    if (socket_id < 0 || socket_id >= MAX_SOCK_NUM) { LLOGE("socket id不合法 %d", socket_id); return -1; } \
    if (sockets[socket_id].tag == 0 || sockets[socket_id].state == SC_CLOSED) { \
        LLOGD("socket[%d] 已经是关闭状态", socket_id); return -1; } \
    if (sockets[socket_id].tag != tag) { \
        LLOGE("socket[%d] tag 不匹配 期望 %016llX 实际 %016llX", socket_id, (unsigned long long)tag, (unsigned long long)sockets[socket_id].tag); \
        return -1; }

/* ─── Event dispatch (thread-safe) ──────────────────────────────────────────── */
static int32_t posix_nw_event_handler(lua_State *L, void *ptr);

static void cb_to_nw_task(uint32_t event_id, size_t param1, size_t param2, size_t param3)
{
    posix_nw_event_t *e = malloc(sizeof(posix_nw_event_t));
    if (!e) { LLOGE("OOM in cb_to_nw_task"); return; }
    memset(e, 0, sizeof(posix_nw_event_t));
    e->event.ID = event_id;
    e->event.Param1 = param1;
    e->event.Param2 = param2;
    e->event.Param3 = param3;

    pthread_mutex_lock(&g_socket_mutex);
    if (event_id > EV_NW_DNS_RESULT) {
        int sid = (int)(uint32_t)param1;
        if (sid >= 0 && sid < MAX_SOCK_NUM) {
            e->event.Param3 = (size_t)sockets[sid].param;
            e->param.tag    = sockets[sid].tag;
        }
    }
    e->param.param = ctrl.user_data;
    pthread_mutex_unlock(&g_socket_mutex);

    rtos_msg_t msg = { .handler = posix_nw_event_handler, .ptr = e };
    luat_msgbus_put(&msg, 0);
}

static int32_t posix_nw_event_handler(lua_State *L, void *ptr)
{
    (void)L;
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    posix_nw_event_t *e = (posix_nw_event_t *)msg->ptr;
    if (e) {
        ctrl.socket_cb(&e->event, &e->param);
        free(e);
    }
    return 0;
}

/* ─── Host IPv4 helper ───────────────────────────────────────────────────────── */
static uint32_t posix_get_host_ipv4_u32(void)
{
#if defined(_WIN32) || defined(_WIN64)
    IP_ADAPTER_INFO buf[16];
    DWORD bufLen = sizeof(buf);
    if (GetAdaptersInfo(buf, &bufLen) == ERROR_SUCCESS) {
        IP_ADAPTER_INFO *a = buf;
        while (a) {
            /* skip loopback */
            if (strcmp(a->IpAddressList.IpAddress.String, "127.0.0.1") != 0
                && strcmp(a->IpAddressList.IpAddress.String, "0.0.0.0") != 0) {
                struct in_addr ia;
                inet_pton(AF_INET, a->IpAddressList.IpAddress.String, &ia);
                return ia.s_addr;
            }
            a = a->Next;
        }
    }
#else
    struct ifaddrs *ifap = NULL, *ifa;
    getifaddrs(&ifap);
    for (ifa = ifap; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
        if (sa->sin_addr.s_addr == htonl(INADDR_LOOPBACK)) continue;
        uint32_t r = sa->sin_addr.s_addr;
        freeifaddrs(ifap);
        return r;
    }
    if (ifap) freeifaddrs(ifap);
#endif
    return 0;
}

/* ─── Helpers to start a detached thread ────────────────────────────────────── */
static void start_detached_thread(void *(*fn)(void*), void *arg)
{
    pthread_t tid;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&tid, &attr, fn, arg);
    pthread_attr_destroy(&attr);
}

/* ─── TCP read loop (called from I/O threads after connect/accept) ───────────── */
static void tcp_read_loop(int socket_id)
{
    posix_conn_t *conn = &sockets[socket_id];
    char *tmp = malloc(TCP_RECV_BUF);
    if (!tmp) return;

    while (!conn->io_stop) {
        sock_fd_t cur_fd;
        pthread_mutex_lock(&g_socket_mutex);
        cur_fd = conn->fd;
        pthread_mutex_unlock(&g_socket_mutex);
        if (cur_fd == INVALID_SOCK_FD) break;

        poll_fd_t pfd = { cur_fd, POLLIN, 0 };
        int ret = sock_poll(&pfd, 1, POLL_TIMEOUT_MS);
        if (ret < 0) break;
        if (ret == 0) continue;  /* timeout – check io_stop */
        if (pfd.revents & (POLLERR | POLLNVAL)) break;

        int nread = recv(cur_fd, tmp, TCP_RECV_BUF, 0);
        if (nread < 0) {
            if (sock_errno == SOCK_EWOULDBLOCK) continue;
            break;
        }
        if (nread == 0) break;  /* connection closed */

        pthread_mutex_lock(&conn->recv_lock);
        if (!conn->recv_buff) {
            conn->recv_buff = malloc(nread);
            if (conn->recv_buff) { memcpy(conn->recv_buff, tmp, nread); conn->recv_size = nread; }
        } else {
            char *p = realloc(conn->recv_buff, conn->recv_size + nread);
            if (p) { memcpy(p + conn->recv_size, tmp, nread); conn->recv_buff = p; conn->recv_size += nread; }
        }
        pthread_mutex_unlock(&conn->recv_lock);
        cb_to_nw_task(EV_NW_SOCKET_RX_NEW, socket_id, nread, 0);
    }
    free(tmp);

    /* Determine what event to post */
    int should_close = 0;
    pthread_mutex_lock(&g_socket_mutex);
    if (conn->state != SC_CLOSED && conn->state != SC_IDLE) {
        if (conn->io_stop) {
            conn->state = SC_CLOSED;
            should_close = 1;   /* we initiated close → CLOSE_OK */
        } else {
            conn->state = SC_CLOSING;
            should_close = -1;  /* remote initiated → REMOTE_CLOSE */
        }
    }
    /* Close fd here so it doesn't leak; do NOT clear io_running yet */
    sock_fd_t fd_to_close = conn->fd;
    conn->fd = INVALID_SOCK_FD;
    pthread_mutex_unlock(&g_socket_mutex);
    if (fd_to_close != INVALID_SOCK_FD) sock_close(fd_to_close);

    /* Post events before clearing io_running: prevents posix_create_socket from
     * reusing this slot while cb_to_nw_task still needs to read sockets[id].tag */
    if (should_close == 1)  cb_to_nw_task(EV_NW_SOCKET_CLOSE_OK,     socket_id, 0, 0);
    if (should_close == -1) cb_to_nw_task(EV_NW_SOCKET_REMOTE_CLOSE,  socket_id, 0, 0);

    /* Last action: mark slot available for reuse */
    pthread_mutex_lock(&g_socket_mutex);
    conn->io_running = 0;
    pthread_cond_broadcast(&g_slot_free_cond);
    pthread_mutex_unlock(&g_socket_mutex);
}

/* ─── TCP connect thread (client) ───────────────────────────────────────────── */
static void *tcp_connect_thread(void *arg)
{
    int socket_id = (int)(intptr_t)arg;
    posix_conn_t *conn = &sockets[socket_id];

    poll_fd_t pfd = { conn->fd, POLLOUT, 0 };
    int connected = 0;
    /* Wait up to 30 s for connect to complete */
    for (int i = 0; i < 300 && !conn->io_stop; i++) {
        int ret = sock_poll(&pfd, 1, POLL_TIMEOUT_MS);
        if (ret < 0) break;
        if (ret == 0) continue;
        /* Writable: check SO_ERROR */
        int err = get_sock_error(conn->fd);
        if (err != 0) {
            LLOGE("socket[%d] connect failed err=%d", socket_id, err);
            pthread_mutex_lock(&g_socket_mutex);
            conn->state = SC_CLOSED;
            sock_fd_t fd_to_close = conn->fd; conn->fd = INVALID_SOCK_FD;
            pthread_mutex_unlock(&g_socket_mutex);
            if (fd_to_close != INVALID_SOCK_FD) sock_close(fd_to_close);
            cb_to_nw_task(EV_NW_SOCKET_ERROR, socket_id, 0, 0);
            pthread_mutex_lock(&g_socket_mutex);
            conn->io_running = 0;
            pthread_cond_broadcast(&g_slot_free_cond);
            pthread_mutex_unlock(&g_socket_mutex);
            return NULL;
        }
        connected = 1;
        break;
    }

    if (!connected || conn->io_stop) {
        int send_error = !conn->io_stop;
        pthread_mutex_lock(&g_socket_mutex);
        conn->state = SC_CLOSED;
        sock_fd_t fd_to_close = conn->fd; conn->fd = INVALID_SOCK_FD;
        pthread_mutex_unlock(&g_socket_mutex);
        if (fd_to_close != INVALID_SOCK_FD) sock_close(fd_to_close);
        if (send_error)
            cb_to_nw_task(EV_NW_SOCKET_ERROR, socket_id, 0, 0);
        pthread_mutex_lock(&g_socket_mutex);
        conn->io_running = 0;
        pthread_cond_broadcast(&g_slot_free_cond);
        pthread_mutex_unlock(&g_socket_mutex);
        return NULL;
    }

    pthread_mutex_lock(&g_socket_mutex);
    conn->state = SC_CONNECTED;
    pthread_mutex_unlock(&g_socket_mutex);
    cb_to_nw_task(EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
    tcp_read_loop(socket_id);
    return NULL;
}

/* ─── TCP accept thread (server) ────────────────────────────────────────────── */
static void *tcp_accept_thread(void *arg)
{
    int socket_id = (int)(intptr_t)arg;
    posix_conn_t *conn = &sockets[socket_id];

    while (!conn->io_stop) {
        sock_fd_t srv_fd;
        pthread_mutex_lock(&g_socket_mutex);
        srv_fd = conn->server_fd;
        pthread_mutex_unlock(&g_socket_mutex);
        if (srv_fd == INVALID_SOCK_FD) break;

        poll_fd_t pfd = { srv_fd, POLLIN, 0 };
        int ret = sock_poll(&pfd, 1, POLL_TIMEOUT_MS);
        if (ret < 0) break;
        if (ret == 0) continue;
        if (pfd.revents & (POLLERR | POLLNVAL)) break;

        struct sockaddr_in client_addr;
        socklen_t alen = sizeof(client_addr);
        sock_fd_t cfd = accept(srv_fd, (struct sockaddr*)&client_addr, &alen);
        if (cfd == INVALID_SOCK_FD) continue;

        /* Only accept in LISTENING state */
        int cur_state;
        pthread_mutex_lock(&g_socket_mutex);
        cur_state = conn->state;
        pthread_mutex_unlock(&g_socket_mutex);

        if (cur_state != SC_LISTENING) {
            sock_close(cfd);
            LLOGW("socket[%d] 已有客户端连接, 拒绝新连接", socket_id);
            continue;
        }

        sock_nonblock(cfd);
#if !(defined(_WIN32) || defined(_WIN64))
        { int one = 1; setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one)); }
#endif

        pthread_mutex_lock(&g_socket_mutex);
        conn->fd    = cfd;
        conn->state = SC_CONNECTED;
        pthread_mutex_unlock(&g_socket_mutex);

        LLOGI("socket[%d] 收到新的客户端连接", socket_id);
        cb_to_nw_task(EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
        tcp_read_loop(socket_id);

        /* After client disconnects: close client fd, revert state unless stopping */
        pthread_mutex_lock(&g_socket_mutex);
        if (conn->fd != INVALID_SOCK_FD) { sock_close(conn->fd); conn->fd = INVALID_SOCK_FD; }
        /* Clear recv buffer */
        if (conn->recv_buff) { free(conn->recv_buff); conn->recv_buff = NULL; conn->recv_size = 0; }
        pthread_mutex_unlock(&g_socket_mutex);
    }

    /* Close server fd */
    pthread_mutex_lock(&g_socket_mutex);
    if (conn->server_fd != INVALID_SOCK_FD) { sock_close(conn->server_fd); conn->server_fd = INVALID_SOCK_FD; }
    conn->io_running = 0;
    pthread_cond_broadcast(&g_slot_free_cond);
    pthread_mutex_unlock(&g_socket_mutex);
    return NULL;
}

/* ─── UDP recv thread ────────────────────────────────────────────────────────── */
static void *udp_recv_thread(void *arg)
{
    int socket_id = (int)(intptr_t)arg;
    posix_conn_t *conn = &sockets[socket_id];

    while (!conn->io_stop) {
        sock_fd_t cur_fd;
        pthread_mutex_lock(&g_socket_mutex);
        cur_fd = conn->fd;
        pthread_mutex_unlock(&g_socket_mutex);
        if (cur_fd == INVALID_SOCK_FD) break;

        poll_fd_t pfd = { cur_fd, POLLIN, 0 };
        int ret = sock_poll(&pfd, 1, POLL_TIMEOUT_MS);
        if (ret < 0) break;
        if (ret == 0) continue;
        if (pfd.revents & (POLLERR | POLLNVAL)) break;

        char tmp[2048];
        struct sockaddr_in from;
        socklen_t flen = sizeof(from);
        int nread = recvfrom(cur_fd, tmp, sizeof(tmp), 0, (struct sockaddr*)&from, &flen);
        if (nread < 0) {
            if (sock_errno == SOCK_EWOULDBLOCK) continue;
            break;
        }
        if (nread == 0) continue;

        posix_udp_data_t *d = malloc(sizeof(posix_udp_data_t) + nread);
        if (!d) { LLOGE("OOM in udp_recv_thread"); continue; }
        memset(d, 0, sizeof(posix_udp_data_t));
        memcpy(d->data, tmp, nread);
        d->from = from;
        d->len  = nread;
        d->next = NULL;

        pthread_mutex_lock(&conn->udp_lock);
        if (!conn->udp_data) {
            conn->udp_data = d;
        } else {
            posix_udp_data_t *h = conn->udp_data;
            while (h->next) h = h->next;
            h->next = d;
        }
        pthread_mutex_unlock(&conn->udp_lock);
        cb_to_nw_task(EV_NW_SOCKET_RX_NEW, socket_id, nread, 0);
    }

    int should_post = 0;
    pthread_mutex_lock(&g_socket_mutex);
    if (conn->state != SC_CLOSED && conn->state != SC_IDLE && conn->io_stop) {
        conn->state = SC_CLOSED;
        should_post = 1;
    }
    /* Close fd; do NOT clear io_running until after the event is posted */
    sock_fd_t fd_to_close = conn->fd;
    conn->fd = INVALID_SOCK_FD;
    pthread_mutex_unlock(&g_socket_mutex);
    if (fd_to_close != INVALID_SOCK_FD) sock_close(fd_to_close);
    if (should_post) cb_to_nw_task(EV_NW_SOCKET_CLOSE_OK, socket_id, 0, 0);
    pthread_mutex_lock(&g_socket_mutex);
    conn->io_running = 0;
    pthread_cond_broadcast(&g_slot_free_cond);
    pthread_mutex_unlock(&g_socket_mutex);
    return NULL;
}

/* ─── DNS thread ─────────────────────────────────────────────────────────────── */
typedef struct { char domain[256]; void *param; } posix_dns_query_t;

static void *dns_resolve_thread(void *arg)
{
    posix_dns_query_t *q = (posix_dns_query_t *)arg;
    struct addrinfo hints = {0};
    hints.ai_family   = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    struct addrinfo *res = NULL;
    int r = getaddrinfo(q->domain, NULL, &hints, &res);
    if (r != 0 || !res) {
        LLOGI("dns query failed for %s", q->domain);
        cb_to_nw_task(EV_NW_DNS_RESULT, 0, 0, (size_t)q->param);
    } else {
        luat_dns_ip_result *ip_result = calloc(1, sizeof(luat_dns_ip_result));
        if (ip_result) {
            char addr[17] = {0};
            inet_ntop(AF_INET, &((struct sockaddr_in*)res->ai_addr)->sin_addr, addr, sizeof(addr));
            LLOGI("dns result ip %s", addr);
            network_set_ip_ipv4(&ip_result->ip,
                ((struct sockaddr_in*)res->ai_addr)->sin_addr.s_addr);
            ip_result->ttl_end = 60;
            cb_to_nw_task(EV_NW_DNS_RESULT, 1, (size_t)ip_result, (size_t)q->param);
        } else {
            cb_to_nw_task(EV_NW_DNS_RESULT, 0, 0, (size_t)q->param);
        }
        freeaddrinfo(res);
    }
    free(q);
    return NULL;
}

/* ─── Internal close helper ──────────────────────────────────────────────────── */
static int close_socket_internal(int socket_id, int force)
{
    posix_conn_t *conn = &sockets[socket_id];
    sock_fd_t fd, srv_fd;
    int cur_state, io_running;

    pthread_mutex_lock(&g_socket_mutex);
    conn->io_stop = 1;
    fd         = conn->fd;
    srv_fd     = conn->server_fd;
    cur_state  = conn->state;
    io_running = conn->io_running;
    if (force) { conn->state = SC_CLOSED; conn->tag = 0; }
    /* NOTE: do NOT clear conn->io_running here; the I/O thread must clear it when
     * it actually exits so that posix_create_socket won't reuse this slot too early. */
    pthread_mutex_unlock(&g_socket_mutex);

    /* Wake up any blocked poll/recv */
    if (fd != INVALID_SOCK_FD) {
        if (force) sock_close(fd);
        else       sock_shutdown_rw(fd);
        if (force) { pthread_mutex_lock(&g_socket_mutex); conn->fd = INVALID_SOCK_FD; pthread_mutex_unlock(&g_socket_mutex); }
    }
    if (srv_fd != INVALID_SOCK_FD) {
        if (force) {
            sock_close(srv_fd);
            pthread_mutex_lock(&g_socket_mutex); conn->server_fd = INVALID_SOCK_FD; pthread_mutex_unlock(&g_socket_mutex);
        } else {
            sock_shutdown_rw(srv_fd);
        }
    }

    if (force) {
        /* Immediate: return without CLOSE_OK */
        return 0;
    }

    /* Graceful: if I/O thread not running, post CLOSE_OK ourselves */
    if (!io_running && cur_state != SC_CLOSED && cur_state != SC_IDLE) {
        int should_post = 0;
        pthread_mutex_lock(&g_socket_mutex);
        if (conn->state != SC_CLOSED && conn->state != SC_IDLE) {
            conn->state = SC_CLOSED;
            should_post = 1;
        }
        pthread_mutex_unlock(&g_socket_mutex);
        if (should_post) cb_to_nw_task(EV_NW_SOCKET_CLOSE_OK, socket_id, 0, 0);
    }
    /* else: I/O thread is running; it will detect io_stop=1 and post CLOSE_OK */

    /* For SC_LISTENING with no io_running, just mark as closed with no event */
    if (cur_state == SC_LISTENING && !io_running) {
        pthread_mutex_lock(&g_socket_mutex);
        conn->state = SC_CLOSED; conn->tag = 0;
        pthread_mutex_unlock(&g_socket_mutex);
    }

    return 0;
}

/* ─── Vtable: socket management ─────────────────────────────────────────────── */
static int posix_check_ready(void *user_data) { (void)user_data; return 1; }

static int posix_socket_check(int socket_id, uint64_t tag, void *user_data)
{
    (void)user_data;
    if (socket_id < 0 || socket_id >= MAX_SOCK_NUM) return -1;
    return (sockets[socket_id].tag == tag) ? 0 : -1;
}

static int posix_create_socket(uint8_t is_tcp, uint64_t *tag, void *param,
                                uint8_t is_ipv6, void *user_data)
{
    (void)user_data;
    uint64_t stag = socket_tag_counter++;

    /* Scan and atomically claim a free slot under g_socket_mutex.
     * If every candidate has io_running==1 (I/O thread just posted its last event
     * but hasn't decremented io_running yet), wait up to 50 ms for a broadcast
     * from the exiting I/O thread rather than skipping to the next slot. */
    int chosen_idx = -1;
    char *old_recv_buff = NULL;
    sock_fd_t old_fd = INVALID_SOCK_FD, old_srv = INVALID_SOCK_FD;

    pthread_mutex_lock(&g_socket_mutex);
    for (int wait_round = 0; wait_round < 2 && chosen_idx < 0; wait_round++) {
        if (wait_round > 0) {
            /* Brief timed-wait for any I/O thread to signal slot availability.
             * luat_calc_abs_timeout handles both Windows and POSIX correctly. */
            struct timespec ts;
            luat_calc_abs_timeout(&ts, 50); /* 50 ms */
            pthread_cond_timedwait(&g_slot_free_cond, &g_socket_mutex, &ts);
        }
        for (int iz = 0; iz < MAX_SOCK_NUM; iz++) {
            int idx = (iz + ctrl.next_idx) % MAX_SOCK_NUM;
            posix_conn_t *c = &sockets[idx];
            if (c->tag == 0 &&
                (c->state == SC_IDLE || c->state == SC_CLOSED) &&
                c->io_running == 0) {
                /* Save stale resources for cleanup after releasing the lock */
                old_recv_buff = c->recv_buff;
                old_fd  = c->fd;
                old_srv = c->server_fd;
                /* Claim slot atomically */
                c->fd = INVALID_SOCK_FD;
                c->server_fd = INVALID_SOCK_FD;
                c->recv_buff = NULL; c->recv_size = 0;
                c->udp_data  = NULL;
                c->tag       = stag;
                c->param     = param;
                c->is_tcp    = is_tcp;
                c->is_ipv6   = is_ipv6;
                c->io_stop   = 0;
                c->io_running = 0;
                c->state     = SC_USED;
                ctrl.next_idx = (uint8_t)((idx + 1) % MAX_SOCK_NUM);
                *tag = stag;
                chosen_idx = idx;
                break;
            }
        }
    }
    pthread_mutex_unlock(&g_socket_mutex);

    if (chosen_idx < 0) {
        LLOGE("没有空闲的socket可创建了");
        return -1;
    }

    /* Free stale resources outside the lock (safe: io_running was 0) */
    if (old_recv_buff) free(old_recv_buff);
    if (old_fd  != INVALID_SOCK_FD) sock_close(old_fd);
    if (old_srv != INVALID_SOCK_FD) sock_close(old_srv);

    posix_conn_t *c = &sockets[chosen_idx];

    /* Create the OS socket */
    int type = is_tcp ? SOCK_STREAM : SOCK_DGRAM;
    c->fd = socket(AF_INET, type, 0);
    if (c->fd == INVALID_SOCK_FD) {
        LLOGE("socket() failed");
        pthread_mutex_lock(&g_socket_mutex);
        c->tag = 0; c->state = SC_IDLE;
        pthread_mutex_unlock(&g_socket_mutex);
        return -1;
    }
    sock_nonblock(c->fd);
#if !(defined(_WIN32) || defined(_WIN64))
    if (is_tcp) { int one = 1; setsockopt(c->fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one)); }
    if (is_tcp) { int one = 1; setsockopt(c->fd, SOL_SOCKET, SO_KEEPALIVE, &one, sizeof(one)); }
#else
    if (is_tcp) {
        DWORD one = 1; setsockopt(c->fd, SOL_SOCKET, SO_KEEPALIVE, (char*)&one, sizeof(one));
    }
#endif
    return chosen_idx;
}

static int posix_socket_connect(int socket_id, uint64_t tag, uint16_t local_port,
                                 luat_ip_addr_t *remote_ip, uint16_t remote_port,
                                 void *user_data)
{
    CHECK_SOCKET_ID
    posix_conn_t *c = &sockets[socket_id];

    struct sockaddr_in saddr = {0};
    saddr.sin_family = AF_INET;
#ifdef LUAT_USE_LWIP
    saddr.sin_addr.s_addr = ip_2_ip4(remote_ip)->addr;
#else
    saddr.sin_addr.s_addr = remote_ip->ipv4;
#endif
    saddr.sin_port = htons(remote_port);

    char ipstr[17] = {0};
    inet_ntop(AF_INET, &saddr.sin_addr, ipstr, sizeof(ipstr));
    LLOGI("socket[%d] connect to %s:%d %s", socket_id, ipstr, remote_port, c->is_tcp ? "TCP" : "UDP");

    if (c->is_tcp) {
        if (local_port) {
            struct sockaddr_in la = {0}; la.sin_family = AF_INET; la.sin_port = htons(local_port);
            bind(c->fd, (struct sockaddr*)&la, sizeof(la));
        }
        connect(c->fd, (struct sockaddr*)&saddr, sizeof(saddr));
        /* Non-blocking connect: EINPROGRESS/WSAEWOULDBLOCK expected */
        c->state = SC_CONNECTING;
        c->io_stop = 0; c->io_running = 1;
        start_detached_thread(tcp_connect_thread, (void*)(intptr_t)socket_id);
    } else {
        /* UDP: "connect" = store peer addr, bind locally, start recv thread */
        c->remote_addr = saddr;
        if (local_port) {
            struct sockaddr_in la = {0}; la.sin_family = AF_INET; la.sin_port = htons(local_port);
            bind(c->fd, (struct sockaddr*)&la, sizeof(la));
        } else {
            struct sockaddr_in la = {0}; la.sin_family = AF_INET;
            bind(c->fd, (struct sockaddr*)&la, sizeof(la));
        }
        c->state = SC_CONNECTING;
        c->io_stop = 0; c->io_running = 1;
        start_detached_thread(udp_recv_thread, (void*)(intptr_t)socket_id);
        /* UDP connect is instant */
        pthread_mutex_lock(&g_socket_mutex);
        c->state = SC_CONNECTED;
        pthread_mutex_unlock(&g_socket_mutex);
        cb_to_nw_task(EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
    }
    return 0;
}

static int posix_socket_listen(int socket_id, uint64_t tag, uint16_t local_port,
                                void *user_data)
{
    (void)user_data;
    if (socket_id < 0 || socket_id >= MAX_SOCK_NUM) { LLOGE("socket id不合法 %d", socket_id); return -1; }
    if (sockets[socket_id].tag != tag) { LLOGE("socket[%d] tag不匹配", socket_id); return -1; }

    posix_conn_t *c = &sockets[socket_id];

    /* If already have a server_fd, just re-arm listening state and fire event */
    if (c->server_fd != INVALID_SOCK_FD) {
        pthread_mutex_lock(&g_socket_mutex);
        c->state = SC_LISTENING;
        pthread_mutex_unlock(&g_socket_mutex);
        LLOGI("socket[%d] 重新设置监听状态", socket_id);
        cb_to_nw_task(EV_NW_SOCKET_LISTEN, socket_id, 0, 0);
        return 0;
    }

    /* Create server socket */
    sock_fd_t srv = socket(AF_INET, SOCK_STREAM, 0);
    if (srv == INVALID_SOCK_FD) { LLOGE("socket[%d] listen socket() failed", socket_id); return -1; }
    {
        int opt = 1;
#if defined(_WIN32) || defined(_WIN64)
        setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, (char*)&opt, sizeof(opt));
#else
        setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#endif
    }
    struct sockaddr_in ba = {0};
    ba.sin_family = AF_INET;
    ba.sin_port   = htons(local_port);
    if (bind(srv, (struct sockaddr*)&ba, sizeof(ba)) != 0) {
        LLOGE("socket[%d] bind port %d failed", socket_id, local_port);
        sock_close(srv); return -1;
    }
    if (listen(srv, 1) != 0) {
        LLOGE("socket[%d] listen port %d failed", socket_id, local_port);
        sock_close(srv); return -1;
    }

    pthread_mutex_lock(&g_socket_mutex);
    c->server_fd = srv;
    c->state = SC_LISTENING;
    c->io_stop = 0; c->io_running = 1;
    pthread_mutex_unlock(&g_socket_mutex);

    LLOGI("socket[%d] 开始监听端口 %d", socket_id, local_port);
    start_detached_thread(tcp_accept_thread, (void*)(intptr_t)socket_id);
    cb_to_nw_task(EV_NW_SOCKET_LISTEN, socket_id, 0, 0);
    return 0;
}

static int posix_socket_accept(int socket_id, uint64_t tag, luat_ip_addr_t *remote_ip,
                                uint16_t *remote_port, void *user_data)
{
    (void)user_data;
    if (socket_id < 0 || socket_id >= MAX_SOCK_NUM) return -1;
    if (sockets[socket_id].state != SC_CONNECTED) {
        LLOGE("socket[%d] accept失败, 当前状态 %s", socket_id,
              socket_state_str(sockets[socket_id].state));
        return -1;
    }
    struct sockaddr_storage peer;
    socklen_t plen = sizeof(peer);
    if (getpeername(sockets[socket_id].fd, (struct sockaddr*)&peer, &plen) == 0) {
        struct sockaddr_in *a4 = (struct sockaddr_in*)&peer;
        if (remote_ip) {
#ifdef LUAT_USE_LWIP
            ip_addr_set_ip4_u32_val((*remote_ip), a4->sin_addr.s_addr);
#else
            remote_ip->ipv4 = a4->sin_addr.s_addr;
#endif
        }
        if (remote_port) *remote_port = ntohs(a4->sin_port);
    }
    LLOGI("socket[%d] accept完成", socket_id);
    return 0;
}

static int posix_socket_disconnect(int socket_id, uint64_t tag, void *user_data)
{
    CHECK_SOCKET_ID
    if (sockets[socket_id].state == SC_CLOSED) return 0;
    return close_socket_internal(socket_id, 0);
}

static int posix_socket_close(int socket_id, uint64_t tag, void *user_data)
{
    CHECK_SOCKET_ID
    if (sockets[socket_id].state == SC_CLOSED) return 0;
    close_socket_internal(socket_id, 0);
    /* Return 1 (non-zero) so network_force_close_socket knows to also call
     * posix_socket_force_close, which clears tag=0 and makes the slot reusable.
     * If we return 0, the framework skips the force_close path and tag is never
     * cleared, causing slot exhaustion after ~32 connections. */
    return 1;
}

static int posix_socket_force_close(int socket_id, void *user_data)
{
    (void)user_data;
    if (socket_id < 0 || socket_id >= MAX_SOCK_NUM) return -1;
    /* Only skip if both tag and fd are already cleared (truly fully released) */
    if (sockets[socket_id].tag == 0 && sockets[socket_id].fd == INVALID_SOCK_FD
            && sockets[socket_id].server_fd == INVALID_SOCK_FD) {
        LLOGI("socket[%d] force_close 该socket已经释放过", socket_id);
        return 0;
    }
    return close_socket_internal(socket_id, 1 /* force */);
}

static int posix_socket_receive(int socket_id, uint64_t tag, uint8_t *buf, uint32_t len,
                                 int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port,
                                 void *user_data)
{
    CHECK_SOCKET_ID
    (void)flags; (void)user_data;

    if (sockets[socket_id].is_tcp) {
        posix_conn_t *c = &sockets[socket_id];
        pthread_mutex_lock(&c->recv_lock);
        if (buf == NULL) {
            int sz = (int)c->recv_size;
            pthread_mutex_unlock(&c->recv_lock);
            return sz;
        }
        if (c->recv_size == 0 || len == 0) {
            pthread_mutex_unlock(&c->recv_lock);
            return 0;
        }
        if (len > (uint32_t)c->recv_size) len = (uint32_t)c->recv_size;
        memcpy(buf, c->recv_buff, len);
        size_t newsize = c->recv_size - len;
        if (newsize == 0) {
            free(c->recv_buff); c->recv_buff = NULL; c->recv_size = 0;
        } else {
            char *p = malloc(newsize);
            if (p) memcpy(p, c->recv_buff + len, newsize);
            free(c->recv_buff);
            c->recv_buff = p; c->recv_size = p ? newsize : 0;
        }
        pthread_mutex_unlock(&c->recv_lock);
        return (int)len;
    } else {
        /* UDP */
        posix_conn_t *c = &sockets[socket_id];
        pthread_mutex_lock(&c->udp_lock);
        if (buf == NULL) {
            int sz = c->udp_data ? (int)c->udp_data->len : 0;
            pthread_mutex_unlock(&c->udp_lock);
            return sz;
        }
        if (!c->udp_data || len == 0) {
            pthread_mutex_unlock(&c->udp_lock);
            return 0;
        }
        if (len > (uint32_t)c->udp_data->len) len = (uint32_t)c->udp_data->len;
        memcpy(buf, c->udp_data->data, len);
        if (remote_ip) {
#ifndef LUAT_USE_LWIP
            remote_ip->is_ipv6 = 0;
#endif
            network_set_ip_ipv4(remote_ip, c->udp_data->from.sin_addr.s_addr);
        }
        if (remote_port) *remote_port = ntohs(c->udp_data->from.sin_port);
        posix_udp_data_t *old = c->udp_data;
        c->udp_data = (posix_udp_data_t *)old->next;
        pthread_mutex_unlock(&c->udp_lock);
        free(old);
        return (int)len;
    }
}

static int posix_socket_send(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len,
                              int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port,
                              void *user_data)
{
    CHECK_SOCKET_ID
    (void)flags; (void)user_data;
    if (len == 0) return 0;
    if (sockets[socket_id].state != SC_CONNECTED) {
        LLOGW("socket[%d] 链接没建立,不能发送数据", socket_id);
        return -1;
    }
    posix_conn_t *c = &sockets[socket_id];

    if (c->is_tcp) {
        int sent = 0;
        while (sent < (int)len) {
            int n = send(c->fd, (const char*)buf + sent, len - sent, 0);
            if (n > 0) { sent += n; continue; }
            if (n < 0 && sock_errno == SOCK_EWOULDBLOCK) {
                poll_fd_t pfd = {c->fd, POLLOUT, 0};
                if (sock_poll(&pfd, 1, 5000) <= 0) break;
                continue;
            }
            break;
        }
        if (sent <= 0) {
            cb_to_nw_task(EV_NW_SOCKET_ERROR, socket_id, 0, 0);
            return -1;
        }
        cb_to_nw_task(EV_NW_SOCKET_TX_OK, socket_id, sent, 0);
        return sent;
    } else {
        /* UDP sendto */
        struct sockaddr_in dst = c->remote_addr;
        if (remote_ip) {
#ifdef LUAT_USE_LWIP
            dst.sin_addr.s_addr = ip_2_ip4(remote_ip)->addr;
#else
            dst.sin_addr.s_addr = remote_ip->ipv4;
#endif
            dst.sin_port = htons(remote_port);
        }
        int n = sendto(c->fd, (const char*)buf, len, 0,
                       (struct sockaddr*)&dst, sizeof(dst));
        if (n < 0) {
            cb_to_nw_task(EV_NW_SOCKET_ERROR, socket_id, 0, 0);
            return -1;
        }
        cb_to_nw_task(EV_NW_SOCKET_TX_OK, socket_id, n, 0);
        return n;
    }
}

static void posix_socket_clean(int *valid_list, uint32_t num, void *user_data)
{
    (void)user_data;
    for (uint32_t i = 0; i < num; i++) {
        int sid = valid_list[i];
        if (sid < 0 || sid >= MAX_SOCK_NUM) continue;
        posix_conn_t *c = &sockets[sid];
        if (c->tag == 0 || c->state == SC_CLOSED) {
            pthread_mutex_lock(&c->recv_lock);
            if (c->recv_buff) { free(c->recv_buff); c->recv_buff = NULL; c->recv_size = 0; }
            pthread_mutex_unlock(&c->recv_lock);

            pthread_mutex_lock(&c->udp_lock);
            posix_udp_data_t *h = c->udp_data;
            while (h) { posix_udp_data_t *n = h->next; free(h); h = n; }
            c->udp_data = NULL;
            pthread_mutex_unlock(&c->udp_lock);

            c->state = SC_IDLE;
        }
    }
}

/* ─── IP info ─────────────────────────────────────────────────────────────────── */
static int posix_get_local_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask,
                                    luat_ip_addr_t *gateway, void *user_data)
{
    (void)user_data;
#if defined(_WIN32) || defined(_WIN64)
    IP_ADAPTER_INFO adapters[16];
    DWORD bufLen = sizeof(adapters);
    if (GetAdaptersInfo(adapters, &bufLen) != ERROR_SUCCESS) return -1;
    IP_ADAPTER_INFO *a = adapters;
    while (a) {
        if (strcmp(a->IpAddressList.IpAddress.String, "127.0.0.1") != 0
            && strcmp(a->IpAddressList.IpAddress.String, "0.0.0.0") != 0) {
            struct in_addr ia, im, ig;
            inet_pton(AF_INET, a->IpAddressList.IpAddress.String, &ia);
            inet_pton(AF_INET, a->IpAddressList.IpMask.String,    &im);
            network_set_ip_ipv4(ip,      ia.s_addr);
            network_set_ip_ipv4(submask, im.s_addr);
            network_set_ip_ipv4(gateway, ia.s_addr | 0x01000000u);
            return 0;
        }
        a = a->Next;
    }
    return -1;
#else
    struct ifaddrs *ifap = NULL, *ifa;
    if (getifaddrs(&ifap) != 0) return -1;
    for (ifa = ifap; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
        if (sa->sin_addr.s_addr == htonl(INADDR_LOOPBACK)) continue;
        network_set_ip_ipv4(ip,      sa->sin_addr.s_addr);
        if (ifa->ifa_netmask) {
            struct sockaddr_in *sm = (struct sockaddr_in*)ifa->ifa_netmask;
            network_set_ip_ipv4(submask, sm->sin_addr.s_addr);
        }
        network_set_ip_ipv4(gateway, sa->sin_addr.s_addr | 0x01000000u);
        freeifaddrs(ifap);
        return 0;
    }
    freeifaddrs(ifap);
    return -1;
#endif
}

static int posix_get_full_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask,
                                   luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6,
                                   void *user_data)
{
    if (ipv6) network_set_ip_invaild(ipv6);
    return posix_get_local_ip_info(ip, submask, gateway, user_data);
}

/* ─── Misc vtable stubs ──────────────────────────────────────────────────────── */
static int posix_user_cmd(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value,
                           void *user_data)
{ (void)socket_id;(void)tag;(void)cmd;(void)value;(void)user_data; return 0; }

static int posix_dns(const char *domain_name, uint32_t len, void *param, void *user_data)
{
    (void)user_data;
    posix_dns_query_t *q = calloc(1, sizeof(posix_dns_query_t));
    if (!q) return -1;
    size_t copy_len = len < 255 ? len : 255;
    memcpy(q->domain, domain_name, copy_len);
    q->domain[copy_len] = 0;
    q->param = param;
    start_detached_thread(dns_resolve_thread, q);
    return 0;
}

static int posix_dns_ipv6(const char *domain_name, uint32_t len, void *param, void *user_data)
{ (void)domain_name;(void)len;(void)param;(void)user_data; return -1; }

static int posix_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data)
{ (void)server_index;(void)ip;(void)user_data; return 0; }

static int posix_set_mac(uint8_t *mac, void *user_data)
{ (void)mac;(void)user_data; return 0; }

static int posix_set_static_ip(luat_ip_addr_t *ip, luat_ip_addr_t *submask,
                                luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6,
                                void *user_data)
{ (void)ip;(void)submask;(void)gateway;(void)ipv6;(void)user_data; return 0; }

static int32_t posix_dummy_callback(void *pData, void *pParam)
{ (void)pData;(void)pParam; return 0; }

static void posix_socket_set_callback(CBFuncEx_t cb_fun, void *param, void *user_data)
{
    (void)user_data;
    ctrl.socket_cb  = cb_fun ? cb_fun : posix_dummy_callback;
    ctrl.user_data  = param;
}

static int posix_getsockopt(int socket_id, uint64_t tag, int level, int optname,
                             void *optval, uint32_t *optlen, void *user_data)
{ (void)socket_id;(void)tag;(void)level;(void)optname;(void)optval;(void)optlen;(void)user_data; return 0; }

static int posix_setsockopt(int socket_id, uint64_t tag, int level, int optname,
                             const void *optval, uint32_t optlen, void *user_data)
{ (void)socket_id;(void)tag;(void)level;(void)optname;(void)optval;(void)optlen;(void)user_data; return 0; }

/* ─── Adapter info ───────────────────────────────────────────────────────────── */
static const network_adapter_info prv_posix_adapter = {
    .check_ready       = posix_check_ready,
    .create_soceket    = posix_create_socket,
    .socket_connect    = posix_socket_connect,
    .socket_listen     = posix_socket_listen,
    .socket_accept     = posix_socket_accept,
    .socket_disconnect = posix_socket_disconnect,
    .socket_close      = posix_socket_close,
    .socket_force_close= posix_socket_force_close,
    .socket_receive    = posix_socket_receive,
    .socket_send       = posix_socket_send,
    .socket_check      = posix_socket_check,
    .socket_clean      = posix_socket_clean,
    .getsockopt        = posix_getsockopt,
    .setsockopt        = posix_setsockopt,
    .user_cmd          = posix_user_cmd,
    .dns               = posix_dns,
    .set_dns_server    = posix_set_dns_server,
    .dns_ipv6          = posix_dns_ipv6,
    .set_mac           = posix_set_mac,
    .set_static_ip     = posix_set_static_ip,
    .get_local_ip_info = posix_get_local_ip_info,
    .get_full_ip_info  = posix_get_full_ip_info,
    .socket_set_callback = posix_socket_set_callback,
    .name              = "posix",
    .max_socket_num    = MAX_SOCK_NUM,
    .no_accept         = 1,
    .is_posix          = 1,
};

/* ─── IP_READY timer ─────────────────────────────────────────────────────────── */
static int32_t l_ip_ready(lua_State *L, void *ptr)
{
    (void)ptr;
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (!lua_isfunction(L, -1)) return 0;
    if (msg->arg1) {
        lua_pushliteral(L, "IP_READY");
        uint32_t ip = (uint32_t)msg->arg2;
        lua_pushfstring(L, "%d.%d.%d.%d",
            ip & 0xFF, (ip >> 8) & 0xFF, (ip >> 16) & 0xFF, (ip >> 24) & 0xFF);
        lua_pushinteger(L, NW_ADAPTER_INDEX_ETH0);
        lua_call(L, 3, 0);
    } else {
        lua_pushliteral(L, "IP_LOSE");
        lua_pushinteger(L, NW_ADAPTER_INDEX_ETH0);
        lua_call(L, 2, 0);
    }
    return 0;
}

static void ip_ready_timer_cb(void *arg)
{
    (void)arg;
    rtos_msg_t msg = {0};
    msg.handler = l_ip_ready;
    msg.arg1 = 1;
    msg.arg2 = (int)posix_get_host_ipv4_u32();
    luat_msgbus_put(&msg, 0);
}

/* ─── Init ────────────────────────────────────────────────────────────────────── */
void luat_network_init(void)
{
    /* Init per-socket mutexes */
    for (int i = 0; i < MAX_SOCK_NUM; i++) {
        sockets[i].fd = INVALID_SOCK_FD;
        sockets[i].server_fd = INVALID_SOCK_FD;
        pthread_mutex_init(&sockets[i].recv_lock, NULL);
        pthread_mutex_init(&sockets[i].udp_lock, NULL);
    }

#if defined(_WIN32) || defined(_WIN64)
    WSADATA wd; WSAStartup(MAKEWORD(2,2), &wd);
#endif

    network_register_adapter(NW_ADAPTER_INDEX_ETH0,
                             (network_adapter_info*)&prv_posix_adapter, NULL);

    /* Publish IP_READY after 500 ms */
    luat_timer_handle_t h = luat_timer_engine_create(ip_ready_timer_cb, NULL);
    luat_timer_engine_start(h, 500, 0);
}

#ifndef LUAT_USE_LWIP
int net_lwip_check_all_ack(int socket_id) { (void)socket_id; return 0; }
#endif
