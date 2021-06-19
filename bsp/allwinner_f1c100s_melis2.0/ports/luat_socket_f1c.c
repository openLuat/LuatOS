#include "luat_base.h"
#include "luat_socket.h"
#include "netclient.h"

int luat_socket_ntp_sync(const char* ntpServer) {
    return 0;
}

int luat_socket_tsend(const char* hostname, int port, void* buff, int len) {
    return 0;
}

int luat_socket_is_ready(void) {
    return 0;
}

uint32_t luat_socket_selfip(void) {
    return (uint32_t)-1;
}

uint32_t netc_next_no(void) {
    return 0;
}
//netclient_t *netclient_create(void);
int32_t netclient_start(netclient_t * thiz) {
    return -1;
}
int32_t netclient_rebind(netclient_t * thiz) {
    return -1;
}
void netclient_close(netclient_t *thiz) {
    return;
}
//int32_t netclient_attach_rx_cb(netclient_t *thiz, tpc_cb_t cb);
int32_t netclient_send(netclient_t *thiz, const void *buff, size_t len, int flags) {
    return 0;
}

