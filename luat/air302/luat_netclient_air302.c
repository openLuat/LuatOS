



#include <stdio.h>
#include <string.h>
#include <stdlib.h>
//#include "elog.h"
#include "netclient.h"
#include "luat_malloc.h"

uint32_t netc_next_no(void) {
    return 0;
}
//netclient_t *netclient_create(void);
int32_t netclient_start(netclient_t * thiz) {
    return 1;
}
void netclient_close(netclient_t *thiz) {
    return;
}
//int32_t netclient_attach_rx_cb(netclient_t *thiz, tpc_cb_t cb);
int32_t netclient_send(netclient_t *thiz, const void *buff, size_t len) {
    return 0;
}
