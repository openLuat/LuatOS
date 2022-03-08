#include "luat_base.h"

#include "string.h"

#ifdef LUAT_USE_LIBTCPIP_POSIX

#include "time.h"

#include "luat_libtcpip.h"
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>

#define LUAT_LOG_TAG "posix"
#include "luat_log.h"

static int luat_libtcpip_socket_posix(int domain, int type, int protocol) {
    return socket(domain, type, protocol);
}

static int luat_libtcpip_send_posix(int s, const void *data, size_t size, int flags) {
    return send(s, data, size, flags);
}

static int luat_libtcpip_recv_posix(int s, void *mem, size_t len, int flags) {
    return recv(s, mem, len, flags);
}

static int luat_libtcpip_recv_timeout_posix(int s, void *mem, size_t len, int flags, int timeout) {
    int ret;
    struct timeval tv;
    fd_set read_fds;
    int fd = s;

    FD_ZERO( &read_fds );
    FD_SET( fd, &read_fds );

    tv.tv_sec  = timeout / 1000;
    tv.tv_usec = ( timeout % 1000 ) * 1000;

    ret = select( fd + 1, &read_fds, NULL, NULL, timeout == 0 ? NULL : &tv );

    /* Zero fds ready means we timed out */
    if( ret == 0 )
        return -1;

    if( ret < 0 )
    {
        return ret;
    }

    /* This call will not block */
    return recv( fd, mem, len, flags);
}

static int luat_libtcpip_select_posix(int maxfdp1, fd_set *readset, fd_set *writeset, fd_set *exceptset,
            struct timeval *timeout) {
    return select(maxfdp1, readset, writeset, exceptset, timeout);
}

static int luat_libtcpip_close_posix(int s) {
    // return close(s);
    return close(s);
}

static int luat_libtcpip_connect_posix(int s, const char *hostname, uint16_t port) {
    struct sockaddr_in socket_address;
    struct hostent *hp;

    hp = gethostbyname(hostname);
    if (hp == NULL )
    {
        LLOGW("DNS Query Fail %s", hostname);
        return -2;
    }

    memset(&socket_address, 0, sizeof(struct sockaddr_in));
    socket_address.sin_family = AF_INET;
    socket_address.sin_port = htons(port);
    memcpy(&(socket_address.sin_addr), hp->h_addr, hp->h_length);

    return connect(s, &socket_address, sizeof(socket_address));
}

static struct hostent* luat_libtcpip_gethostbyname_posix(const char* name) {
    return gethostbyname(name);
}

static int luat_libtcpip_setsockopt_posix(int s, int level, int optname, const void *optval, uint32_t optlen) {
    return setsockopt(s, level, optname, optval, (socklen_t)optlen);
}

luat_libtcpip_opts_t luat_libtcpip_posix = {
    ._socket = luat_libtcpip_socket_posix,
    ._close = luat_libtcpip_close_posix,
    ._connect = luat_libtcpip_connect_posix,
    ._gethostbyname = luat_libtcpip_gethostbyname_posix,
    ._recv = luat_libtcpip_recv_posix,
    ._recv_timeout = luat_libtcpip_recv_timeout_posix,
    // ._select = luat_libtcpip_select_posix,
    ._send = luat_libtcpip_send_posix,
    ._setsockopt = luat_libtcpip_setsockopt_posix
};

#endif
