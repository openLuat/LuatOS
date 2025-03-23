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
#include "luat_mem.h"
#include "luat_msgbus.h"

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

// 注意, 下面的函数, 是主机端使用的, 例如scan的回调结果
extern uint8_t drv_scan_result_size;
extern uint8_t *drv_scan_result;

static int scan_result_handler(lua_State* L, void* ptr) {
    lua_getglobal(L, "sys_pub");
    lua_pushstring(L, "WLAN_SCAN_DONE");
    lua_call(L, 1, 0);
    return 0;
}

int luat_airlink_cmd_exec_wlan_scan_result_cb(luat_airlink_cmd_t* cmd, void* userdata) {
    uint8_t tmp = cmd->data[0];
    LLOGD("收到扫描结果 %d", tmp);
    if (drv_scan_result) {
        luat_heap_opt_free(AIRLINK_MEM_TYPE, drv_scan_result);
        drv_scan_result = NULL;
        drv_scan_result_size = 0;
    }
    if (tmp > 0) {
        drv_scan_result = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, tmp * sizeof(luat_wlan_scan_result_t));
        if (drv_scan_result) {
            memcpy(drv_scan_result, cmd->data + 1, tmp * sizeof(luat_wlan_scan_result_t));
            drv_scan_result_size = tmp;
        }
        else {
            LLOGW("获取到扫描结果, 但是内存不足, 丢弃 %d", tmp);
        }
    }
    // 发送通知
    rtos_msg_t msg = {0};
    msg.handler = scan_result_handler;
    luat_msgbus_put(&msg, 0);
    return 0;
}