#ifndef LUAT_SOCKET_H
#define LUAT_SOCKET_H
#include "luat_base.h"

int luat_socket_ntp_sync(const char* ntpServer);
int luat_socket_tsend(const char* hostname, int port, void* buff, int len);
int luat_socket_is_ready(void);
uint32_t luat_socket_selfip(void);

#endif
