#include "luat_base.h"

#ifndef LUAT_LIBTCPIP_H
#define LUAT_LIBTCPIP_H

#define LUAT_SOCK_STREAM 1
#define LUAT_AF_INET 2
#define LUAT_PF_INET LUAT_AF_INET
#define LUAT_IPPROTO_IP      0
#define LUAT_IPPROTO_ICMP    1
#define LUAT_IPPROTO_TCP     6
#define LUAT_IPPROTO_UDP     17

typedef int (*luat_libtcpip_socket)(int domain, int type, int protocol);
typedef int (*luat_libtcpip_send)(int s, const void *data, size_t size, int flags);
typedef int (*luat_libtcpip_recv)(int s, void *mem, size_t len, int flags);
typedef int (*luat_libtcpip_recv_timeout)(int s, void *mem, size_t len, int flags, int timeout_ms);
// typedef int (*luat_libtcpip_select)(int maxfdp1, fd_set *readset, fd_set *writeset, fd_set *exceptset,
//             struct timeval *timeout);
typedef int (*luat_libtcpip_close)(int fd);
typedef int (*luat_libtcpip_connect)(int s, const char *hostname, uint16_t port);
typedef struct hostent* (*luat_libtcpip_gethostbyname)(const char* name);
typedef int (*luat_libtcpip_setsockopt)(int s, int level, int optname, const void *optval, uint32_t optlen);

typedef struct luat_libtcpip_opts
{
    luat_libtcpip_socket          _socket;
    luat_libtcpip_send            _send;
    luat_libtcpip_recv            _recv;
    luat_libtcpip_recv_timeout    _recv_timeout;
    luat_libtcpip_close           _close;
    // luat_libtcpip_select          _select;
    luat_libtcpip_connect         _connect;
    luat_libtcpip_gethostbyname   _gethostbyname;
    luat_libtcpip_setsockopt      _setsockopt;
}luat_libtcpip_opts_t;

#endif
