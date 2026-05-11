
#include "luat_posix_compat.h"

#include <stdlib.h>
#include <string.h>
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_uart.h"
#include "luat_uart_drv.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "uart.udp"
#include "luat_log.h"

#include "luat_pcconf.h"

#if defined(_WIN32) || defined(_WIN64)
  #include <winsock2.h>
  typedef SOCKET udp_sock_t;
  #define UDP_INVALID_SOCK INVALID_SOCKET
  #define udp_close(fd) closesocket(fd)
  #define udp_poll WSAPoll
  typedef WSAPOLLFD udp_poll_fd_t;
  #define UDP_EWOULDBLOCK WSAEWOULDBLOCK
  #define udp_errno WSAGetLastError()
#else
  #include <sys/socket.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #include <poll.h>
  #include <fcntl.h>
  #include <unistd.h>
  typedef int udp_sock_t;
  #define UDP_INVALID_SOCK ((udp_sock_t)(-1))
  #define udp_close(fd) close(fd)
  #define udp_poll poll
  typedef struct pollfd udp_poll_fd_t;
  #define UDP_EWOULDBLOCK EWOULDBLOCK
  #define udp_errno errno
#endif

typedef struct uart_drv_udp
{
    udp_sock_t fd;
    struct sockaddr_in remote;
    int state;                  /* 0=closed, 1=open */
    volatile int stop_flag;
    pthread_t recv_thread;
    char* recv_buff;
    size_t recv_len;
    pthread_mutex_t recv_lock;
} uart_drv_udp_t;

static uart_drv_udp_t udps[8];

static void *udp_recv_thread_fn(void *arg)
{
    int uart_id = (int)(intptr_t)arg;
    uart_drv_udp_t *u = &udps[uart_id];

    while (!u->stop_flag) {
        udp_poll_fd_t pfd;
        pfd.fd = u->fd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        int ret = udp_poll(&pfd, 1, 100);
        if (ret <= 0) continue;
        if (pfd.revents & (POLLERR | POLLNVAL)) break;

        char tmp[1500];
        struct sockaddr_in from;
        socklen_t flen = sizeof(from);
        int nread = recvfrom(u->fd, tmp, sizeof(tmp), 0, (struct sockaddr*)&from, &flen);
        if (nread <= 0) {
            if (nread < 0 && udp_errno == UDP_EWOULDBLOCK) continue;
            break;
        }

        pthread_mutex_lock(&u->recv_lock);
        size_t newsize = u->recv_len + nread;
        if (u->recv_buff == NULL) {
            u->recv_buff = luat_heap_malloc(nread);
            if (u->recv_buff) { memcpy(u->recv_buff, tmp, nread); u->recv_len = nread; }
        } else {
            void *p = luat_heap_realloc(u->recv_buff, newsize);
            if (p) {
                memcpy((char*)p + u->recv_len, tmp, nread);
                u->recv_buff = p; u->recv_len = newsize;
            } else {
                LLOGE("overflow when uart udp recv");
            }
        }
        pthread_mutex_unlock(&u->recv_lock);

        rtos_msg_t msg = { .handler = l_uart_handler, .arg1 = uart_id, .arg2 = nread };
        luat_msgbus_put(&msg, 0);
    }
    return NULL;
}

