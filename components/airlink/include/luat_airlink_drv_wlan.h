#ifndef LUAT_AIRLINK_DRV_WLAN_H
#define LUAT_AIRLINK_DRV_WLAN_H

#ifndef LUAT_AIRLINK_H
#error "include luat_airlink.h first"
#endif

// WLAN, 也就是wifi
#include "luat_wlan.h"
int luat_airlink_drv_wlan_init(luat_wlan_config_t *conf);

int luat_airlink_drv_wlan_mode(luat_wlan_config_t *conf);

int luat_airlink_drv_wlan_ready(void);

int luat_airlink_drv_wlan_connect(luat_wlan_conninfo_t* info);

int luat_airlink_drv_wlan_disconnect(void);

int luat_airlink_drv_wlan_scan(void);

int luat_airlink_drv_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit);

int luat_airlink_drv_wlan_set_station_ip(luat_wlan_station_info_t *info);

int luat_airlink_drv_wlan_smartconfig_start(int tp);

int luat_airlink_drv_wlan_smartconfig_stop(void);

// 数据类
int luat_airlink_drv_wlan_get_mac(int id, char* mac);
int luat_airlink_drv_wlan_set_mac(int id, const char* mac);

int luat_airlink_drv_wlan_get_ip(int type, char* data);

const char* luat_airlink_drv_wlan_get_hostname(int id);

int luat_airlink_drv_wlan_set_hostname(int id, const char* hostname);

// 设置和获取省电模式
int luat_airlink_drv_wlan_set_ps(int mode);

int luat_airlink_drv_wlan_get_ps(void);

int luat_airlink_drv_wlan_get_ap_bssid(char* buff);

int luat_airlink_drv_wlan_get_ap_rssi(void);

int luat_airlink_drv_wlan_get_ap_gateway(char* buff);


// AP类
int luat_airlink_drv_wlan_ap_start(luat_wlan_apinfo_t *apinfo);
int luat_airlink_drv_wlan_ap_stop(void);

#endif
