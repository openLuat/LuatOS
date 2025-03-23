#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_wlan.h"
#include "luat_airlink.h"
#include "luat/drv_wlan.h"
#include "luat_network_adapter.h"
#include "luat_netdrv.h"

#define LUAT_LOG_TAG "drv.gpio"
#include "luat_log.h"

// #undef LLOGD
// #define LLOGD(...) 

int luat_drv_wlan_init(luat_wlan_config_t *conf) {
    return luat_airlink_drv_wlan_init(conf);
}

int luat_drv_wlan_mode(luat_wlan_config_t *conf) {
    return 0;
}

int luat_drv_wlan_ready(void) {
    return 1;
}

int luat_drv_wlan_connect(luat_wlan_conninfo_t* info) {
    return luat_airlink_drv_wlan_connect(info);
}

int luat_drv_wlan_disconnect(void) {
    return luat_airlink_drv_wlan_disconnect();
}

int luat_drv_wlan_scan(void) {
    return 0;
}

int luat_drv_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit) {
    return 0;
}

int luat_drv_wlan_set_station_ip(luat_wlan_station_info_t *info) {
    return 0;
}

int luat_drv_wlan_smartconfig_start(int tp) {
    return -1;
}

int luat_drv_wlan_smartconfig_stop(void) {
    return -1;
}

// 数据类
int luat_drv_wlan_get_mac(int id, char* mac) {
    return 0;
}
int luat_drv_wlan_set_mac(int id, const char* mac) {
    return 0;
}

int luat_drv_wlan_get_ip(int type, char* data) {
    return 0;
}

const char* luat_drv_wlan_get_hostname(int id) {
    return NULL;
}

int luat_drv_wlan_set_hostname(int id, const char* hostname) {
    return -1;
}

// 设置和获取省电模式
int luat_drv_wlan_set_ps(int mode) {
    return -1;
}

int luat_drv_wlan_get_ps(void) {
    return -1;
}

int luat_drv_wlan_get_ap_bssid(char* buff) {
    return -1;
}

int luat_drv_wlan_get_ap_rssi(void) {
    return -1;
}

int luat_drv_wlan_get_ap_gateway(char* buff) {
    return -1;
}


// AP类
int luat_drv_wlan_ap_start(luat_wlan_apinfo_t *apinfo) {
    return luat_airlink_drv_wlan_ap_start(apinfo);
}

int luat_drv_wlan_ap_stop(void) {
    return luat_airlink_drv_wlan_ap_stop();
}

// 下面的都是代理函数
#ifdef LUAT_USE_DRV_WLAN

// int luat_wlan_init(luat_wlan_config_t *conf) {
//     return luat_drv_wlan_init(conf);
// }

int luat_wlan_mode(luat_wlan_config_t *conf) {
    return luat_drv_wlan_mode(conf);
}

int luat_wlan_ready(void) {
    return luat_drv_wlan_ready();
}

int luat_wlan_connect(luat_wlan_conninfo_t* info) {
    return luat_drv_wlan_connect(info);
}

int luat_wlan_disconnect(void) {
    return luat_drv_wlan_disconnect();
}

// int luat_wlan_scan(void) {
//     return luat_drv_wlan_scan();
// }

// int luat_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit) {
//     return luat_drv_wlan_scan_get_result(results, ap_limit);
// }

int luat_wlan_set_station_ip(luat_wlan_station_info_t *info) {
    return luat_drv_wlan_set_station_ip(info);
}

int luat_wlan_smartconfig_start(int tp) {
    return luat_drv_wlan_smartconfig_start(tp);
}

int luat_wlan_smartconfig_stop(void) {
    return luat_drv_wlan_smartconfig_stop();
}

// 数据类
int luat_wlan_get_mac(int id, char* mac) {
    return luat_drv_wlan_get_mac(id, mac);
}
int luat_wlan_set_mac(int id, const char* mac) {
    return luat_drv_wlan_set_mac(id, mac);
}

int luat_wlan_get_ip(int type, char* data) {
    return luat_drv_wlan_get_ip(type, data);
}

const char* luat_wlan_get_hostname(int id) {
    return luat_drv_wlan_get_hostname(id);
}

int luat_wlan_set_hostname(int id, const char* hostname) {
    return luat_drv_wlan_set_hostname(id, hostname);
}

// 设置和获取省电模式
int luat_wlan_set_ps(int mode) {
    return luat_drv_wlan_set_ps(mode);
}

int luat_wlan_get_ps(void) {
    return luat_drv_wlan_get_ps();
}

int luat_wlan_get_ap_bssid(char* buff) {
    return luat_drv_wlan_get_ap_bssid(buff);
}

int luat_wlan_get_ap_rssi(void) {
    return luat_drv_wlan_get_ap_rssi();
}

int luat_wlan_get_ap_gateway(char* buff) {
    return luat_drv_wlan_get_ap_gateway(buff);
}

int luat_wlan_ap_start(luat_wlan_apinfo_t *apinfo) {
    return luat_drv_wlan_ap_start(apinfo);
}

int luat_wlan_ap_stop(void) {
    return luat_drv_wlan_ap_stop();
}

#endif