static int uart_setup_udp(void* userdata, luat_uart_t* uart) {
    if (uart->id < 0 || uart->id >= 8) return -1;
    if (udps[uart->id].state) return 0;

    uart_drv_udp_t *u = &udps[uart->id];
    memset(u, 0, sizeof(*u));
    pthread_mutex_init(&u->recv_lock, NULL);

    LLOGD("初始化uart udp %d port %d %d", uart->id, 9000 + uart->id, 19000 + uart->id);

    u->fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (u->fd == UDP_INVALID_SOCK) { LLOGE("udp socket() failed"); return -1; }

    /* Set non-blocking */
#if defined(_WIN32) || defined(_WIN64)
    { u_long mode = 1; ioctlsocket(u->fd, FIONBIO, &mode); }
#else
    { int f = fcntl(u->fd, F_GETFL, 0); fcntl(u->fd, F_SETFL, f | O_NONBLOCK); }
#endif

    /* Bind to local receive port */
    struct sockaddr_in la = {0};
    la.sin_family = AF_INET;
    la.sin_port   = htons((uint16_t)(9000 + uart->id));
    if (bind(u->fd, (struct sockaddr*)&la, sizeof(la)) != 0) {
        LLOGW("udp bind port %d failed", 9000 + uart->id);
        udp_close(u->fd); u->fd = UDP_INVALID_SOCK; return -1;
    }

    /* Default remote: 127.0.0.1:19000+id */
    u->remote.sin_family = AF_INET;
    u->remote.sin_port   = htons((uint16_t)(19000 + uart->id));
    inet_pton(AF_INET, "127.0.0.1", &u->remote.sin_addr);

    u->stop_flag = 0;
    u->state     = 1;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&u->recv_thread, &attr, udp_recv_thread_fn, (void*)(intptr_t)uart->id);
    pthread_attr_destroy(&attr);
    return 0;
}

static int uart_write_udp(void* userdata, int uart_id, void* data, size_t length) {
    if (uart_id < 0 || uart_id >= 8) return 0;
    if (udps[uart_id].state == 0) return 0;

    uart_drv_udp_t *u = &udps[uart_id];
    char *ptr = data;
    while (length > 0) {
        size_t chunk = length > 512 ? 512 : length;
        sendto(u->fd, ptr, (int)chunk, 0,
               (struct sockaddr*)&u->remote, sizeof(u->remote));
        ptr    += chunk;
        length -= chunk;
        if (length > 0) luat_sleep_ms(1);  /* reduce UDP ordering errors */
    }
    rtos_msg_t msg = { .handler = l_uart_handler, .arg1 = uart_id, .arg2 = 0 };
    luat_msgbus_put(&msg, 0);
    return 0;
}

static int uart_read_udp(void* userdata, int uart_id, void* buffer, size_t length) {
    if (uart_id < 0 || uart_id >= 8) return 0;
    if (udps[uart_id].state == 0) return 0;

    uart_drv_udp_t *u = &udps[uart_id];
    pthread_mutex_lock(&u->recv_lock);
    if (u->recv_len == 0) { pthread_mutex_unlock(&u->recv_lock); return 0; }
    if (length > u->recv_len) length = u->recv_len;
    memcpy(buffer, u->recv_buff, length);
    if (u->recv_len > length) {
        size_t newsize = u->recv_len - length;
        memmove(u->recv_buff, u->recv_buff + length, newsize);
        void* p = luat_heap_realloc(u->recv_buff, newsize);
        u->recv_buff = p;
        u->recv_len  = newsize;
    } else {
        luat_heap_free(u->recv_buff);
        u->recv_buff = NULL;
        u->recv_len  = 0;
    }
    pthread_mutex_unlock(&u->recv_lock);
    return (int)length;
}

static int uart_close_udp(void* userdata, int uart_id) {
    if (uart_id < 0 || uart_id >= 8) return 0;
    uart_drv_udp_t *u = &udps[uart_id];
    if (u->state == 0) return 0;
    u->stop_flag = 1;
    if (u->fd != UDP_INVALID_SOCK) {
#if defined(_WIN32) || defined(_WIN64)
        shutdown(u->fd, SD_BOTH);
#else
        shutdown(u->fd, SHUT_RDWR);
#endif
        udp_close(u->fd);
        u->fd = UDP_INVALID_SOCK;
    }
    u->state = 0;
    return 0;
}


const luat_uart_drv_opts_t uart_udp = {
    .setup = uart_setup_udp,
    .write = uart_write_udp,
    .read  = uart_read_udp,
    .close = uart_close_udp,
};

