#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_pm.h"
#include "luat_airlink.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "luat_wlan.h"

#define LUAT_LOG_TAG "airlink.wlan"
#include "luat_log.h"

int luat_airlink_cmd_exec_wlan_init(luat_airlink_cmd_t* cmd, void* userdata) {
    int ret = luat_wlan_init(NULL);
    LLOGD("luat_wlan_init ret=%d", ret);
    return 0;
}

int luat_airlink_cmd_exec_wlan_sta_connect(luat_airlink_cmd_t* cmd, void* userdata) {
    luat_wlan_conninfo_t* info = (luat_wlan_conninfo_t*)(cmd->data+8);
    int ret = luat_wlan_connect(info);
    LLOGD("luat_wlan_connect ret=%d", ret);
    return 0;
}

int luat_airlink_cmd_exec_wlan_sta_disconnect(luat_airlink_cmd_t* cmd, void* userdata) {
    int ret = luat_wlan_disconnect();
    LLOGD("luat_wlan_disconnect ret=%d", ret);
    return 0;
}

int luat_airlink_cmd_exec_wlan_ap_start(luat_airlink_cmd_t* cmd, void* userdata) {
    luat_wlan_apinfo_t* info = (luat_wlan_apinfo_t*)(cmd->data+8);
    int ret = luat_wlan_ap_start(info);
    LLOGD("luat_wlan_ap_start ret=%d", ret);
    return 0;
}

int luat_airlink_cmd_exec_wlan_ap_stop(luat_airlink_cmd_t* cmd, void* userdata) {
    int ret = luat_wlan_ap_stop();
    LLOGD("luat_wlan_ap_stop ret=%d", ret);
    return 0;
}

int luat_airlink_cmd_exec_wlan_scan(luat_airlink_cmd_t* cmd, void* userdata) {
    int ret = luat_wlan_scan();
    LLOGD("luat_wlan_scan ret=%d", ret);
    return 0;
}
