
#include "luat_base.h"

int luat_socket_ntp_sync(const char* ntpServer);
int luat_socket_tsend(const char* hostname, int port, void* buff, int len);
